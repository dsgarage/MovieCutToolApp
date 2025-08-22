// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MovieCutToolApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MovieCutToolApp",
            targets: ["MovieCutToolApp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MovieCutToolApp",
            dependencies: [],
            path: "Sources"
        )
    ]
)