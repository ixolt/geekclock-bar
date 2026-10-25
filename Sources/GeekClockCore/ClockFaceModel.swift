import Foundation

/// One limit, ready to draw.
public struct FaceRow: Equatable, Sendable {
    public var title: String
    public var percentText: String
    public var fraction: Double
    public var level: UsageLevel

    func with(title: String) -> FaceRow {
        var row = self
        row.title = title
        return row
    }
}

/// Everything a clock face shows, whichever layout draws it.
public struct UsageFace: Equatable, Sendable {
    /// Current time ("05:30"), or "⚠ 05:12" with the last good fetch when stale.
    public var headerText: String
    /// The current time, stale or not.
    public var currentTime: String
    public var isStale: Bool
    public var fiveHour: FaceRow
    public var fiveHourCountdown: String
    public var weekly: FaceRow
    public var model: FaceRow?
    public var weeklyResetText: String
    /// "4d", or empty when unknown.
    public var weeklyCountdown: String
}

public enum ClockFace: Equatable, Sendable {
    case usage(UsageFace)
    case signedOut(headerTime: String)
}

/// Builds the clock face. `state == nil` means the user is signed out.
public func makeClockFace(state: UsageState?, now: Date, timeZone: TimeZone) -> ClockFace {
    guard let state else { return .signedOut(headerTime: clockTime(now, timeZone)) }

    let stale = state.isStale(now: now)
    let header = stale
        ? "⚠ " + (state.lastSuccess.map { clockTime($0, timeZone) } ?? "--:--")
        : clockTime(now, timeZone)

    let five = state.display(.fiveHour, now: now)
    let week = state.display(.sevenDay, now: now)
    let model = state.display(.modelWeekly, now: now)
    let modelLabel = state.blocks[.modelWeekly]?.label

    // The weekly limits reset together; show the countdown once, from the
    // last weekly row that has one.
    let weeklyCountdown = [model, week].lazy.compactMap(countdown).first { !$0.isEmpty } ?? ""

    return .usage(UsageFace(
        headerText: header,
        currentTime: clockTime(now, timeZone),
        isStale: stale,
        fiveHour: row("5-hour", five),
        fiveHourCountdown: countdown(five) ?? "",
        weekly: row("Weekly", week),
        model: modelLabel.map { row($0, model) },
        weeklyResetText: weeklyCountdown.isEmpty ? "" : "weekly resets in " + weeklyCountdown,
        weeklyCountdown: weeklyCountdown
    ))
}

private func row(_ title: String, _ display: BlockDisplay) -> FaceRow {
    var percent: Double?
    if case .value(let p, _, _) = display { percent = p }
    return FaceRow(title: title,
                   percentText: formatPercent(display),
                   fraction: min(max((percent ?? 0) / 100, 0), 1),
                   level: usageLevel(percent))
}

private func countdown(_ display: BlockDisplay) -> String? {
    guard case .value(_, let minutes?, _) = display else { return nil }
    return formatCountdown(minutes: minutes)
}

private func clockTime(_ date: Date, _ timeZone: TimeZone) -> String {
    var style = Date.FormatStyle(date: .omitted, time: .omitted)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    style.timeZone = timeZone
    style.locale = Locale(identifier: "en_GB")
    return date.formatted(style)
}
