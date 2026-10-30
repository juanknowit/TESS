// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TESS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TESS",
            path: "Sources/TESS"
        )
    ]
)
