// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Bkdict",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Bkdict",
            path: "Sources/Bkdict"
        )
    ]
)
