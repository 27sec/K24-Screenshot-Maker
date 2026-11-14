// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FramePlayer",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "FramePlayer",
            path: "Sources/FramePlayer"
        )
    ]
)
