import Foundation

/// A limit as last seen, with the time it was fetched.
public struct StoredBlock: Codable, Equatable, Sendable {
    public var percent: Double
    public var resetsAt: Date?
    public var label: String?
    public var fetchedAt: Date

    public init(percent: Double, resetsAt: Date?, label: String?, fetchedAt: Date) {
        self.percent = percent
        self.resetsAt = resetsAt
        self.label = label
        self.fetchedAt = fetchedAt
    }
}

/// What a limit should look like right now.
public enum BlockDisplay: Equatable, Sendable {
    case value(percent: Double, resetsInMinutes: Int?, label: String?)
    case unknown
}

/// Everything we know about the user's usage. Persisted between launches.
public struct UsageState: Codable, Equatable, Sendable {
    /// No fresh data for this long → shown as stale.
    public static let staleAfter: TimeInterval = 900
    /// A block older than this is hidden rather than shown as current.
    public static let hideAfter: TimeInterval = 43200

    public static let empty = UsageState(blocks: [:], lastSuccess: nil)

    public var blocks: [BlockKind: StoredBlock]
    public var lastSuccess: Date?

    public init(blocks: [BlockKind: StoredBlock], lastSuccess: Date?) {
        self.blocks = blocks
        self.lastSuccess = lastSuccess
    }

    /// Applies a fresh response. Blocks missing from it keep their previous
    /// value and fetch time, so a partial response never wipes good data.
    public func merging(_ fresh: [BlockKind: ParsedBlock], at now: Date) -> UsageState {
        var next = self
        for (kind, block) in fresh {
            next.blocks[kind] = StoredBlock(percent: block.percent, resetsAt: block.resetsAt,
                                            label: block.label, fetchedAt: now)
        }
        next.lastSuccess = now
        return next
    }

    public func display(_ kind: BlockKind, now: Date) -> BlockDisplay {
        guard let block = blocks[kind],
              now.timeIntervalSince(block.fetchedAt) <= Self.hideAfter else { return .unknown }
        // Once the window has reset, the stored percentage no longer applies.
        if let resetsAt = block.resetsAt, resetsAt < now { return .unknown }
        let minutes = block.resetsAt.map { max(0, Int($0.timeIntervalSince(now)) / 60) }
        return .value(percent: block.percent, resetsInMinutes: minutes, label: block.label)
    }

    public func isStale(now: Date) -> Bool {
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) > Self.staleAfter
    }
}
