import AppKit
import SwiftUI

/// The settings window. Managed by hand like the sign-in window: SwiftUI's
/// Settings scene and SettingsLink don't reliably open from a menu-bar-only app.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            // A grouped Form scrolls, so it has no height of its own; letting the
            // hosting controller size the window would collapse it to the title bar.
            let controller = NSHostingController(rootView: SettingsView(model: model))
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "GeekClock Bar Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 420, height: 640))
            window.contentMinSize = NSSize(width: 380, height: 360)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
