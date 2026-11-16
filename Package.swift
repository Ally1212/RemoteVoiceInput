// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemoteVoiceInput",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "RemoteVoiceInput", targets: ["RemoteVoiceInput"])],
    targets: [
        .target(name: "TransferPolicy"),
        .executableTarget(name: "RemoteVoiceInput", dependencies: ["TransferPolicy"]),
        .testTarget(name: "TransferPolicyTests", dependencies: ["TransferPolicy"]),
        .testTarget(name: "RemoteVoiceInputTests", dependencies: ["RemoteVoiceInput"])
    ]
)
