// swift-tools-version: 6.4
// Vendored from thaw-app/Thaw (ThawConcurrency/); the commit is recorded in UPSTREAM. Tests are not carried over,
// and the platform is macOS 26 to match Floe (upstream declares macOS 27).

import PackageDescription

/// Shared concurrency primitives for the app and its packages.
///
/// The one-shot continuation and abandoning timeout are written once here;
/// per-call-site copies lost cancellations to registration-order differences.
let package = Package(
    name: "ThawConcurrency",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ThawConcurrency", targets: ["ThawConcurrency"]),
    ],
    targets: [
        .target(
            name: "ThawConcurrency",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
