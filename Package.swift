// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AeroTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AeroTabCore"),
        .executableTarget(name: "AeroTab", dependencies: ["AeroTabCore"]),
        .testTarget(name: "AeroTabCoreTests", dependencies: ["AeroTabCore"]),
    ],
    swiftLanguageModes: [.v5]
)
