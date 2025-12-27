// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Launcher",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Launcher",
            type: .dynamic,
            targets: ["Launcher"]
        ),
        .executable(
            name: "launcher-cli",
            targets: ["LauncherCLI"]
        ),
        .executable(
            name: "launcher-agent",
            targets: ["LauncherAgent"]
        )
    ],
    targets: [
        .target(
            name: "Launcher",
            path: "Sources/Launcher"
        ),
        .executableTarget(
            name: "LauncherCLI",
            dependencies: ["Launcher"],
            path: "Sources/LauncherCLI"
        ),
        .executableTarget(
            name: "LauncherAgent",
            dependencies: ["Launcher"],
            path: "Sources/LauncherAgent"
        )
    ]
)
