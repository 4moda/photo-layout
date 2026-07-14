// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "PhotoLayoutCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PhotoLayoutCore", targets: ["PhotoLayoutCore"])
    ],
    targets: [
        .target(name: "PhotoLayoutCore"),
        .testTarget(name: "PhotoLayoutCoreTests", dependencies: ["PhotoLayoutCore"])
    ]
)
