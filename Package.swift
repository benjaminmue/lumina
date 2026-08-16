// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LuminaCore",
            path: "Sources/LuminaCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Lumina",
            dependencies: ["LuminaCore"],
            path: "Sources/Lumina",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LuminaCoreTests",
            dependencies: ["LuminaCore"],
            path: "Tests/LuminaCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
