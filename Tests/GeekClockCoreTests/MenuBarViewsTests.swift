import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GeekClockCore

private let five = BlockDisplay.value(percent: 7, resetsInMinutes: 209, label: nil)
private let week = BlockDisplay.value(percent: 13, resetsInMinutes: 5760, label: nil)

@MainActor @Test func menuBarLabelLooksDifferentInEveryStyle() throws {
    var images: Set<Data> = []
    for style in MenuBarStyle.allCases {
        images.insert(try #require(renderPreviewPNG(MenuBarLabel(style: style, fiveHour: five, weekly: week))))
    }
    #expect(images.count == MenuBarStyle.allCases.count)
}

@MainActor @Test func menuBarImageIsMenuBarHigh() {
    let image = menuBarImage(fiveHour: five, weekly: week, bars: true, dimmed: false)
    #expect(image.size.height == 18)
    #expect(image.size.width > image.size.height)
}

@MainActor @Test func panelIs280WideSignedInAndOut() throws {
    let clock = (text: "Clock 192.168.1.50 · synced 05:30", color: Color.green)
    let signedIn = UsagePanelContent(usage: freshState(), now: faceNow, signedIn: true, usageLine: nil, clockLine: clock)
    let signedOut = UsagePanelContent(usage: .empty, now: faceNow, signedIn: false, usageLine: nil, clockLine: clock)
    let inPNG = try #require(renderPreviewPNG(signedIn, scale: 1))
    let outPNG = try #require(renderPreviewPNG(signedOut, scale: 1))
    #expect(try #require(NSBitmapImageRep(data: inPNG)).pixelsWide == 280)
    #expect(try #require(NSBitmapImageRep(data: outPNG)).pixelsWide == 280)
    #expect(inPNG != outPNG)
}
