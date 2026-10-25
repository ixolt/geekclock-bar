import AppKit
import ImageIO
import Foundation
import Testing
@testable import GeekClockCore

private let five = BlockDisplay.value(percent: 7, resetsInMinutes: 209, label: nil)
private let week = BlockDisplay.value(percent: 13, resetsInMinutes: 5760, label: nil)

@Test func menuBarTextPerStyle() {
    #expect(menuBarText(.numbers, fiveHour: five, weekly: week) == "7% · 13%")
    #expect(menuBarText(.bars, fiveHour: five, weekly: week) == nil)
    #expect(menuBarText(.countdown, fiveHour: five, weekly: week) == "7% · 3h 29m")
    #expect(menuBarText(.barsAndNumbers, fiveHour: five, weekly: week) == "7% · 13%")
}

@Test func menuBarTextWhenUnknown() {
    #expect(menuBarText(.numbers, fiveHour: .unknown, weekly: .unknown) == "— · —")
    #expect(menuBarText(.countdown, fiveHour: .unknown, weekly: week) == "—")
}

/// The raw values are saved in UserDefaults; renaming one would reset the user's choice.
@Test func styleRawValuesAreStable() {
    #expect(MenuBarStyle.allCases.map(\.rawValue) == ["numbers", "bars", "countdown", "barsAndNumbers"])
    #expect(ClockFaceStyle.allCases.map(\.rawValue) == ["rings", "bigNumber", "bars", "minimal", "time", "gauge",
                                                         "columns", "tiles", "mood"])
}

@MainActor @Test func everyClockFaceStyleRenders240SquareAndLooksDifferent() throws {
    let face = makeClockFace(state: freshState(), now: faceNow, timeZone: kyiv)
    var images: Set<Data> = []
    for style in ClockFaceStyle.allCases {
        let png = try #require(renderClockFacePNG(face, style: style))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == 240)
        #expect(rep.pixelsHigh == 240)
        images.insert(png)
    }
    #expect(images.count == ClockFaceStyle.allCases.count)
}

private func gifFrames(_ data: Data) throws -> (count: Int, firstDelay: Double, width: Int) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    let delay = gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (CGImageSourceGetCount(source), delay, image.width)
}

@MainActor @Test func everyMonsterActivityIsALoopingGIFWithItsOwnTiming() throws {
    let face = makeClockFace(state: freshState(), now: faceNow, timeZone: kyiv)
    var gifs: Set<Data> = []
    for activity in MonsterActivity.allCases {
        let image = try #require(renderClockImage(face, style: .mood, activity: activity))
        #expect(image.fileName == "claude.gif")
        let frames = try gifFrames(image.data)
        #expect(frames.count == activity.frameCount)
        #expect(abs(frames.firstDelay - activity.frameDelay) < 0.011)
        #expect(frames.width == 240)
        gifs.insert(image.data)
    }
    #expect(gifs.count == MonsterActivity.allCases.count)
}

@MainActor @Test func stillFacesStayJPEG() throws {
    let face = makeClockFace(state: freshState(), now: faceNow, timeZone: kyiv)
    for style in ClockFaceStyle.allCases where style != .mood {
        #expect(try #require(renderClockImage(face, style: style)).fileName == "claude.jpg")
    }
}
