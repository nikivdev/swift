// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-docs",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "swift-docs", targets: ["swift-docs"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "swift-docs",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
