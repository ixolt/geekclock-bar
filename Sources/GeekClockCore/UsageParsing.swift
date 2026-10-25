import Foundation

/// The three limits shown in the app and on the clock.
public enum BlockKind: String, CaseIterable, Codable, Sendable, CodingKeyRepresentable {
    case fiveHour, sevenDay, modelWeekly
}

/// One limit as read from a single `/usage` response.
public struct ParsedBlock: Equatable, Sendable {
    public var percent: Double
    public var resetsAt: Date?
    public var label: String?

    public init(percent: Double, resetsAt: Date? = nil, label: String? = nil) {
        self.percent = percent
        self.resetsAt = resetsAt
        self.label = label
    }
}

public enum UsageParseError: Error, Equatable {
    case notAnObject
}

/// Extracts the limits we show from `GET /api/organizations/{org}/usage`.
/// Blocks that are missing, null, or carry a non-numeric value are left out.
public func parseUsage(_ data: Data) throws -> [BlockKind: ParsedBlock] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UsageParseError.notAnObject
    }
    var blocks: [BlockKind: ParsedBlock] = [:]
    for (kind, key) in [(BlockKind.fiveHour, "five_hour"), (.sevenDay, "seven_day")] {
        guard let entry = root[key] as? [String: Any],
              let pct = number(entry["utilization"]) else { continue }
        blocks[kind] = ParsedBlock(percent: pct, resetsAt: date(entry["resets_at"]))
    }
    // The per-model weekly limit lives in "limits" as kind=weekly_scoped
    // with scope.model.display_name (e.g. "Fable").
    for item in root["limits"] as? [[String: Any]] ?? [] {
        guard item["kind"] as? String == "weekly_scoped",
              let scope = item["scope"] as? [String: Any],
              let model = scope["model"] as? [String: Any],
              let label = model["display_name"] as? String, !label.isEmpty,
              let pct = number(item["percent"]) else { continue }
        blocks[.modelWeekly] = ParsedBlock(percent: pct, resetsAt: date(item["resets_at"]), label: label)
        break
    }
    return blocks
}

/// `[0].uuid` of `GET /api/organizations`, or nil.
public func parseOrganizationID(_ data: Data) -> String? {
    guard let orgs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
    return orgs.first?["uuid"] as? String
}

/// Parses ISO 8601 timestamps as claude.ai sends them, including
/// microsecond fractions ("2026-09-04T18:49:59.978553+00:00").
public func parseISODate(_ string: String) -> Date? {
    let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    if let d = try? withFraction.parse(string) { return d }
    if let d = try? Date.ISO8601FormatStyle().parse(string) { return d }
    // Trim the fraction to milliseconds and retry.
    guard let dot = string.firstIndex(of: ".") else { return nil }
    let digits = string[string.index(after: dot)...].prefix { $0.isNumber }
    guard digits.count > 3 else { return nil }
    let trimmed = string[..<dot] + "." + digits.prefix(3) + string[digits.endIndex...]
    return try? withFraction.parse(String(trimmed))
}

private func number(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}

private func date(_ value: Any?) -> Date? {
    (value as? String).flatMap(parseISODate)
}
