// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Sparkle übernimmt Download, Signaturprüfung, den Austausch des Bundles
        // und den Neustart. Selbst gebaut wäre jeder dieser Schritte eine
        // Sicherheitslücke in Wartung.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // libwebp aus Homebrew. Apples ImageIO dekodiert animierte WebP nur wahlfrei
        // und damit quadratisch langsam (gemessen 280 ms je Frame gegenüber 1.5 ms hier).
        .systemLibrary(
            name: "CWebPDemux",
            path: "Sources/CWebPDemux",
            pkgConfig: "libwebpdemux",
            providers: [.brew(["webp"])]
        ),
        .target(
            name: "LuminaCore",
            dependencies: ["CWebPDemux"],
            path: "Sources/LuminaCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Lumina",
            dependencies: [
                "LuminaCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Lumina",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LuminaCoreTests",
            dependencies: ["LuminaCore"],
            path: "Tests/LuminaCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
