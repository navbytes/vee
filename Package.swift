// swift-tools-version: 6.2
import PackageDescription

// Vee — a native macOS menu-bar script runner (xbar successor).
//
// All testable logic lives in library targets (built and tested with `swift test`).
// `VeeApp` holds the AppKit shell as a library so it is unit-testable; the `vee`
// executable is a thin entry point for `swift run` during development. The
// distributable `Vee.app` bundle is produced by the XcodeGen-generated Xcode
// target (see project.yml), which links the same libraries.
let package = Package(
    name: "Vee",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VeeCore", targets: ["VeeCore"]),
        .library(name: "VeePluginFormat", targets: ["VeePluginFormat"]),
        .library(name: "VeeApp", targets: ["VeeApp"]),
        .executable(name: "vee", targets: ["vee"]),
    ],
    targets: [
        .target(name: "VeeCore"),
        .target(name: "VeePluginFormat", dependencies: ["VeeCore"]),
        .target(name: "VeeApp", dependencies: ["VeeCore"]),
        .executableTarget(name: "vee", dependencies: ["VeeApp"]),
        .testTarget(name: "VeeCoreTests", dependencies: ["VeeCore"]),
        .testTarget(name: "VeePluginFormatTests", dependencies: ["VeePluginFormat"]),
    ]
)
