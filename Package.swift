// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hush",
    defaultLocalization: "nl",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Hush", targets: ["Hush"]),
    ],
    targets: [
        // Pure logic: models, storage, formatting, notes providers. No UI.
        .target(name: "HushCore"),
        // The menu bar app: UI, audio capture, transcription.
        .executableTarget(
            name: "Hush",
            dependencies: ["HushCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
    ]
)
