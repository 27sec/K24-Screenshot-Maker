// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FramePlayer",
    platforms: [.macOS("15.0")],
    targets: [
        // libmpv headers (ISC licensed, from mpv 0.42) plus a dlopen shim; libmpv itself is loaded at runtime.
        .target(name: "CMpv", path: "Sources/CMpv"),
        .executableTarget(
            name: "FramePlayer",
            dependencies: ["CMpv"],
            path: "Sources/FramePlayer",
            swiftSettings: [.unsafeFlags(["-Xcc", "-DGL_SILENCE_DEPRECATION"])],
            linkerSettings: [.linkedFramework("OpenGL")]
        )
    ]
)
