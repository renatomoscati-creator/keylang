// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudyKit",
    // Matches LinguaKeyCore. iOS 26 is the floor for the Translation framework,
    // and macOS is here so the store and the fold are testable without a device.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "StudyKit", targets: ["StudyKit"])
    ],
    dependencies: [
        .package(path: "../LinguaKeyCore")
    ],
    targets: [
        .target(name: "StudyKit", dependencies: ["LinguaKeyCore"]),
        .testTarget(name: "StudyKitTests", dependencies: ["StudyKit"])
    ]
)
