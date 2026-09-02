// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UkigumuSqueeze",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UkigumuSqueezeCore", targets: ["UkigumuSqueezeCore"]),
        .executable(name: "UkigumuSqueeze", targets: ["UkigumuSqueezeApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.5.0")
    ],
    targets: [
        .target(
            name: "UkigumuSqueezeCore",
            dependencies: [
                .product(name: "libwebp", package: "libwebp-Xcode")
            ]
        ),
        .executableTarget(
            name: "UkigumuSqueezeApp",
            dependencies: ["UkigumuSqueezeCore"],
            exclude: ["UkigumuSqueeze.entitlements"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "UkigumuSqueezeCoreTests",
            dependencies: ["UkigumuSqueezeCore"],
            path: "Tests/UnitTests"
        ),
        .testTarget(
            name: "UkigumuSqueezeIntegrationTests",
            dependencies: ["UkigumuSqueezeCore"],
            path: "Tests/IntegrationTests"
        ),
        .testTarget(
            name: "UkigumuSqueezeFixtureTests",
            dependencies: ["UkigumuSqueezeCore"],
            path: "Tests/FixtureTests"
        ),
        .testTarget(
            name: "UkigumuSqueezePerformanceTests",
            dependencies: ["UkigumuSqueezeCore"],
            path: "Tests/PerformanceTests"
        )
    ]
)
