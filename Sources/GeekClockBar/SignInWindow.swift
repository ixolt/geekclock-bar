import AppKit
import WebKit

/// A window with the real claude.ai login page. Closes itself once the
/// session can see the account's organization.
@MainActor
final class SignInWindowController: NSObject, NSWindowDelegate {
    private let session: ClaudeSession
    private let onSignedIn: (String) -> Void
    private var window: NSWindow?
    private var pollTask: Task<Void, Never>?

    init(session: ClaudeSession, onSignedIn: @escaping (String) -> Void) {
        self.session = session
        self.onSignedIn = onSignedIn
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariUserAgent
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign in to Claude"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.window?.isVisible == true else { return }
                if case .success(let orgID) = await self.session.organizationID() {
                    self.close()
                    self.onSignedIn(orgID)
                    return
                }
            }
        }
    }

    func close() {
        window?.close()
    }

    /// Closed by us or by the user: stop polling and forget the window, so the
    /// next `show()` opens a fresh one that polls again.
    func windowWillClose(_ notification: Notification) {
        pollTask?.cancel()
        pollTask = nil
        window?.delegate = nil
        window = nil
    }
}
