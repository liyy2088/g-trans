// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "GTrans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GTrans", targets: ["GTrans"]),
        .library(name: "GTransCore", targets: ["GTransCore"])
    ],
    targets: [
        .target(
            name: "GTransCore",
            path: "Sources/GTransCore"
        ),
        .executableTarget(
            name: "GTrans",
            dependencies: ["GTransCore"],
            path: "Sources/GTrans"
        ),
        .testTarget(
            name: "GTransCoreTests",
            dependencies: ["GTransCore"],
            path: "Tests/GTransCoreTests"
        )
    ]
)
