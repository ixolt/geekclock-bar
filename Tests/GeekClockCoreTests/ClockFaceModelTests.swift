import Foundation
import Testing
@testable import GeekClockCore

let kyiv = TimeZone(identifier: "Europe/Kyiv")!
/// 2026-10-25T03:30:00Z — 05:30 in Kyiv.
let faceNow = parseISODate("2026-10-25T03:30:00Z")!

/// The numbers on the user's clock: 5h 7% (3h 29m left), weekly 13%, Fable 0% (4d left).
func freshState(lastSuccess: Date = faceNow - 60, model: Bool = true) -> UsageState {
    var blocks: [BlockKind: StoredBlock] = [
        .fiveHour: StoredBlock(percent: 7, resetsAt: faceNow + 209 * 60 + 30, label: nil, fetchedAt: lastSuccess),
        .sevenDay: StoredBlock(percent: 13, resetsAt: faceNow + 5760 * 60 + 30, label: nil, fetchedAt: lastSuccess),
    ]
    if model {
        blocks[.modelWeekly] = StoredBlock(percent: 0, resetsAt: faceNow + 5760 * 60 + 30, label: "Fable",
                                           fetchedAt: lastSuccess)
    }
    return UsageState(blocks: blocks, lastSuccess: lastSuccess)
}

private func usageFace(_ face: ClockFace) throws -> UsageFace {
    guard case .usage(let f) = face else { throw FaceError.notUsage }
    return f
}
private enum FaceError: Error { case notUsage }

@Test func freshFaceUsesCurrentTime() throws {
    let f = try usageFace(makeClockFace(state: freshState(), now: faceNow, timeZone: kyiv))
    #expect(f.headerText == "05:30")
    #expect(f.isStale == false)
    #expect(f.fiveHour.percentText == "7%")
    #expect(f.fiveHour.fraction == 0.07)
    #expect(f.fiveHour.level == .green)
    #expect(f.fiveHourCountdown == "3h 29m")
    #expect(f.weekly.title == "Weekly")
    #expect(f.weekly.percentText == "13%")
    #expect(f.model?.title == "Fable")
    #expect(f.model?.percentText == "0%")
    #expect(f.weeklyResetText == "weekly resets in 4d")
}

@Test func staleFaceShowsLastSuccessWithWarning() throws {
    let last = parseISODate("2026-10-25T03:12:00Z")!
    let f = try usageFace(makeClockFace(state: freshState(lastSuccess: last), now: faceNow, timeZone: kyiv))
    #expect(f.headerText == "⚠ 05:12")
    #expect(f.isStale == true)
}

/// The "Time" face shows the real time even when the numbers are stale.
@Test func staleFaceStillKnowsCurrentTime() throws {
    let last = parseISODate("2026-10-25T03:12:00Z")!
    let f = try usageFace(makeClockFace(state: freshState(lastSuccess: last), now: faceNow, timeZone: kyiv))
    #expect(f.currentTime == "05:30")
}

@Test func faceCarriesShortWeeklyCountdown() throws {
    let f = try usageFace(makeClockFace(state: freshState(), now: faceNow, timeZone: kyiv))
    #expect(f.weeklyCountdown == "4d")
}

@Test func noModelLimitOmitsRow() throws {
    let f = try usageFace(makeClockFace(state: freshState(model: false), now: faceNow, timeZone: kyiv))
    #expect(f.model == nil)
    #expect(f.weeklyResetText == "weekly resets in 4d")
}

@Test func unknownBlockRendersDash() throws {
    var state = freshState()
    state.blocks[.fiveHour]?.resetsAt = faceNow - 1
    let f = try usageFace(makeClockFace(state: state, now: faceNow, timeZone: kyiv))
    #expect(f.fiveHour.percentText == "—")
    #expect(f.fiveHour.fraction == 0)
    #expect(f.fiveHour.level == .unknown)
    #expect(f.fiveHourCountdown == "")
}

@Test func signedOutFace() {
    #expect(makeClockFace(state: nil, now: faceNow, timeZone: kyiv) == .signedOut(headerTime: "05:30"))
}
