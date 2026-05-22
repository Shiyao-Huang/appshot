// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppShot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AppShotCore", targets: ["AppShotCore"]),
        .executable(name: "AppShotApp", targets: ["AppShotApp"]),
        .executable(name: "appshot", targets: ["appshot"])
    ],
    targets: [
        .target(
            name: "AppShotCore",
            path: "Sources/AppShotCore"
        ),
        .executableTarget(
            name: "AppShotApp",
            dependencies: ["AppShotCore"],
            path: "Sources/AppShotApp"
        ),
        .executableTarget(
            name: "appshot",
            dependencies: ["AppShotCore"],
            path: "Sources/AppShotCLI"
        )
    ]
)
