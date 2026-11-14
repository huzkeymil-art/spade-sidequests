// swift-tools-version: 5.9
import PackageDescription

// The game's rules as a standalone Swift package.
//
// The app itself compiles these same source files directly into its own
// module. This package exists so the rules can be tested on their own with
// `swift test`, on a Mac or on Linux, with no simulator involved.
let package = Package(
    name: "SpadeCore",
    products: [
        .library(name: "SpadeCore", targets: ["SpadeCore"]),
    ],
    targets: [
        .target(
            name: "SpadeCore",
            resources: [.process("Content")]
        ),
        .testTarget(
            name: "SpadeCoreTests",
            dependencies: ["SpadeCore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
