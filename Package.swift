// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Voxtv",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .executableTarget(
            name: "Voxtv",
            dependencies: [
                "CSherpaOnnx",
                "COnnxRuntime",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources"), .process("Assets.xcassets")],
            linkerSettings: [
                .unsafeFlags(["-L", "Libraries/CSherpaOnnx", "-lsherpa-onnx"]),
                .unsafeFlags(["-L", "Libraries/COnnxRuntime", "-lonnxruntime"]),
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "VoxtvTests",
            dependencies: ["Voxtv"]
        ),
        .systemLibrary(
            name: "CSherpaOnnx",
            path: "Libraries/CSherpaOnnx",
            providers: [.brew(["sherpa-onnx"])]
        ),
        .systemLibrary(
            name: "COnnxRuntime",
            path: "Libraries/COnnxRuntime",
            providers: [.brew(["onnxruntime"])]
        ),
    ]
)
