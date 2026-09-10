// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "borders",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "borders", targets: ["Borders"])],
    targets: [
        .target(name: "BordersCore", path: "Sources/BordersCore"),
        .executableTarget(
            name: "Borders",
            dependencies: ["BordersCore"],
            path: "Sources/NBorders",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(name: "BordersCoreTests", dependencies: ["BordersCore"], path: "Tests/BordersCoreTests")
    ]
)
