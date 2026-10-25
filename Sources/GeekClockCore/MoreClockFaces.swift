import SwiftUI

/// The pixel monster on the left, the time (or "⚠ 05:12" when stale) on the right.
struct FaceHeader: View {
    var text: String
    var warn: Bool
    var title = false
    var monster = true

    var body: some View {
        HStack {
            if monster { PixelMonster(scale: 1) }
            if title {
                Text("Claude").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            }
            Spacer()
            Text(text).font(.system(size: 11, weight: warn ? .semibold : .regular))
                .foregroundStyle(warn ? Palette.yellow : Palette.dim)
        }
        .padding(.horizontal, 10).padding(.top, 8)
    }
}

/// "Week 13% · Fable 0%" with the numbers in bold.
func weeklyLine(_ f: UsageFace, size: CGFloat = 12) -> AttributedString {
    func bold(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        value.font = .system(size: size, weight: .bold)
        return value
    }
    var line = AttributedString("Week ") + bold(f.weekly.percentText)
    if let model = f.model {
        line += AttributedString(" · \(model.title) ") + bold(model.percentText)
    }
    return line
}

private func resetsLine(_ f: UsageFace) -> String {
    f.fiveHourCountdown.isEmpty ? "5-hour" : "5-hour · resets in \(f.fiveHourCountdown)"
}

// MARK: - Minimal

/// Only the 5-hour number, as large as the screen allows.
struct MinimalFace: View {
    let f: UsageFace

    var body: some View {
        VStack(spacing: 0) {
            FaceHeader(text: f.headerText, warn: f.isStale)
            Spacer()
            Text(f.fiveHour.percentText).font(.system(size: 104, weight: .heavy))
                .foregroundStyle(Palette.color(f.fiveHour.level))
                .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 8)
            Text(resetsLine(f)).font(.system(size: 13)).foregroundStyle(Palette.dim)
            Spacer()
            Text(weeklyLine(f)).font(.system(size: 12)).foregroundStyle(Palette.dim)
                .padding(.bottom, 12)
        }
        .frame(width: 240, height: 240)
    }
}

// MARK: - Time first

/// A clock first: the time large, usage as slim bars underneath.
struct TimeFace: View {
    let f: UsageFace

    var body: some View {
        VStack(spacing: 0) {
            FaceHeader(text: "", warn: false)
            Text(f.currentTime).font(.system(size: 72, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white).padding(.top, 8)
            Text(f.isStale ? "\(f.headerText) last update" : " ")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.yellow)
            VStack(spacing: 9) {
                row(f.fiveHour.with(title: "5h"), detail: f.fiveHourCountdown)
                row(f.weekly.with(title: "Week"), detail: f.weeklyCountdown)
                if let model = f.model { row(model, detail: "") }
            }
            .padding(.horizontal, 14).padding(.top, 10)
            Spacer()
        }
        .frame(width: 240, height: 240)
    }

    private func row(_ row: FaceRow, detail: String) -> some View {
        HStack(spacing: 8) {
            Text(row.title).font(.system(size: 11)).foregroundStyle(Palette.dim)
                .frame(width: 40, alignment: .leading)
            UsageBar(fraction: row.fraction, level: row.level, height: 8)
            Text(row.percentText).font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.color(row.level)).frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - Gauge

/// A speedometer: the 5-hour limit as a half-circle dial.
struct GaugeFace: View {
    let f: UsageFace
    private let diameter: CGFloat = 184
    private let width: CGFloat = 18

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                halfCircle(1).stroke(Palette.track, style: StrokeStyle(lineWidth: width, lineCap: .round))
                if f.fiveHour.fraction > 0 {
                    halfCircle(f.fiveHour.fraction)
                        .stroke(Palette.color(f.fiveHour.level), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            .frame(width: diameter, height: diameter)
            .padding(.top, 44)
            VStack(spacing: 2) {
                Text(f.fiveHour.percentText).font(.system(size: 50, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(f.fiveHourCountdown.isEmpty ? "5-hour" : "resets in \(f.fiveHourCountdown)")
                    .font(.system(size: 12)).foregroundStyle(Palette.dim)
            }
            .padding(.top, 92)
            Text(weeklyLine(f)).font(.system(size: 12)).foregroundStyle(.white).padding(.top, 196)
            FaceHeader(text: f.headerText, warn: f.isStale)
        }
        .frame(width: 240, height: 240, alignment: .top)
    }

    /// The top half of a circle, drawn left to right and filled to `fraction`.
    private func halfCircle(_ fraction: Double) -> some Shape {
        Circle().trim(from: 0.5, to: 0.5 + 0.5 * fraction)
    }
}

// MARK: - Columns

/// Each limit as a vertical bar that fills from the bottom.
struct ColumnsFace: View {
    let f: UsageFace

    var body: some View {
        VStack(spacing: 0) {
            FaceHeader(text: f.headerText, warn: f.isStale)
            HStack(alignment: .bottom, spacing: 22) {
                column(f.fiveHour.with(title: "5h"))
                column(f.weekly.with(title: "Week"))
                if let model = f.model { column(model) }
            }
            .padding(.top, 10)
            Text(captions).font(.system(size: 10)).foregroundStyle(Palette.dim).padding(.top, 8)
            Spacer()
        }
        .frame(width: 240, height: 240)
    }

    private var captions: String {
        [f.fiveHourCountdown.isEmpty ? nil : "5h resets \(f.fiveHourCountdown)",
         f.weeklyCountdown.isEmpty ? nil : "week \(f.weeklyCountdown)"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func column(_ row: FaceRow) -> some View {
        VStack(spacing: 5) {
            Text(row.percentText).font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.color(row.level)).lineLimit(1).minimumScaleFactor(0.6)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8).fill(Palette.track)
                if row.fraction > 0 {
                    RoundedRectangle(cornerRadius: 8).fill(Palette.color(row.level))
                        .frame(height: max(12, 124 * row.fraction))
                }
            }
            .frame(width: 44, height: 124)
            Text(row.title).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
        }
        .frame(width: 52)
    }
}

// MARK: - Tiles

/// Four tiles: 5-hour, its countdown, weekly, and the model limit.
struct TilesFace: View {
    let f: UsageFace

    var body: some View {
        VStack(spacing: 8) {
            FaceHeader(text: f.headerText, warn: f.isStale)
            HStack(spacing: 8) {
                tile("5-HOUR", f.fiveHour.percentText, Palette.color(f.fiveHour.level))
                tile("RESETS IN", f.fiveHourCountdown.isEmpty ? "—" : f.fiveHourCountdown, .white)
            }
            HStack(spacing: 8) {
                tile("WEEKLY", f.weekly.percentText, Palette.color(f.weekly.level))
                if let model = f.model {
                    tile(model.title.uppercased(), model.percentText, Palette.color(model.level))
                } else {
                    tile("WEEK RESETS", f.weeklyCountdown.isEmpty ? "—" : f.weeklyCountdown, .white)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 240, height: 240)
    }

    private func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .medium)).kerning(0.5).foregroundStyle(Palette.dim)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 32, weight: .bold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(10)
        .frame(width: 104, height: 92, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
    }
}

// MARK: - Mood monster

/// A big Claude-orange pixel monster doing something different every minute;
/// the 5-hour number below it is coloured by level.
struct MoodFace: View {
    let f: UsageFace
    var activity: MonsterActivity = .wave
    var frame = 0

    var body: some View {
        let (pose, offset, degrees) = activity.frame(frame)
        VStack(spacing: 0) {
            FaceHeader(text: f.headerText, warn: f.isStale, monster: false)
            if activity.isScene {
                PixelCanvas(layers: sceneLayers(activity, frame: frame), scale: 6)
                    .frame(width: 240, height: 96).padding(.vertical, 2)
            } else {
                ZStack {
                    PixelMonster(scale: 8, pose: pose)
                        .rotationEffect(.degrees(degrees))
                        .offset(offset)
                    extras
                }
                .frame(width: 240, height: 100)
            }
            Text(f.fiveHour.percentText).font(.system(size: 40, weight: .bold))
                .foregroundStyle(Palette.color(f.fiveHour.level))
            Text(resetsLine(f)).font(.system(size: 11)).foregroundStyle(Palette.dim)
            Text(weeklyLine(f)).font(.system(size: 12)).foregroundStyle(.white).padding(.top, 8)
            Spacer()
        }
        .frame(width: 240, height: 240)
    }

    /// Floating z's, hearts or sweat around the monster.
    @ViewBuilder
    private var extras: some View {
        let i = frame % activity.frameCount
        switch activity {
        case .sleep:
            ForEach(0..<3, id: \.self) { k in
                let p = (i + k * 3) % 8
                Text("z").font(.system(size: CGFloat(12 + 2 * p), weight: .bold))
                    .foregroundStyle(Palette.dim)
                    .offset(x: CGFloat(62 + 3 * p), y: CGFloat(-22 - 4 * p))
                    .opacity(p < 7 ? 1 : 0)
            }
        case .love:
            ForEach(0..<2, id: \.self) { k in
                let p = (i + k * 4) % 8
                Text("♥").font(.system(size: 18))
                    .foregroundStyle(Color(.sRGB, red: 1, green: 0.42, blue: 0.6))
                    .offset(x: k == 0 ? -64 : 64, y: CGFloat(-6 - 5 * p))
                    .opacity(1 - Double(p) / 8)
            }
        case .panic:
            Text("💦").font(.system(size: 18)).offset(x: 66, y: CGFloat(-30 + 2 * (i % 4)))
        default:
            EmptyView()
        }
    }
}
