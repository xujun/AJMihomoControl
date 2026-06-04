// swift-tools-version: 5.9
import PackageDescription

/// AJMihomoControl - macOS menu bar app for mihomo proxy control
/// Author: xujun (https://github.com/xujun)
let package = Package(
    name: "MihomoControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MihomoControl", targets: ["MihomoControl"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MihomoControl",
            path: "Sources",
            exclude: ["Info.plist"],
            linkerSettings: []
        )
    ]
)
