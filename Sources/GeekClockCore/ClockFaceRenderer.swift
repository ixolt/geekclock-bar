import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The clock's display is 240×240 px; render at scale 1 so 1 pt = 1 px.
@MainActor
private func renderCGImage(_ face: ClockFace, style: ClockFaceStyle, frame: Int = 0,
                           activity: MonsterActivity = .wave) -> CGImage? {
    let renderer = ImageRenderer(content: ClockFaceView(face: face, style: style, frame: frame, activity: activity))
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: 240, height: 240)
    return renderer.cgImage
}

@MainActor
private func renderBitmap(_ face: ClockFace, style: ClockFaceStyle) -> NSBitmapImageRep? {
    renderCGImage(face, style: style).map(NSBitmapImageRep.init(cgImage:))
}

/// The file to send to the clock: a looping GIF for animated faces, else a JPEG.
@MainActor
public func renderClockImage(_ face: ClockFace, style: ClockFaceStyle,
                             activity: MonsterActivity = .wave) -> ClockImage? {
    guard style.isAnimated else { return renderClockFaceJPEG(face, style: style).map(ClockImage.jpeg) }

    let data = NSMutableData()
    guard let gif = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString,
                                                     activity.frameCount, nil) else { return nil }
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: activity.frameDelay]]
    for frame in 0..<activity.frameCount {
        guard let image = renderCGImage(face, style: style, frame: frame, activity: activity) else { return nil }
        CGImageDestinationAddImage(gif, image, frameProperties as CFDictionary)
    }
    guard CGImageDestinationFinalize(gif) else { return nil }
    return .gif(data as Data)
}

@MainActor
public func renderClockFaceJPEG(_ face: ClockFace, style: ClockFaceStyle = .bigNumber) -> Data? {
    renderBitmap(face, style: style)?.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
}

/// Any view as a dark-mode PNG, for previews and the README. Goes through a
/// hosting view rather than ImageRenderer, which can't draw AppKit-backed
/// controls such as buttons.
@MainActor
func renderPreviewPNG(_ view: some View, scale: CGFloat = 2) -> Data? {
    let host = NSHostingView(rootView: view)
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                                     pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
}

@MainActor
public func renderClockFacePNG(_ face: ClockFace, style: ClockFaceStyle = .bigNumber) -> Data? {
    renderBitmap(face, style: style)?.representation(using: .png, properties: [:])
}
