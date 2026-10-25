import SwiftUI

/// The scenes are drawn on a 40×16 pixel stage (240×96 points at scale 6).
public let sceneSize = (columns: 40, rows: 16)

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255)
}

private enum Ink {
    static let light = rgb(225, 225, 232)
    static let grey = rgb(150, 150, 160)
    static let darkGrey = rgb(85, 85, 95)
    static let ink = rgb(20, 20, 26)
    static let blue = rgb(40, 110, 200)
    static let lightBlue = rgb(130, 195, 255)
    static let red = rgb(240, 70, 80)
    static let yellow = rgb(255, 210, 40)
    static let wood = rgb(130, 85, 50)
    static let coffee = rgb(110, 70, 40)
    static let purple = rgb(190, 120, 255)
    static let green = rgb(120, 220, 120)
    static let orange = rgb(255, 165, 70)
    static let screens = [rgb(60, 120, 255), rgb(80, 200, 255), rgb(150, 90, 255), rgb(60, 210, 140)]
}

/// Collects pixel layers in drawing order.
private struct Stage {
    var layers: [PixelLayer] = []

    mutating func add(_ color: Color, _ points: [(Int, Int)]) {
        layers.append(PixelLayer(color: color, points: points.map { PixelPoint(x: $0.0, y: $0.1) }))
    }

    mutating func rect(_ color: Color, x: ClosedRange<Int>, y: ClosedRange<Int>) {
        add(color, y.flatMap { row in x.map { ($0, row) } })
    }

    mutating func monster(_ pose: MonsterPose, x: Int, y: Int) {
        let cells = monsterCells(pose)
        add(Palette.monster, cells.body.map { ($0.x + x, $0.y + y) })
        add(Palette.monsterEyes, cells.eyes.map { ($0.x + x, $0.y + y) })
        if pose.sunglasses {
            let eyeRow = 3 + pose.eyesDY
            add(Ink.ink, (3...11).map { ($0 + x, eyeRow + y) } + [3, 4, 5, 9, 10, 11].map { ($0 + x, eyeRow + 1 + y) })
        }
    }
}

/// The pixels of one frame of a calm scene, monster included.
public func sceneLayers(_ activity: MonsterActivity, frame: Int) -> [PixelLayer] {
    let i = frame % activity.frameCount
    var stage = Stage()
    var pose = MonsterPose()

    switch activity {
    case .watchTV:
        pose.eyesDX = 1
        if i == 5 { pose.eyes = .blink }
        stage.monster(pose, x: 3, y: 6)
        stage.add(Ink.grey, [(27, 3), (28, 4), (29, 5), (30, 5), (31, 4), (32, 3)])
        stage.rect(Ink.darkGrey, x: 24...35, y: 6...14)
        stage.rect(Ink.screens[(i / 2) % Ink.screens.count], x: 25...32, y: 7...13)
        stage.rect(Ink.light.opacity(0.5), x: 25...32, y: (7 + i % 7)...(7 + i % 7))
        stage.add(Ink.ink, [(34, 8), (34, 10)])
        stage.add(Ink.darkGrey, [(25, 15), (34, 15)])

    case .fishing:
        let bobberY = i % 4 < 2 ? 12 : 13
        pose.eyesDX = 1
        stage.rect(Ink.wood, x: 0...17, y: 15...15)
        stage.monster(pose, x: 1, y: 5)
        stage.rect(Ink.blue, x: 18...39, y: 13...15)
        stage.add(Ink.lightBlue, stride(from: 18 + i % 4, through: 39, by: 4).map { ($0, 13) })
        stage.add(Ink.wood, (0..<12).map { (16 + $0, 8 - $0 / 2) })
        stage.add(Ink.light, (3..<bobberY).map { (28, $0) })
        stage.add(Ink.red, [(28, bobberY)])
        if bobberY == 13 { stage.add(Ink.lightBlue, [(26, 13), (30, 13)]) }
        if i == 5 { stage.add(Ink.orange, [(34, 11), (35, 10)]) }
        if i == 6 { stage.add(Ink.orange, [(36, 11), (37, 12)]) }

    case .relaxing:
        pose.sunglasses = true
        pose.leftArmUp = true
        pose.rightArmUp = true
        stage.monster(pose, x: 4, y: 6)
        stage.rect(Ink.yellow, x: 32...36, y: 2...4)
        stage.rect(Ink.yellow, x: 33...35, y: 1...5)
        stage.add(Ink.yellow, i % 2 == 0
                  ? [(34, 0), (30, 3), (38, 3), (34, 7)]
                  : [(31, 0), (37, 0), (31, 6), (37, 6)])
        stage.rect(Ink.lightBlue, x: 23...25, y: 10...10)
        stage.rect(Ink.orange, x: 23...25, y: 11...14)
        stage.add(Ink.red, [(26, 8), (25, 9)])
        if i % 4 == 1 { stage.add(Ink.grey, [(21, 3), (21, 4), (22, 2)]) }  // ♪
        if i % 4 == 3 { stage.add(Ink.grey, [(23, 2), (23, 3), (24, 1)]) }

    case .thinking:
        pose.eyesDX = 1
        pose.eyesDY = -1
        pose.rightArmUp = true
        stage.monster(pose, x: 3, y: 6)
        stage.add(Ink.light, [(19, 6), (21, 3), (22, 3), (21, 4), (22, 4)])
        stage.rect(Ink.light, x: 25...37, y: 0...6)
        stage.rect(Ink.light, x: 24...38, y: 1...5)
        switch i / 3 {
        case 0: stage.add(Ink.ink, [(28, 3)])
        case 1: stage.add(Ink.ink, [(28, 3), (31, 3)])
        case 2: stage.add(Ink.ink, [(28, 3), (31, 3), (34, 3)])
        default:
            stage.rect(Ink.yellow, x: 30...32, y: 1...3)
            stage.add(Ink.yellow, [(31, 4)])
            stage.rect(Ink.grey, x: 30...32, y: 5...5)
        }

    case .coding:
        pose.eyesDX = 1
        if i == 6 { pose.eyes = .blink }
        stage.monster(pose, x: 2, y: 6)
        stage.rect(Ink.grey, x: 20...33, y: 6...13)
        stage.rect(Ink.ink, x: 21...32, y: 7...12)
        stage.rect(Ink.purple, x: 22...27, y: 8...8)
        stage.rect(Ink.green, x: 24...30, y: 9...9)
        let typed = min(i + 1, 7)
        stage.rect(Ink.orange, x: 24...(23 + typed), y: 10...10)
        if i % 2 == 0 { stage.add(Ink.light, [(24 + typed, 10)]) }
        stage.rect(Ink.light, x: 18...35, y: 14...14)
        stage.rect(Ink.grey, x: 19...34, y: 15...15)

    case .coffee:
        if i == 3 || i == 4 { pose.eyes = .closed }
        stage.monster(pose, x: 6, y: 6)
        stage.rect(Ink.light, x: 21...24, y: 9...13)
        stage.rect(Ink.coffee, x: 22...23, y: 9...9)
        stage.add(Ink.light, [(25, 10), (26, 11), (25, 12)])
        stage.add(Ink.grey, (0..<3).flatMap { k -> [(Int, Int)] in
            let y = 7 - k * 2 - i % 2
            return [(22 + (k + i) % 2, y), (24 - (k + i) % 2, y - 1)]
        })

    case .reading:
        pose.eyesDX = [-1, 0, 1, -1, 0, 1, -1, 0][i]
        stage.monster(pose, x: 12, y: 1)
        stage.rect(Ink.blue, x: 9...29, y: 15...15)
        stage.rect(Ink.light, x: 10...18, y: 10...14)
        stage.rect(Ink.light, x: 20...28, y: 10...14)
        stage.rect(Ink.blue, x: 19...19, y: 10...14)
        stage.add(Ink.grey, [11, 13].flatMap { y in (11...17).map { ($0, y) } + (21...27).map { ($0, y) } })
        if i == 4 { stage.rect(Ink.light, x: 20...24, y: 8...9) }
        if i == 5 { stage.rect(Ink.light, x: 14...18, y: 8...9) }

    default:
        stage.monster(pose, x: 12, y: 3)
    }
    return stage.layers
}
