import Foundation
import GeekClockCore
import WebKit

enum FetchOutcome: Sendable {
    case ok(Data)
    case signedOut
    case failed(String)
}

enum SessionError: Error, Equatable {
    case signedOut
    case failed(String)
}

/// Safari's user agent, so claude.ai and Cloudflare treat the web views like
/// a normal browser tab.
let safariUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

/// Calls claude.ai's web API from inside an off-screen web view, so requests
/// carry the signed-in browser session (cookies, Cloudflare clearance) and
/// WebKit keeps that session refreshed for us.
@MainActor
final class ClaudeSession {
    private let webView: WKWebView
    private var pageReady = false

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.customUserAgent = safariUserAgent
    }

    func organizationID() async -> Result<String, SessionError> {
        switch await get("/api/organizations") {
        case .ok(let data):
            guard let id = parseOrganizationID(data) else { return .failure(.failed("No organization found")) }
            return .success(id)
        case .signedOut:
            return .failure(.signedOut)
        case .failed(let message):
            return .failure(.failed(message))
        }
    }

    func usage(orgID: String) async -> FetchOutcome {
        await get("/api/organizations/\(orgID)/usage")
    }

    /// The account's email address, if claude.ai tells us.
    func accountLabel() async -> String? {
        guard case .ok(let data) = await get("/api/account"),
              let account = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return account["email_address"] as? String
    }

    func signOut() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types).filter {
            $0.displayName.contains("claude.ai") || $0.displayName.contains("anthropic")
        }
        await store.removeData(ofTypes: types, for: records)
        pageReady = false
    }

    private func get(_ path: String) async -> FetchOutcome {
        if !pageReady {
            guard await loadHomePage() else { return .failed("claude.ai did not load") }
        }
        let script = """
            const r = await fetch(path, {credentials: 'include', headers: {'accept': 'application/json'}});
            return {status: r.status, body: await r.text(), url: r.url};
            """
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(script, arguments: ["path": path], contentWorld: .defaultClient)
        } catch {
            pageReady = false
            return .failed(error.localizedDescription)
        }
        guard let reply = result as? [String: Any],
              let status = (reply["status"] as? NSNumber)?.intValue,
              let body = reply["body"] as? String else {
            return .failed("Unexpected reply from claude.ai")
        }
        let url = reply["url"] as? String ?? ""
        let isJSON = body.hasPrefix("{") || body.hasPrefix("[")

        if status == 200 && isJSON { return .ok(Data(body.utf8)) }
        if status == 401 || url.contains("/login") || (status == 403 && isJSON && body.contains("\"error\"")) {
            return .signedOut
        }
        // Probably a Cloudflare challenge page: reload claude.ai next time.
        pageReady = false
        return .failed("HTTP \(status)")
    }

    /// Loads https://claude.ai/ so fetches run on a claude.ai page.
    private func loadHomePage() async -> Bool {
        webView.load(URLRequest(url: URL(string: "https://claude.ai/")!))
        for _ in 0..<80 {  // up to 20 s
            try? await Task.sleep(for: .milliseconds(250))
            if !webView.isLoading, webView.url?.host == "claude.ai" {
                pageReady = true
                return true
            }
        }
        return false
    }
}
