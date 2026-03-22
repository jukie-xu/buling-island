// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BulingIsland",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BulingIsland",
            path: "BulingIsland",
            exclude: [
                "Info.plist",
            ],
            resources: [
                .process("Assets.xcassets"),
            ],
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"]),
            ]
        ),
    ]
)
