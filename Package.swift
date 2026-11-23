// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cellar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CellarCore"),
        .executableTarget(name: "Cellar", dependencies: ["CellarCore"]),
        .testTarget(name: "CellarCoreTests", dependencies: ["CellarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
