// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Floe",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "Vendor/ThawUI"),
    ],
    targets: [
        .executableTarget(name: "Floe", dependencies: ["ThawUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FloeTests", dependencies: ["Floe"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
