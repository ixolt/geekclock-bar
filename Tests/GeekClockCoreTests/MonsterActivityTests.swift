import Testing
@testable import GeekClockCore

/// A seeded generator so the random picks are repeatable.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func picks(_ level: UsageLevel, count: Int = 500) -> [MonsterActivity] {
    var rng = SplitMix64(state: 42)
    var previous: MonsterActivity?
    return (0..<count).map { _ in
        let next = pickActivity(level: level, previous: previous, using: &rng)
        previous = next
        return next
    }
}

@Test func monsterNeverDoesTheSameThingTwiceInARow() {
    let seq = picks(.green)
    #expect(zip(seq, seq.dropFirst()).allSatisfy { $0 != $1 })
}

@Test func monsterOnlyPanicsNearTheLimit() {
    for level in [UsageLevel.green, .yellow, .unknown] {
        #expect(!picks(level).contains(.panic))
    }
    #expect(picks(.red).contains(.panic))
}

@Test func monsterGetsAroundToEveryCalmActivity() {
    #expect(Set(picks(.green)) == Set(MonsterActivity.allCases.filter { $0 != .panic }))
}

private let scenes: [MonsterActivity] = [.watchTV, .fishing, .relaxing, .thinking, .coding, .coffee, .reading]

@Test func calmScenesAreScenes() {
    #expect(MonsterActivity.allCases.filter(\.isScene) == scenes)
}

/// Each scene moves a little: not every frame is the same picture.
@Test func everySceneAnimates() {
    for scene in scenes {
        let frames = (0..<scene.frameCount).map { sceneLayers(scene, frame: $0) }
        #expect(Set(frames.map { "\($0)" }).count > 1, "\(scene) never changes")
    }
}

/// Every scene fits the 40×16 pixel stage and has the monster in it.
@Test func scenesStayOnStageWithTheMonster() {
    for scene in scenes {
        let layers = sceneLayers(scene, frame: 0)
        let points = layers.flatMap(\.points)
        #expect(points.allSatisfy { (0..<sceneSize.columns).contains($0.x) && (0..<sceneSize.rows).contains($0.y) },
                "\(scene) draws off stage")
        #expect(layers.contains { $0.color == Palette.monster && $0.points.count > 60 }, "\(scene) has no monster")
    }
}
