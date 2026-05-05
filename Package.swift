// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Voxtv",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Voxtv"),
        .testTarget(
            name: "VoxtvTests",
            dependencies: ["Voxtv"]
        ),
    ]
)
