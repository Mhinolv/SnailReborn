// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SnailReborn",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SnailCore", targets: ["SnailCore"]),
        .executable(name: "snailctl", targets: ["SnailCLI"]),
        .executable(name: "SnailApp", targets: ["SnailApp"])
    ],
    targets: [
        .target(name: "SnailCore", path: "Sources/SnailCore"),
        .executableTarget(name: "SnailCLI", dependencies: ["SnailCore"], path: "Sources/SnailCLI"),
        .executableTarget(name: "SnailApp", dependencies: ["SnailCore"], path: "Sources/SnailApp"),
        .testTarget(name: "SnailAppTests", dependencies: ["SnailApp", "SnailCore"], path: "Tests/SnailAppTests"),
        .testTarget(name: "SnailCLITests", dependencies: ["SnailCLI", "SnailCore"], path: "Tests/SnailCLITests"),
        .testTarget(name: "SnailCoreTests", dependencies: ["SnailCore"], path: "Tests/SnailCoreTests")
    ]
)
