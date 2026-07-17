// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexSkinManager",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "SkinCore", targets: ["SkinCore"]),
        .executable(name: "CodexSkinManager", targets: ["CodexSkinManager"]),
    ],
    targets: [
        .target(name: "SkinCore"),
        .executableTarget(
            name: "CodexSkinManager",
            dependencies: ["SkinCore"],
            exclude: ["Resources"]
        ),
        .testTarget(name: "SkinCoreTests", dependencies: ["SkinCore"]),
    ]
)
