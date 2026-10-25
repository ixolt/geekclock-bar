import AppKit
import GeekClockCore
import SwiftUI

/// The panel that opens from the menu bar item, fed from the model.
struct UsagePanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        UsagePanelContent(usage: model.usage, now: model.now, signedIn: model.isSignedIn,
                          signInDisabled: model.auth == .checking, usageLine: usageLine, clockLine: clockLine,
                          onSignIn: { model.signIn() }, onSettings: { model.openSettings() },
                          onQuit: { NSApp.terminate(nil) })
            .onAppear { model.panelOpened() }
    }

    private var usageLine: (text: String, isError: Bool)? {
        guard model.isSignedIn else { return nil }
        var parts: [String] = []
        if model.usage.isStale(now: model.now) {
            if let last = model.usage.lastSuccess {
                parts.append("Updated \(Int(model.now.timeIntervalSince(last) / 60)) min ago")
            } else {
                parts.append("Not updated yet")
            }
        }
        if let error = model.lastError { parts.append(error) }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), model.lastError != nil)
    }

    private var clockLine: (text: String, color: Color) {
        switch model.clockStatus {
        case .disabled: ("Clock updates off", .gray)
        case .notConfigured: ("Clock not set up", .gray)
        case .ok(let date): ("Clock \(model.clockIP) · synced \(date.formatted(date: .omitted, time: .shortened))", .green)
        case .failed(let reason): ("Clock: \(reason)", .red)
        }
    }
}
