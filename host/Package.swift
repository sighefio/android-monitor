// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AndroidMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AndroidMonitorDaemon", targets: ["AndroidMonitorDaemon"]),
        .library(name: "AndroidMonitorCore", targets: ["Core", "Capture", "Encode", "Audio", "Networking", "Input", "USB"])
    ],
    targets: [
        .target(name: "Core", path: "Sources/Core"),
        .target(name: "Capture", dependencies: ["Core"], path: "Sources/Capture", exclude: ["LinuxCapture"]),
        .target(name: "Encode", dependencies: ["Core"], path: "Sources/Encode"),
        .target(name: "Audio", dependencies: ["Core"], path: "Sources/Audio"),
        .target(name: "Networking", dependencies: ["Core", "Encode", "Audio"], path: "Sources/Network"),

        .target(name: "Input", dependencies: ["Core"], path: "Sources/Input"),
        .target(name: "USB", dependencies: ["Core"], path: "Sources/USB"),
        .executableTarget(
            name: "AndroidMonitorDaemon",
            dependencies: ["Core", "Capture", "Encode", "Audio", "Networking", "Input", "USB"],
            path: "Sources/AndroidMonitorDaemon"
        ),
        .testTarget(name: "ProtocolTests", dependencies: ["Core"], path: "Tests/ProtocolTests"),
        .testTarget(name: "EncoderTests", dependencies: ["Encode"], path: "Tests/EncoderTests"),
        .testTarget(name: "InputTests", dependencies: ["Input"], path: "Tests/InputTests")
    ]
)
