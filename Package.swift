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
        .target(
            name: "WhisperBridge",
            path: "Sources/WhisperNode/Bridge",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ]
        ),
        .executableTarget(
            name: "WhisperNode",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "WhisperBridge"
            ],
            path: "Sources/WhisperNode",
            exclude: [
                "Resources/Info.plist",
                "Bridge"
            ],
            linkerSettings: [
                .linkedLibrary("whisper_rust", .when(platforms: [.macOS])),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .unsafeFlags(["-L./whisper-rust/target/aarch64-apple-darwin/release"])
            ]
        ),
        .testTarget(
            name: "WhisperNodeTests",
            dependencies: ["WhisperNode"],
            path: "Tests/WhisperNodeTests"
        )
    ]
)