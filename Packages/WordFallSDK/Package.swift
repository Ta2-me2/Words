// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WortfallKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WortfallKit", targets: ["WortfallKit"]),
        .library(name: "WortfallCore", targets: ["WortfallCore"]),
        .executable(name: "WortfallDemo", targets: ["WortfallDemo"])
    ],
    targets: [
        .target(name: "WortfallCore"),
        .target(name: "WortfallKit", dependencies: ["WortfallCore"], resources: [.process("Resources")]),
        .executableTarget(name: "WortfallDemo", dependencies: ["WortfallKit"]),
        .testTarget(name: "WortfallCoreTests", dependencies: ["WortfallCore"]),
        .testTarget(name: "WortfallKitTests", dependencies: ["WortfallKit"])
    ]
)
