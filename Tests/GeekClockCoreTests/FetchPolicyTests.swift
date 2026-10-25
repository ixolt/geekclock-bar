import Foundation
import Testing
@testable import GeekClockCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func fetchPolicy() {
    #expect(shouldFetch(now: t0, lastAttempt: nil, panelOpened: false))
    #expect(!shouldFetch(now: t0 + 299, lastAttempt: t0, panelOpened: false))
    #expect(shouldFetch(now: t0 + 300, lastAttempt: t0, panelOpened: false))
    #expect(shouldFetch(now: t0 + 61, lastAttempt: t0, panelOpened: true))
    #expect(!shouldFetch(now: t0 + 60, lastAttempt: t0, panelOpened: true))
    #expect(!shouldFetch(now: t0 + 10, lastAttempt: t0, panelOpened: true))
}

/// The clock shows HH:MM, so updates land on the minute rather than at launch time + 60 s.
@Test func ticksLandOnTheNextWholeMinute() {
    let minute = parseISODate("2026-10-25T03:31:00Z")!
    #expect(nextMinute(after: minute - 42.5) == minute)
    #expect(nextMinute(after: minute) == minute + 60)
}
