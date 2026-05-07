// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Voxtv",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Voxtv",
            dependencies: [
                "CSherpaOnnx",
                "COnnxRuntime",
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
