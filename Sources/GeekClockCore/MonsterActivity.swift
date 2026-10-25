import CoreGraphics
import SwiftUI

/// How the pixel monster holds itself in one frame.
public struct MonsterPose: Equatable, Sendable {
    public enum Eyes: Sendable { case open, blink, closed }

    public var eyes: Eyes = .open
    /// Eyes shifted one pixel left (-1) or right (1), up (-1) or down (1).
    public var eyesDX = 0
    public var eyesDY = 0
    public var sunglasses = false
    public var leftArmUp = false
    public var rightArmUp = false
    /// Lifts every other leg, for walking and dancing.
    public var stepping = false

    public init() {}
}

/// What the mood monster is up to; it picks a new one every minute.
public enum MonsterActivity: String, CaseIterable, Sendable {
    case wave, jump, dance, sleep, lookAround, walk, love, panic
    case watchTV, fishing, relaxing, thinking, coding, coffee, reading

    /// A calm little pixel-art scene with props, drawn by `sceneLayers`.
    public var isScene: Bool {
        switch self {
        case .watchTV, .fishing, .relaxing, .thinking, .coding, .coffee, .reading: true
        default: false
        }
    }

    public var frameCount: Int {
        switch self {
        case .walk: 16
        case .thinking: 12
        default: 8
        }
    }

    /// Seconds per frame.
    public var frameDelay: Double {
        switch self {
        case .wave, .love: 0.15
        case .jump, .walk: 0.1
        case .dance: 0.13
        case .sleep: 0.3
        case .lookAround: 0.2
        case .panic: 0.06
        case .watchTV, .coding: 0.2
        case .fishing, .thinking, .coffee: 0.3
        case .reading: 0.35
        case .relaxing: 0.4
        }
    }

    /// The pose and the shift (in points) for one frame.
    public func frame(_ index: Int) -> (pose: MonsterPose, offset: CGSize, degrees: Double) {
        let i = index % frameCount
        var pose = MonsterPose()
        var offset = CGSize.zero
        var degrees = 0.0
        switch self {
        case .wave:
            pose.rightArmUp = i % 4 < 2
            if i == 6 { pose.eyes = .blink }
        case .jump:
            offset.height = [0, -6, -14, -20, -20, -14, -6, 0][i]
            pose.leftArmUp = offset.height < -10
            pose.rightArmUp = pose.leftArmUp
        case .dance:
            offset.width = [-6, -3, 0, 3, 6, 3, 0, -3][i]
            degrees = [-8, -4, 0, 4, 8, 4, 0, -4][i]
            pose.leftArmUp = i % 4 < 2
            pose.rightArmUp = !pose.leftArmUp
            pose.stepping = i % 2 == 0
        case .sleep:
            pose.eyes = .closed
            offset.height = [0, 0, 1, 2, 2, 2, 1, 0][i]
        case .lookAround:
            pose.eyesDX = [0, -1, -1, -1, 0, 1, 1, 1][i]
            if i == 4 { pose.eyes = .blink }
        case .walk:
            let out = i < 8
            offset.width = out ? CGFloat(-28 + 8 * i) : CGFloat(28 - 8 * (i - 8))
            offset.height = i % 2 == 0 ? 0 : -2
            pose.eyesDX = out ? 1 : -1
            pose.stepping = i % 2 == 0
        case .love:
            offset.height = [0, -1, -2, -2, -1, 0, 0, 0][i]
            if i == 3 { pose.eyes = .blink }
        case .panic:
            offset.width = [-5, 5, -5, 5, -4, 4, -3, 3][i]
            pose.leftArmUp = true
            pose.rightArmUp = true
        case .watchTV, .fishing, .relaxing, .thinking, .coding, .coffee, .reading:
            break  // Posed inside the scene.
        }
        return (pose, offset, degrees)
    }
}

/// A different activity from last time; panicking only when the 5-hour limit is nearly used up.
public func pickActivity(level: UsageLevel, previous: MonsterActivity?,
                         using rng: inout some RandomNumberGenerator) -> MonsterActivity {
    var pool = MonsterActivity.allCases.filter { $0 != .panic || level == .red }
    pool.removeAll { $0 == previous }
    return pool.randomElement(using: &rng) ?? .wave
}

// MARK: - Pixels

public struct PixelPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int
}

/// Pixels of one colour, drawn as a single shape.
public struct PixelLayer: Equatable {
    public var color: Color
    public var points: [PixelPoint]
}

/// The monster's body and eye pixels on its 15×10 grid.
func monsterCells(_ pose: MonsterPose) -> (body: [PixelPoint], eyes: [PixelPoint]) {
    var body: [PixelPoint] = []
    func add(_ x: Int, _ y: Int, to list: inout [PixelPoint]) { list.append(PixelPoint(x: x, y: y)) }
    for y in 0...7 { for x in 2...12 { add(x, y, to: &body) } }
    for (x, up) in [(0, pose.leftArmUp), (13, pose.rightArmUp)] {
        for y in up ? 1...2 : 3...4 { add(x, y, to: &body); add(x + 1, y, to: &body) }
    }
    for (n, x) in [2, 5, 8, 11].enumerated() {
        for y in pose.stepping && n % 2 == 1 ? 8...8 : 8...9 { add(x, y, to: &body); add(x + 1, y, to: &body) }
    }
    var eyes: [PixelPoint] = []
    let top = 3 + pose.eyesDY
    for x in [4 + pose.eyesDX, 10 + pose.eyesDX] {
        switch pose.eyes {
        case .open: add(x, top, to: &eyes); add(x, top + 1, to: &eyes)
        case .blink: add(x, top + 1, to: &eyes)
        case .closed: for dx in -1...1 { add(x + dx, top + 1, to: &eyes) }
        }
    }
    return (body, eyes)
}
