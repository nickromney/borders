// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "borders",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "borders", targets: ["Borders"])],
    targets: [
        .executableTarget(
            name: "Borders",
            path: "Sources/NBorders",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
