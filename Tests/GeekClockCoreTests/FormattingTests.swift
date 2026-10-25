import Foundation
import Testing
@testable import GeekClockCore

@Test func countdownFormats() {
    #expect(formatCountdown(minutes: 37) == "37m")
    #expect(formatCountdown(minutes: 95) == "1h 35m")
    #expect(formatCountdown(minutes: 240) == "4h")
    #expect(formatCountdown(minutes: 9120) == "6d 8h")
    #expect(formatCountdown(minutes: 5760) == "4d")
    #expect(formatCountdown(minutes: 0) == "")
    #expect(formatCountdown(minutes: -5) == "")
}

@Test func levels() {
    #expect(usageLevel(nil) == .unknown)
    #expect(usageLevel(0) == .green)
    #expect(usageLevel(49.9) == .green)
    #expect(usageLevel(50) == .yellow)
    #expect(usageLevel(79.9) == .yellow)
    #expect(usageLevel(80) == .red)
    #expect(usageLevel(100) == .red)
}

@Test func percentText() {
    #expect(formatPercent(.value(percent: 7.0, resetsInMinutes: nil, label: nil)) == "7%")
    #expect(formatPercent(.value(percent: 13.4, resetsInMinutes: nil, label: nil)) == "13%")
    #expect(formatPercent(.unknown) == "—")
}
