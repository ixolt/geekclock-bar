import SwiftUI

public enum Palette {
    public static let green = rgb(0, 240, 60)
    public static let yellow = rgb(255, 210, 40)
    public static let red = rgb(240, 70, 80)
    public static let dim = rgb(150, 150, 160)
    public static let track = rgb(45, 45, 55)
    /// Claude's terracotta orange.
    public static let monster = rgb(217, 119, 87)
    public static let monsterEyes = rgb(20, 15, 18)

    public static func color(_ level: UsageLevel) -> Color {
        switch level {
        case .green: green
        case .yellow: yellow
        case .red: red
        case .unknown: dim
        }
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255)
    }
}

/// The pixel-art mascot from the original script: a 15×10 sprite with a
/// body, two arms, two eyes and four legs, drawn in the given pose.
public struct PixelMonster: View {
    private let scale: CGFloat
    private let color: Color
    private let pose: MonsterPose

    public init(scale: CGFloat, color: Color = Palette.monster, pose: MonsterPose = MonsterPose()) {
        self.scale = scale
        self.color = color
        self.pose = pose
    }

    public var body: some View {
        let cells = monsterCells(pose)
        return PixelCanvas(layers: [PixelLayer(color: color, points: cells.body),
                                    PixelLayer(color: Palette.monsterEyes, points: cells.eyes)],
                           scale: scale)
            .frame(width: 15 * scale, height: 10 * scale)
    }
}

/// Draws pixel layers in order, each colour as one shape so nothing shows
/// seams between pixels when tilted or scaled.
struct PixelCanvas: View {
    let layers: [PixelLayer]
    let scale: CGFloat

    var body: some View {
        Canvas { context, _ in
            for layer in layers {
                let path = Path { path in
                    for p in layer.points {
                        path.addRect(CGRect(x: CGFloat(p.x) * scale, y: CGFloat(p.y) * scale, width: scale, height: scale))
                    }
                }
                context.fill(path, with: .color(layer.color))
            }
        }
    }
}

/// A rounded progress bar.
public struct UsageBar: View {
    let fraction: Double
    let level: UsageLevel
    let height: CGFloat

    public init(fraction: Double, level: UsageLevel, height: CGFloat) {
        self.fraction = fraction
        self.level = level
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                if fraction > 0 {
                    Capsule().fill(Palette.color(level))
                        .frame(width: max(height, geo.size.width * fraction))
                }
            }
        }
        .frame(height: height)
    }
}

/// The 240×240 image sent to the clock, in the chosen layout.
struct ClockFaceView: View {
    let face: ClockFace
    var style: ClockFaceStyle = .bigNumber
    /// The animation frame and what the monster is doing, for animated styles.
    var frame = 0
    var activity: MonsterActivity = .wave

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            switch face {
            case .usage(let f):
                switch style {
                case .rings: rings(f)
                case .bigNumber: bigNumber(f)
                case .bars: bars(f)
                case .minimal: MinimalFace(f: f)
                case .time: TimeFace(f: f)
                case .gauge: GaugeFace(f: f)
                case .columns: ColumnsFace(f: f)
                case .tiles: TilesFace(f: f)
                case .mood: MoodFace(f: f, activity: activity, frame: frame)
                }
            case .signedOut(let time): signedOut(time)
            }
        }
        .frame(width: 240, height: 240)
        .environment(\.colorScheme, .dark)
    }

    private func header(_ text: String, warn: Bool, title: Bool = false) -> some View {
        FaceHeader(text: text, warn: warn, title: title)
    }

    // MARK: - A · Rings

    private func rings(_ f: UsageFace) -> some View {
        ZStack(alignment: .top) {
            ring(f.fiveHour, diameter: 176, width: 12)
            ring(f.weekly, diameter: 140, width: 8, opacity: 0.75)
            VStack(spacing: 0) {
                Text(f.fiveHour.percentText).font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text(f.fiveHourCountdown.isEmpty ? "5h" : "5h · resets \(f.fiveHourCountdown)")
                    .font(.system(size: 11)).foregroundStyle(Palette.dim).padding(.top, 2)
                Text(weeklyLine(f)).font(.system(size: 12)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7).frame(width: 120).padding(.top, 6)
            }
            .padding(.top, 78)
            header(f.headerText, warn: f.isStale)
        }
        .frame(width: 240, height: 240, alignment: .top)
    }

    /// One activity ring centred at (120, 124), filled clockwise from 12 o'clock.
    private func ring(_ row: FaceRow, diameter: CGFloat, width: CGFloat, opacity: Double = 1) -> some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: width)
            if row.fraction > 0 {
                Circle().trim(from: 0, to: row.fraction)
                    .stroke(Palette.color(row.level).opacity(opacity),
                            style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
        .padding(.top, 124 - diameter / 2)
    }

    // MARK: - B · Big number

    private func bigNumber(_ f: UsageFace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(f.headerText, warn: f.isStale)
            VStack(alignment: .leading, spacing: 0) {
                Text("5-HOUR").font(.system(size: 11, weight: .medium)).kerning(1)
                    .foregroundStyle(Palette.dim).padding(.top, 8)
                HStack(alignment: .lastTextBaseline) {
                    bigPercent(f.fiveHour)
                    Spacer(minLength: 4)
                    if !f.fiveHourCountdown.isEmpty {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("resets in").font(.system(size: 11)).foregroundStyle(Palette.dim)
                            Text(f.fiveHourCountdown).font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                UsageBar(fraction: f.fiveHour.fraction, level: f.fiveHour.level, height: 8).padding(.top, 6)

                VStack(alignment: .leading, spacing: 0) {
                    smallRow(f.weekly)
                    if let model = f.model { smallRow(model).padding(.top, 10) }
                    if !f.weeklyResetText.isEmpty {
                        Text(f.weeklyResetText).font(.system(size: 10)).foregroundStyle(Palette.dim)
                            .padding(.top, 6)
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 14)
        }
    }

    private func bigPercent(_ row: FaceRow) -> some View {
        let color = Palette.color(row.level)
        let number = row.percentText.hasSuffix("%") ? String(row.percentText.dropLast()) : row.percentText
        return HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(number).font(.system(size: 64, weight: .heavy))
            if row.percentText.hasSuffix("%") {
                Text("%").font(.system(size: 28, weight: .heavy))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func smallRow(_ row: FaceRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.title)
                Spacer()
                Text(row.percentText).fontWeight(.bold)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white)
            UsageBar(fraction: row.fraction, level: row.level, height: 5)
        }
    }

    // MARK: - C · Bars

    private func bars(_ f: UsageFace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(f.headerText, warn: f.isStale, title: true)
            VStack(alignment: .leading, spacing: 0) {
                barRow(f.fiveHour.with(title: "Current"),
                       caption: f.fiveHourCountdown.isEmpty ? nil : "resets in \(f.fiveHourCountdown)")
                barRow(f.weekly, caption: f.model == nil ? weeklyCaption(f) : nil).padding(.top, 10)
                if let model = f.model {
                    barRow(model, caption: weeklyCaption(f)).padding(.top, 10)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
        }
    }

    private func weeklyCaption(_ f: UsageFace) -> String? {
        f.weeklyResetText.isEmpty ? nil : f.weeklyResetText
    }

    private func barRow(_ row: FaceRow, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline) {
                Text(row.title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text(row.percentText).font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.color(row.level))
            }
            UsageBar(fraction: row.fraction, level: row.level, height: 14)
            if let caption {
                Text(caption).font(.system(size: 10)).foregroundStyle(Palette.dim)
            }
        }
    }

    // MARK: - Signed out

    private func signedOut(_ time: String) -> some View {
        VStack(spacing: 0) {
            header(time, warn: false)
            Spacer()
            PixelMonster(scale: 4)
            Text("Sign in on your Mac").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white).padding(.top, 18)
            Spacer()
            Spacer()
        }
    }
}
