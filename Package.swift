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
    // Engraving engine — RulesKit remote package for geometry heuristics and API.
    dependencies: [
        .package(url: "https://github.com/Fountain-Coach/RulesKit-SPM.git", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0")
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
                .product(name: "RulesKit", package: "RulesKit-SPM"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
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
            path: "Sources/ScoreKitSnap",
            swiftSettings: [
                .define("ENABLE_LILYPOND")
            ]
        ),
    ]
)
