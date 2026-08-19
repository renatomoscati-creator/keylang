// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinguaKeyCore",
    // iOS 26 is the floor because headless TranslationSession and Foundation
    // Models both require it. This package itself is pure Foundation and has no
    // UIKit or Translation dependency, which is deliberate: it must compile and
    // be testable on the Mac, so the memory model and focus selection can be
    // verified without a device.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LinguaKeyCore", targets: ["LinguaKeyCore"])
    ],
    targets: [
        // No resources. The linguistic tables and the golden vectors both live
        // at the repository root and are already committed there; copying them
        // in would put a second 3.9 MB of identical binary under version control
        // to serve a code path the product never takes. The app stages them into
        // the App Group container, and the tests read them via `#filePath`.
        .target(name: "LinguaKeyCore"),
        .testTarget(
            name: "LinguaKeyCoreTests",
            dependencies: ["LinguaKeyCore"]
        )
    ]
)
