// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TESS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TESS",
            path: "Sources/TESS"
        ),
        // Run with `swift test` (needs Xcode; GitHub Actions runs them on every pull request).
        .testTarget(
            name: "TESSTests",
            dependencies: ["TESS"],
            path: "Tests/TESSTests"
        ),
    ]
)
