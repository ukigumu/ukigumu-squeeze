// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrumpySqueeze",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrumpySqueezeCore", targets: ["GrumpySqueezeCore"]),
        .executable(name: "GrumpySqueeze", targets: ["GrumpySqueezeApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.5.0")
    ],
    targets: [
        .target(
            name: "GrumpySqueezeCore",
            dependencies: [
                .product(name: "libwebp", package: "libwebp-Xcode")
            ]
        ),
        .executableTarget(
            name: "GrumpySqueezeApp",
            dependencies: ["GrumpySqueezeCore"],
            exclude: ["GrumpySqueeze.entitlements"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GrumpySqueezeCoreTests",
            dependencies: ["GrumpySqueezeCore"],
            path: "Tests/UnitTests"
        ),
        .testTarget(
            name: "GrumpySqueezeIntegrationTests",
            dependencies: ["GrumpySqueezeCore"],
            path: "Tests/IntegrationTests"
        ),
        .testTarget(
            name: "GrumpySqueezeFixtureTests",
            dependencies: ["GrumpySqueezeCore"],
            path: "Tests/FixtureTests"
        ),
        .testTarget(
            name: "GrumpySqueezePerformanceTests",
            dependencies: ["GrumpySqueezeCore"],
            path: "Tests/PerformanceTests"
        )
    ]
)
