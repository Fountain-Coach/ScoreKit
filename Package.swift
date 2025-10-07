// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScoreKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13), .iOS(.v16)
    ],
    products: [
        .library(name: "ScoreKit", targets: ["ScoreKit"]),
        .library(name: "ScoreKitUI", targets: ["ScoreKitUI"]),
        .executable(name: "ScoreKitDemo", targets: ["ScoreKitDemo"]),
        .executable(name: "ScoreKitBench", targets: ["ScoreKitBench"]),
        .executable(name: "ScoreKitGif", targets: ["ScoreKitGif"]),
        .executable(name: "ScoreKitVid", targets: ["ScoreKitVid"]),
        .executable(name: "ScoreKitSnap", targets: ["ScoreKitSnap"]),
    ],
    // Engraving engine (local path) — RulesKit manual API for offline builds.
    dependencies: [
        .package(path: "../Engraving/codegen/swift/RulesKit-SPM")
    ],
    targets: [
        .target(
            name: "ScoreKit",
            path: "Sources/ScoreKit",
            swiftSettings: [
                // LilyPond is deprecated and disabled by default. For tests and interop, enable via feature flag.
                .define("ENABLE_LILYPOND")
            ]
        ),
        .target(
            name: "ScoreKitUI",
            dependencies: [
                "ScoreKit",
                .product(name: "RulesKit", package: "RulesKit-SPM")
            ],
            path: "Sources/ScoreKitUI"
        ),
        .testTarget(
            name: "ScoreKitTests",
            dependencies: ["ScoreKit"],
            path: "Tests/ScoreKitTests"
        ),
        .testTarget(
            name: "ScoreKitUITests",
            dependencies: ["ScoreKitUI"],
            path: "Tests/ScoreKitUITests"
        ),
        .executableTarget(
            name: "ScoreKitDemo",
            dependencies: ["ScoreKitUI"],
            path: "Sources/ScoreKitDemo"
        ),
        .executableTarget(
            name: "ScoreKitBench",
            dependencies: ["ScoreKitUI"],
            path: "Sources/ScoreKitBench"
        ),
        .executableTarget(
            name: "ScoreKitGif",
            dependencies: ["ScoreKitUI"],
            path: "Sources/ScoreKitGif"
        ),
        .executableTarget(
            name: "ScoreKitVid",
            dependencies: ["ScoreKitUI"],
            path: "Sources/ScoreKitVid"
        ),
        .executableTarget(
            name: "ScoreKitSnap",
            dependencies: ["ScoreKitUI"],
            path: "Sources/ScoreKitSnap"
        ),
    ]
)
