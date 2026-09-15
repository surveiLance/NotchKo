// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Notch",
            path: "Sources/Notch"
        )
    ]
)
