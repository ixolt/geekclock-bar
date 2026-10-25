import AppKit
import SwiftUI
import Foundation
import Testing
@testable import GeekClockCore

@MainActor @Test func jpegIs240Square() throws {
    let faces: [ClockFace] = [
        makeClockFace(state: freshState(), now: faceNow, timeZone: kyiv),
        .signedOut(headerTime: "05:30"),
    ]
    for face in faces {
        let data = try #require(renderClockFaceJPEG(face))
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 240)
        #expect(rep.pixelsHigh == 240)
    }
}

/// Writes PNGs to .build/previews/ for eyeballing against the approved mockup.
@MainActor @Test func writesPreviews() throws {
    var pastReset = freshState()
    pastReset.blocks[.fiveHour]?.resetsAt = faceNow - 1
    var busy = freshState()
    busy.blocks[.fiveHour]?.percent = 86
    busy.blocks[.sevenDay]?.percent = 55
    let faces: [(String, ClockFace)] = [
        ("fresh", makeClockFace(state: freshState(), now: faceNow, timeZone: kyiv)),
        ("busy", makeClockFace(state: busy, now: faceNow, timeZone: kyiv)),
        ("stale", makeClockFace(state: freshState(lastSuccess: faceNow - 1080), now: faceNow, timeZone: kyiv)),
        ("unknown-5h", makeClockFace(state: pastReset, now: faceNow, timeZone: kyiv)),
        ("no-model", makeClockFace(state: freshState(model: false), now: faceNow, timeZone: kyiv)),
        ("signed-out", .signedOut(headerTime: "05:30")),
    ]
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/previews")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for style in ClockFaceStyle.allCases {
        for (name, face) in faces {
            let png = try #require(renderClockFacePNG(face, style: style))
            try png.write(to: dir.appendingPathComponent("\(style.rawValue)-\(name).png"))
            if style.isAnimated {
                for activity in MonsterActivity.allCases {
                    let gif = try #require(renderClockImage(face, style: style, activity: activity))
                    try gif.data.write(to: dir.appendingPathComponent("\(style.rawValue)-\(name)-\(activity.rawValue).gif"))
                }
            }
        }
    }

    let five = freshState().display(.fiveHour, now: faceNow)
    let week = freshState().display(.sevenDay, now: faceNow)
    for style in MenuBarStyle.allCases {
        let png = try #require(renderPreviewPNG(MenuBarLabel(style: style, fiveHour: five, weekly: week)))
        try png.write(to: dir.appendingPathComponent("menubar-\(style.rawValue).png"))
    }
    let clock = (text: "Clock 192.168.1.50 · synced 05:30", color: Color.green)
    let panels: [(String, UsagePanelContent)] = [
        ("fresh", UsagePanelContent(usage: freshState(), now: faceNow, signedIn: true, usageLine: nil, clockLine: clock)),
        ("busy", UsagePanelContent(usage: busy, now: faceNow, signedIn: true, usageLine: nil, clockLine: clock)),
        ("signed-out", UsagePanelContent(usage: .empty, now: faceNow, signedIn: false, usageLine: nil, clockLine: clock)),
    ]
    for (name, panel) in panels {
        try #require(renderPreviewPNG(panel)).write(to: dir.appendingPathComponent("panel-\(name).png"))
    }
}
