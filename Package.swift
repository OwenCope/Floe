// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Floe",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "Vendor/ThawUI"),
        .package(path: "Vendor/ThawConcurrency"),
        // Keep in step with project.yml.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    ],
    targets: [
        .executableTarget(
            name: "Floe",
            dependencies: [
                "ThawUI",
                "ThawConcurrency",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The test bundle links the app's code, so it loads Sparkle.framework too. SwiftPM puts the
        // framework beside the bundle, three levels above the bundle's binary, and adds no rpath for it.
        .testTarget(
            name: "FloeTests",
            dependencies: ["Floe"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])]
        ),
    ]
)
