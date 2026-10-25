import AppKit
import SwiftUI

/// The menu bar item: the pixel monster, then the chosen style's two stacked
/// mini bars (5-hour on top, weekly below) and/or text. The image is dimmed
/// when the numbers are stale. The status item takes one image and one title,
/// so the text sits after the image rather than between the bars.
public struct MenuBarLabel: View {
    private let style: MenuBarStyle
    private let fiveHour: BlockDisplay
    private let weekly: BlockDisplay
    private let dimmed: Bool

    public init(style: MenuBarStyle, fiveHour: BlockDisplay, weekly: BlockDisplay, dimmed: Bool = false) {
        self.style = style
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.dimmed = dimmed
    }

    public var body: some View {
        let image = Image(nsImage: menuBarImage(fiveHour: fiveHour, weekly: weekly, bars: style.showsBars,
                                                dimmed: dimmed))
        if let text = menuBarText(style, fiveHour: fiveHour, weekly: weekly) {
            HStack(spacing: 4) {
                image
                Text(text).monospacedDigit()
            }
        } else {
            image
        }
    }
}

/// The image part of the menu bar item, 18 pt high.
@MainActor
public func menuBarImage(fiveHour: BlockDisplay, weekly: BlockDisplay, bars: Bool, dimmed: Bool) -> NSImage {
    let content = HStack(spacing: 4) {
        PixelMonster(scale: 1)
        if bars {
            VStack(spacing: 2) {
                menuBarBar(fiveHour)
                menuBarBar(weekly)
            }
        }
    }
    .frame(height: 18)
    .opacity(dimmed ? 0.4 : 1)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let cgImage = renderer.cgImage else { return NSImage() }
    let image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / 2,
                                                       height: CGFloat(cgImage.height) / 2))
    image.isTemplate = false
    return image
}

@MainActor
private func menuBarBar(_ display: BlockDisplay) -> some View {
    var percent: Double?
    if case .value(let p, _, _) = display { percent = p }
    return UsageBar(fraction: min(max((percent ?? 0) / 100, 0), 1), level: usageLevel(percent), height: 4)
        .frame(width: 28)
}

/// The panel that opens from the menu bar item. The app supplies the status
/// lines and the actions.
public struct UsagePanelContent: View {
    private let usage: UsageState
    private let now: Date
    private let signedIn: Bool
    private let signInDisabled: Bool
    private let usageLine: (text: String, isError: Bool)?
    private let clockLine: (text: String, color: Color)
    private let onSignIn: @MainActor () -> Void
    private let onSettings: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void

    public init(usage: UsageState, now: Date, signedIn: Bool, signInDisabled: Bool = false,
                usageLine: (text: String, isError: Bool)?, clockLine: (text: String, color: Color),
                onSignIn: @escaping @MainActor () -> Void = {}, onSettings: @escaping @MainActor () -> Void = {},
                onQuit: @escaping @MainActor () -> Void = {}) {
        self.usage = usage
        self.now = now
        self.signedIn = signedIn
        self.signInDisabled = signInDisabled
        self.usageLine = usageLine
        self.clockLine = clockLine
        self.onSignIn = onSignIn
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if signedIn {
                usageRows
            } else {
                signedOutRows
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Rows

    private var usageRows: some View {
        let five = usage.display(.fiveHour, now: now)
        let week = usage.display(.sevenDay, now: now)
        let modelLimit = usage.blocks[.modelWeekly].map { ($0.label ?? "Model", usage.display(.modelWeekly, now: now)) }
        let weeklyReset = [modelLimit?.1, week].compactMap { $0 }.compactMap(countdown).first { !$0.isEmpty }

        return VStack(alignment: .leading, spacing: 12) {
            row("Current (5h)", five, caption: countdown(five).flatMap { $0.isEmpty ? nil : "Resets in \($0)" })
            row("Weekly", week, caption: modelLimit == nil ? weeklyReset.map { "Weekly resets in \($0)" } : nil)
            if let (label, display) = modelLimit {
                row(label, display, caption: weeklyReset.map { "Weekly resets in \($0)" })
            }
        }
        .opacity(usage.isStale(now: now) ? 0.6 : 1)
    }

    private var signedOutRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Current (5h)", .unknown, caption: nil)
            row("Weekly", .unknown, caption: nil)
            Button("Sign in again") { onSignIn() }
                .buttonStyle(.borderedProminent)
                .disabled(signInDisabled)
        }
    }

    private func row(_ title: String, _ display: BlockDisplay, caption: String?) -> some View {
        var percent: Double?
        if case .value(let p, _, _) = display { percent = p }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(formatPercent(display)).monospacedDigit()
            }
            UsageBar(fraction: min(max((percent ?? 0) / 100, 0), 1), level: usageLevel(percent), height: 8)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func countdown(_ display: BlockDisplay) -> String? {
        guard case .value(_, let minutes?, _) = display else { return nil }
        return formatCountdown(minutes: minutes)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let usageLine {
                Text(usageLine.text).foregroundStyle(usageLine.isError ? .red : .secondary)
            }
            HStack(spacing: 6) {
                Circle().fill(clockLine.color).frame(width: 7, height: 7)
                Text(clockLine.text).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button(action: onSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("Settings")
                Button(action: onQuit) { Image(systemName: "power") }
                    .buttonStyle(.borderless).help("Quit GeekClock Bar")
            }
        }
        .font(.caption)
    }
}
