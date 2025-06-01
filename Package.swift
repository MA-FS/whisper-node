// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperNode",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "WhisperNode",
            targets: ["WhisperNode"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", "2.0.0"..<"3.0.0")
    ],
    targets: [
        .executableTarget(
            name: "WhisperNode",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/WhisperNode",
            exclude: [
                "Resources/Info.plist"
            ]
        ),
        .testTarget(
            name: "WhisperNodeTests",
            dependencies: ["WhisperNode"],
            path: "Tests/WhisperNodeTests"
        )
    ]
)