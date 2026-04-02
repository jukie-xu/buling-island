// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BulingIsland",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "BulingIsland",
            targets: ["BulingIsland"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "BulingIsland",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
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
        .testTarget(
            name: "BulingIslandTests",
            dependencies: ["BulingIsland"],
            path: "Tests/BulingIslandTests"
        ),
    ]
)
