// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GeekClockBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GeekClockCore"),
        .executableTarget(name: "GeekClockBar", dependencies: ["GeekClockCore"]),
        .testTarget(
            name: "GeekClockCoreTests",
            dependencies: ["GeekClockCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
