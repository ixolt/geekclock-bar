import Foundation

/// "37m", "1h 35m", "4h", "6d 8h", "4d"; empty when the time is up.
public func formatCountdown(minutes: Int) -> String {
    guard minutes > 0 else { return "" }
    let days = minutes / (24 * 60)
    let hours = minutes % (24 * 60) / 60
    let mins = minutes % 60
    if days >= 1 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
    if hours >= 1 { return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h" }
    return "\(mins)m"
}

public enum UsageLevel: Equatable, Sendable {
    case green, yellow, red, unknown
}

/// Same thresholds as the original script: <50 green, 50–80 yellow, ≥80 red.
public func usageLevel(_ percent: Double?) -> UsageLevel {
    guard let percent else { return .unknown }
    if percent >= 80 { return .red }
    if percent >= 50 { return .yellow }
    return .green
}

public func formatPercent(_ display: BlockDisplay) -> String {
    guard case .value(let percent, _, _) = display else { return "—" }
    return "\(Int(percent.rounded()))%"
}
