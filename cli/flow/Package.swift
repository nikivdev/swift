// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "flow",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "flow", targets: ["flow"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "flow",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
