// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BulingIsland",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BulingIsland",
            path: "Sources",
            exclude: [
                "Info.plist",
            ],
            resources: [
                .process("Assets.xcassets"),
            ],
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"]),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
