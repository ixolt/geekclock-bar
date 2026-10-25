import Foundation

/// What the menu bar item shows next to the pixel monster.
public enum MenuBarStyle: String, CaseIterable, Codable, Sendable {
    case numbers, bars, countdown, barsAndNumbers

    public var title: String {
        switch self {
        case .numbers: "Two numbers"
        case .bars: "Mini bars"
        case .countdown: "Number + countdown"
        case .barsAndNumbers: "Bars + numbers"
        }
    }

    public var showsBars: Bool { self == .bars || self == .barsAndNumbers }
}

/// The layout of the 240×240 image sent to the clock.
public enum ClockFaceStyle: String, CaseIterable, Codable, Sendable {
    case rings, bigNumber, bars, minimal, time, gauge, columns, tiles, mood

    public var title: String {
        switch self {
        case .rings: "Rings"
        case .bigNumber: "Big number"
        case .bars: "Bars"
        case .minimal: "Minimal"
        case .time: "Time first"
        case .gauge: "Gauge"
        case .columns: "Columns"
        case .tiles: "Tiles"
        case .mood: "Mood monster (animated)"
        }
    }

    /// Sent as a looping GIF rather than a JPEG.
    public var isAnimated: Bool { self == .mood }
}

/// The text beside the menu bar icon, or nil when the style has none.
public func menuBarText(_ style: MenuBarStyle, fiveHour: BlockDisplay, weekly: BlockDisplay) -> String? {
    switch style {
    case .bars:
        return nil
    case .numbers, .barsAndNumbers:
        return formatPercent(fiveHour) + " · " + formatPercent(weekly)
    case .countdown:
        guard case .value(_, let minutes?, _) = fiveHour, !formatCountdown(minutes: minutes).isEmpty else {
            return formatPercent(fiveHour)
        }
        return formatPercent(fiveHour) + " · " + formatCountdown(minutes: minutes)
    }
}
