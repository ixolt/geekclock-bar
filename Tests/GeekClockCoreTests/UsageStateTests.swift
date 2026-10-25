import Foundation
import Testing
@testable import GeekClockCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func mergeKeepsMissingBlocks() {
    let state = UsageState(blocks: [.sevenDay: StoredBlock(percent: 13, resetsAt: nil, label: nil, fetchedAt: t0)],
                           lastSuccess: t0)
    let merged = state.merging([.fiveHour: ParsedBlock(percent: 7)], at: t0 + 300)
    #expect(merged.blocks[.fiveHour]?.percent == 7)
    #expect(merged.blocks[.fiveHour]?.fetchedAt == t0 + 300)
    #expect(merged.blocks[.sevenDay]?.percent == 13)
    #expect(merged.blocks[.sevenDay]?.fetchedAt == t0)
    #expect(merged.lastSuccess == t0 + 300)
}

@Test func displayShowsValueAndCountdown() {
    let state = UsageState(blocks: [.fiveHour: StoredBlock(percent: 7, resetsAt: t0 + 209 * 60, label: nil, fetchedAt: t0)],
                           lastSuccess: t0)
    #expect(state.display(.fiveHour, now: t0) == .value(percent: 7, resetsInMinutes: 209, label: nil))
}

@Test func blockOlderThan12hIsUnknown() {
    let state = UsageState(blocks: [.sevenDay: StoredBlock(percent: 13, resetsAt: nil, label: nil, fetchedAt: t0)],
                           lastSuccess: t0)
    #expect(state.display(.sevenDay, now: t0 + 43201) == .unknown)
    #expect(state.display(.sevenDay, now: t0 + 43199) == .value(percent: 13, resetsInMinutes: nil, label: nil))
}

@Test func blockPastResetIsUnknown() {
    let state = UsageState(blocks: [.fiveHour: StoredBlock(percent: 90, resetsAt: t0 + 60, label: nil, fetchedAt: t0)],
                           lastSuccess: t0)
    #expect(state.display(.fiveHour, now: t0 + 61) == .unknown)
}

@Test func missingBlockIsUnknown() {
    #expect(UsageState.empty.display(.modelWeekly, now: t0) == .unknown)
}

@Test func staleAfter15Minutes() {
    let state = UsageState(blocks: [:], lastSuccess: t0)
    #expect(state.isStale(now: t0 + 900) == false)
    #expect(state.isStale(now: t0 + 901) == true)
    #expect(UsageState.empty.isStale(now: t0) == true)
}

@Test func codableRoundTrip() throws {
    let state = UsageState(blocks: [
        .fiveHour: StoredBlock(percent: 7, resetsAt: t0 + 60, label: nil, fetchedAt: t0),
        .sevenDay: StoredBlock(percent: 13, resetsAt: nil, label: nil, fetchedAt: t0),
        .modelWeekly: StoredBlock(percent: 0, resetsAt: t0 + 999, label: "Fable", fetchedAt: t0),
    ], lastSuccess: t0)
    let decoded = try JSONDecoder().decode(UsageState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
}
