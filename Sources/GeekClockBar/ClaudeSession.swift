import Foundation
import GeekClockCore
import WebKit

enum SessionError: LocalizedError, Equatable {
    case signedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .signedOut: "Signed out"
        case .failed(let message): message
        }
    }
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
    private let page: WebViewPage
    private let fetcher: ClaudeFetcher

    init() {
        page = WebViewPage()
        fetcher = ClaudeFetcher(page: page)
    }

    func organizationID() async -> Result<String, SessionError> {
        switch await fetcher.get("/api/organizations") {
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
        await fetcher.get("/api/organizations/\(orgID)/usage")
    }

    /// The account's email address, if claude.ai tells us.
    func accountLabel() async -> String? {
        guard case .ok(let data) = await fetcher.get("/api/account"),
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
        fetcher.reset()
    }
}

/// The off-screen claude.ai page, backed by a WKWebView.
@MainActor
private final class WebViewPage: ClaudePage {
    private let webView: WKWebView

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.customUserAgent = safariUserAgent
    }

    /// Loads https://claude.ai/ so fetches run on a claude.ai page.
    func load() async -> Bool {
        webView.load(URLRequest(url: URL(string: "https://claude.ai/")!))
        for _ in 0..<80 {  // up to 20 s
            try? await Task.sleep(for: .milliseconds(250))
            if !webView.isLoading, webView.url?.host == "claude.ai" {
                return true
            }
        }
        return false
    }

    func fetch(_ path: String) async throws -> PageReply {
        let script = """
            const r = await fetch(path, {credentials: 'include', headers: {'accept': 'application/json'}});
            return {status: r.status, body: await r.text(), url: r.url};
            """
        let result = try await webView.callAsyncJavaScript(
            script, arguments: ["path": path], contentWorld: .defaultClient)
        guard let reply = result as? [String: Any],
              let status = (reply["status"] as? NSNumber)?.intValue,
              let body = reply["body"] as? String else {
            throw SessionError.failed("Unexpected reply from claude.ai")
        }
        return PageReply(status: status, body: body, url: reply["url"] as? String ?? "")
    }
}
