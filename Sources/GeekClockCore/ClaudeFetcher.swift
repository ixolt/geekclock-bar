import Foundation

/// What the in-page fetch script returned.
public struct PageReply: Equatable, Sendable {
    public var status: Int
    public var body: String
    public var url: String

    public init(status: Int, body: String, url: String) {
        self.status = status
        self.body = body
        self.url = url
    }
}

public enum FetchOutcome: Equatable, Sendable {
    case ok(Data)
    case signedOut
    case failed(String)
}

/// A claude.ai page that can run fetches; the app backs it with a WKWebView.
@MainActor
public protocol ClaudePage {
    /// Loads https://claude.ai/; true once the page is ready.
    func load() async -> Bool
    /// Fetches `path` from inside the page; throws when the script does.
    func fetch(_ path: String) async throws -> PageReply
}

/// Fetches claude.ai API paths through a page. A throwing script usually
/// means a killed web process or a Cloudflare challenge, so it reloads the
/// page and retries once before reporting the error.
@MainActor
public final class ClaudeFetcher {
    private let page: any ClaudePage
    private var pageReady = false

    public init(page: any ClaudePage) {
        self.page = page
    }

    /// Forgets the loaded page, so the next fetch reloads it.
    public func reset() {
        pageReady = false
    }

    public func get(_ path: String) async -> FetchOutcome {
        for attempt in 0..<2 {
            if !pageReady {
                guard await page.load() else { return .failed("claude.ai did not load") }
                pageReady = true
            }
            do {
                return interpret(try await page.fetch(path))
            } catch {
                pageReady = false
                if attempt == 1 { return .failed(error.localizedDescription) }
            }
        }
        return .failed("claude.ai did not load")
    }

    private func interpret(_ reply: PageReply) -> FetchOutcome {
        let isJSON = reply.body.hasPrefix("{") || reply.body.hasPrefix("[")
        if reply.status == 200 && isJSON { return .ok(Data(reply.body.utf8)) }
        if reply.status == 401 || reply.url.contains("/login")
            || (reply.status == 403 && isJSON && reply.body.contains("\"error\""))
        {
            return .signedOut
        }
        // Probably a Cloudflare challenge page: reload claude.ai next time.
        pageReady = false
        return .failed("HTTP \(reply.status)")
    }
}
