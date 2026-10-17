// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "borders",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "borders", targets: ["Borders"]),
        // BordersCore holds the geometry, settings, config parsing and key
        // light protocol — all of it pure and already public. It was a target
        // only, so nothing outside this package could use it without copying
        // the source. Exposing it is what lets it be depended on instead.
        .library(name: "BordersCore", targets: ["BordersCore"])
    ],
    targets: [
        .target(name: "BordersCore", path: "Sources/BordersCore"),
        .executableTarget(
            name: "Borders",
            dependencies: ["BordersCore"],
            path: "Sources/NBorders",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(name: "BordersCoreTests", dependencies: ["BordersCore"], path: "Tests/BordersCoreTests")
    ]
)
