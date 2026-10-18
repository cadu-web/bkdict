// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Bkdict",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates: checks the appcast published with each release (scripts/release.sh).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Bkdict",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Bkdict",
            // Sparkle.framework is copied into Contents/Frameworks by build.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
