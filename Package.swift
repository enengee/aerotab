// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AeroTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AeroTabCore"),
        .executableTarget(
            name: "AeroTab",
            dependencies: ["AeroTabCore"],
            linkerSettings: [.unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"])]
        ),
        .testTarget(name: "AeroTabCoreTests", dependencies: ["AeroTabCore"]),
    ],
    swiftLanguageModes: [.v5]
)
