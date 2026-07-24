// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiquidGlassMacOSTerminal",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "LiquidGlassCore", targets: ["LiquidGlassCore"]),
        .executable(name: "liquidglass", targets: ["LiquidGlassCLI"]),
        .executable(name: "LiquidGlassAgent", targets: ["LiquidGlassAgent"])
    ],
    targets: [
        .target(
            name: "LiquidGlassCore",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "LiquidGlassCLI",
            dependencies: ["LiquidGlassCore"],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "LiquidGlassAgent",
            dependencies: ["LiquidGlassCore"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
                .linkedFramework("CoreMedia", .when(platforms: [.macOS])),
                .linkedFramework("CoreVideo", .when(platforms: [.macOS])),
                .linkedFramework("Metal", .when(platforms: [.macOS])),
                .linkedFramework("MetalKit", .when(platforms: [.macOS])),
                .linkedFramework("MetalPerformanceShaders", .when(platforms: [.macOS])),
                .linkedFramework("ScreenCaptureKit", .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "LiquidGlassCoreTests",
            dependencies: ["LiquidGlassCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
