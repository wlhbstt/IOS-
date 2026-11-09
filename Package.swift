// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoCleanerCore",
    platforms: [.iOS(.v18), .macOS(.v13)],
    products: [.library(name: "PhotoCleanerCore", targets: ["PhotoCleanerCore"])],
    targets: [
        .target(name: "PhotoCleanerCore"),
        .testTarget(name: "PhotoCleanerCoreTests", dependencies: ["PhotoCleanerCore"])
    ],
    swiftLanguageModes: [.v5]
)
