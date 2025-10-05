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
    ],
    targets: [
        .target(
            name: "ScoreKit",
            path: "Sources/ScoreKit"
        ),
        .target(
            name: "ScoreKitUI",
            dependencies: ["ScoreKit"],
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
    ]
)
