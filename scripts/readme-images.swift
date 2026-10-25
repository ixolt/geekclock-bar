// Builds the README images from the previews the test suite renders.
// Run via scripts/readme-images.sh.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let previews = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let background = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)

func image(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: previews.appendingPathComponent(name)) else {
        fatalError("missing \(name); run scripts/test.sh first")
    }
    return image
}

/// The size of a preview in pixels; the menu bar and panel previews are 2x.
func pixels(_ image: NSImage) -> NSSize {
    NSSize(width: image.representations[0].pixelsWide, height: image.representations[0].pixelsHigh)
}

/// Draws into a new bitmap of the given pixel size and writes it as a PNG.
/// `draw` gets the canvas height, since AppKit counts y from the bottom.
func canvas(width: Int, height: Int, to name: String, draw: (CGFloat) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("wrote docs/images/\(name)")
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor,
          align: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    return [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
}

/// Lays images out in a grid with a caption under each and writes a PNG.
func grid(_ items: [(file: String, caption: String)], columns: Int, to name: String) {
    let cell = 240, gap = 24, caption = 30
    let rows = (items.count + columns - 1) / columns
    let width = columns * cell + (columns + 1) * gap
    let height = rows * (cell + caption) + (rows + 1) * gap
    let attributes = text("", size: 16, weight: .semibold, color: NSColor(white: 0.85, alpha: 1), align: .center)
    canvas(width: width, height: height, to: name) { height in
        background.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: height).fill()
        for (n, item) in items.enumerated() {
            let x = gap + (n % columns) * (cell + gap)
            let top = gap + (n / columns) * (cell + caption + gap)
            let y = Int(height) - top - cell
            image(item.file).draw(in: NSRect(x: x, y: y, width: cell, height: cell))
            item.caption.draw(in: NSRect(x: x, y: y - caption, width: cell, height: caption - 6),
                              withAttributes: attributes)
        }
    }
}

let menuBarColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1)

/// The menu bar with the item in it and the panel open below, on a desktop.
func tray(label: String, panel: String, to name: String) {
    let label = image(label), panel = image(panel)
    let labelSize = pixels(label), panelSize = pixels(panel)
    let width: CGFloat = 820, bar: CGFloat = 48, margin: CGFloat = 40
    let height = bar + 12 + panelSize.height + margin
    let clock = text("Sun 25 Oct  05:30", size: 26, color: .white)
    let clockWidth = ("Sun 25 Oct  05:30" as NSString).size(withAttributes: clock).width
    let labelX = width - 32 - clockWidth - 44 - labelSize.width
    canvas(width: Int(width), height: Int(height), to: name) { height in
        NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.25, blue: 0.38, alpha: 1),
                   ending: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.16, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -60)
        menuBarColor.setFill()
        NSRect(x: 0, y: height - bar, width: width, height: bar).fill()
        label.draw(in: NSRect(x: labelX, y: height - bar + (bar - labelSize.height) / 2,
                              width: labelSize.width, height: labelSize.height))
        "Sun 25 Oct  05:30".draw(at: NSPoint(x: width - 32 - clockWidth, y: height - bar + 9), withAttributes: clock)

        let frame = NSRect(x: min(labelX - 12, width - panelSize.width - 24), y: height - bar - 12 - panelSize.height,
                           width: panelSize.width, height: panelSize.height)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 24, yRadius: 24)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor(srgbRed: 0.17, green: 0.17, blue: 0.19, alpha: 1).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 1, alpha: 0.12).setStroke()
        shape.lineWidth = 2
        shape.stroke()
        panel.draw(in: frame)
    }
}

/// One row per menu bar style: its name, then the item on a menu bar.
func menuBarStyles(_ items: [(file: String, caption: String)], to name: String) {
    let row: CGFloat = 48, gap: CGFloat = 16, pad: CGFloat = 24, captionWidth: CGFloat = 300, strip: CGFloat = 320
    let width = pad + captionWidth + strip + pad
    let height = pad * 2 + CGFloat(items.count) * row + CGFloat(items.count - 1) * gap
    let caption = text("", size: 26, weight: .semibold, color: NSColor(white: 0.85, alpha: 1))
    canvas(width: Int(width), height: Int(height), to: name) { height in
        background.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (n, item) in items.enumerated() {
            let y = height - pad - CGFloat(n + 1) * row - CGFloat(n) * gap
            item.caption.draw(at: NSPoint(x: pad, y: y + 8), withAttributes: caption)
            menuBarColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: pad + captionWidth, y: y, width: strip, height: row),
                         xRadius: 10, yRadius: 10).fill()
            let label = image(item.file), size = pixels(label)
            label.draw(in: NSRect(x: pad + captionWidth + 24, y: y + (row - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }
}

/// Plays several activity GIFs one after another in a single looping GIF.
func reel(_ files: [String], loops: Int, to name: String) {
    let data = NSMutableData()
    var frames: [(CGImage, Any)] = []
    for file in files {
        let source = CGImageSourceCreateWithURL(previews.appendingPathComponent(file) as CFURL, nil)!
        let count = CGImageSourceGetCount(source)
        for _ in 0..<loops {
            for i in 0..<count {
                let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] ?? [:]
                frames.append((CGImageSourceCreateImageAtIndex(source, i, nil)!,
                               properties[kCGImagePropertyGIFDictionary] ?? [:]))
            }
        }
    }
    let gif = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (frame, gifProperties) in frames {
        CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: gifProperties] as CFDictionary)
    }
    CGImageDestinationFinalize(gif)
    try! (data as Data).write(to: out.appendingPathComponent(name))
    print("wrote docs/images/\(name) (\(frames.count) frames)")
}

grid([("rings-fresh.png", "Rings"), ("bigNumber-fresh.png", "Big number"), ("bars-fresh.png", "Bars"),
      ("minimal-fresh.png", "Minimal"), ("time-fresh.png", "Time first"), ("gauge-busy.png", "Gauge"),
      ("columns-busy.png", "Columns"), ("tiles-fresh.png", "Tiles"), ("mood-fresh.png", "Mood monster")],
     columns: 3, to: "clock-faces.png")
grid([("bigNumber-fresh.png", "Fresh"), ("bigNumber-busy.png", "Busy (≥ 50% / ≥ 80%)"),
      ("bigNumber-stale.png", "Stale: last update time"), ("bigNumber-signed-out.png", "Signed out")],
     columns: 4, to: "clock-states.png")
reel(["mood-fresh-wave.gif", "mood-fresh-watchTV.gif", "mood-fresh-fishing.gif", "mood-fresh-coding.gif",
      "mood-fresh-dance.gif", "mood-fresh-thinking.gif", "mood-fresh-coffee.gif", "mood-busy-panic.gif"],
     loops: 2, to: "mood-monster.gif")
tray(label: "menubar-barsAndNumbers.png", panel: "panel-fresh.png", to: "menu-bar.png")
menuBarStyles([("menubar-numbers.png", "Two numbers"), ("menubar-bars.png", "Mini bars (default)"),
               ("menubar-countdown.png", "Number + countdown"), ("menubar-barsAndNumbers.png", "Bars + numbers")],
              to: "menu-bar-styles.png")
