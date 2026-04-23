// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VibeUsage",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "VibeUsage",
            path: "Sources/Usage"
        )
    ]
)
