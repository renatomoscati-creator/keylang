// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudyKit",
    // Matches LinguaKeyCore. iOS 26 is the floor for the Translation framework,
    // and macOS is here so the store and the fold are testable without a device.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "StudyKit", targets: ["StudyKit"]),
        // The study surface itself, shared by the app and the share extension
        // because they are two processes and two copies of it drift within a
        // week. It is a package target rather than a folder in one of them so
        // neither target has to reach into the other's sources.
        .library(name: "StudyUI", targets: ["StudyUI"]),
        // The single place that imports Translation. Separate from StudyUI so a
        // test target can link the study surface without dragging in a framework
        // that does not exist in the Simulator.
        .library(name: "StudySystem", targets: ["StudySystem"])
    ],
    dependencies: [
        .package(path: "../LinguaKeyCore")
    ],
    targets: [
        .target(name: "StudyKit", dependencies: ["LinguaKeyCore"]),
        .target(name: "StudyUI", dependencies: ["StudyKit", "LinguaKeyCore"]),
        .target(name: "StudySystem", dependencies: ["StudyKit"]),
        .testTarget(name: "StudyKitTests", dependencies: ["StudyKit"])
    ]
)
