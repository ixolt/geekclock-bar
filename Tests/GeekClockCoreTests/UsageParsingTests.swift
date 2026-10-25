import Foundation
import Testing
@testable import GeekClockCore

func fixtureData() throws -> Data {
    let url = try #require(Bundle.module.url(
        forResource: "usage_response_2026-09-04", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func json(_ s: String) -> Data { Data(s.utf8) }

@Test func fixtureParsesAllThreeBlocks() throws {
    let blocks = try parseUsage(fixtureData())
    #expect(blocks[.fiveHour]?.percent == 37)
    #expect(blocks[.sevenDay]?.percent == 27)
    #expect(blocks[.modelWeekly]?.percent == 32)
    #expect(blocks[.modelWeekly]?.label == "Fable")
    let expected = try #require(parseISODate("2026-09-04T18:49:59.978Z"))
    let actual = try #require(blocks[.fiveHour]?.resetsAt)
    #expect(abs(actual.timeIntervalSince(expected)) < 0.001)
}

@Test func parsesSixDigitFractionWithOffset() throws {
    let date = try #require(parseISODate("2026-09-04T18:49:59.978553+00:00"))
    let whole = try #require(parseISODate("2026-09-04T18:49:59Z"))
    #expect(abs(date.timeIntervalSince(whole) - 0.978553) < 0.001)
}

@Test func parsesWithoutFraction() {
    #expect(parseISODate("2026-09-06T17:59:59Z") != nil)
}

@Test func nullAndMissingBlocksAreAbsent() throws {
    let blocks = try parseUsage(json(#"{"five_hour":null,"seven_day":{"utilization":5,"resets_at":null}}"#))
    #expect(Set(blocks.keys) == Set([BlockKind.sevenDay]))
    #expect(blocks[.sevenDay]?.percent == 5)
    #expect(blocks[.sevenDay]?.resetsAt == nil)
}

@Test func boolOrStringUtilizationIsIgnored() throws {
    let blocks = try parseUsage(json(#"{"five_hour":{"utilization":true},"seven_day":{"utilization":"7"}}"#))
    #expect(blocks.isEmpty)
}

@Test func modelWeeklyNeedsDisplayName() throws {
    let blocks = try parseUsage(json("""
        {"limits":[
          {"kind":"weekly_scoped","percent":50,"scope":null},
          {"kind":"weekly_scoped","percent":12,"resets_at":null,"scope":{"model":{"display_name":"Opus"}}}
        ]}
        """))
    #expect(blocks[.modelWeekly]?.label == "Opus")
    #expect(blocks[.modelWeekly]?.percent == 12)
}

@Test func nonObjectThrows() {
    #expect(throws: UsageParseError.notAnObject) { try parseUsage(json("[]")) }
}

@Test func orgIdFromArray() {
    #expect(parseOrganizationID(json(#"[{"uuid":"abc"},{"uuid":"def"}]"#)) == "abc")
    #expect(parseOrganizationID(json("[]")) == nil)
    #expect(parseOrganizationID(json("{}")) == nil)
}
