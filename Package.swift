// swift-tools-version: 5.9
import PackageDescription

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
