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
        .library(name: "VeeRuntime", targets: ["VeeRuntime"]),
        .library(name: "VeeMenu", targets: ["VeeMenu"]),
        .library(name: "VeeSearch", targets: ["VeeSearch"]),
        .library(name: "VeePreferences", targets: ["VeePreferences"]),
        .library(name: "VeeTrust", targets: ["VeeTrust"]),
        .library(name: "VeeCatalog", targets: ["VeeCatalog"]),
        .library(name: "VeeUI", targets: ["VeeUI"]),
        .library(name: "VeeWidgetShared", targets: ["VeeWidgetShared"]),
        .library(name: "VeeCLI", targets: ["VeeCLI"]),
        .library(name: "VeeApp", targets: ["VeeApp"]),
        .executable(name: "vee", targets: ["vee"]),
    ],
    targets: [
        .target(name: "VeeCore"),
        .target(name: "VeePluginFormat", dependencies: ["VeeCore"]),
        .target(name: "VeeRuntime", dependencies: ["VeeCore", "VeePluginFormat"]),
        .target(name: "VeeMenu", dependencies: ["VeeCore", "VeePluginFormat"]),
        // Pure, AppKit-free searchable-menu core: flatten a plugin's menu tree
        // into activatable rows and fuzzy-filter/rank them. Consumed by the app's
        // (future) search panel; kept independent so it is fully unit-testable.
        .target(name: "VeeSearch", dependencies: ["VeePluginFormat"]),
        .target(name: "VeePreferences", dependencies: ["VeeCore", "VeePluginFormat"]),
        .target(name: "VeeTrust", dependencies: ["VeeCore"]),
        .target(name: "VeeCatalog", dependencies: ["VeeCore"]),
        .target(name: "VeeUI", dependencies: ["VeeCore", "VeePluginFormat", "VeePreferences", "VeeTrust", "VeeCatalog"]),
        // Tiny Foundation-only module shared between the app and the WidgetKit /
        // Control Center extension via an App Group container. Kept dependency-free
        // so the extension links almost nothing.
        .target(name: "VeeWidgetShared"),
        // AppKit-free CLI logic (render/lint/new subcommands) so it builds
        // headless in CI. The `vee` executable dispatches to it.
        .target(name: "VeeCLI", dependencies: ["VeePluginFormat", "VeeRuntime"]),
        .target(name: "VeeApp", dependencies: ["VeeCore", "VeePluginFormat", "VeeRuntime", "VeeMenu", "VeePreferences", "VeeTrust", "VeeCatalog", "VeeUI", "VeeWidgetShared"]),
        .executableTarget(name: "vee", dependencies: ["VeeApp", "VeeCLI"]),
        .testTarget(name: "VeeCoreTests", dependencies: ["VeeCore"]),
        .testTarget(name: "VeePluginFormatTests", dependencies: ["VeePluginFormat"]),
        .testTarget(name: "VeeRuntimeTests", dependencies: ["VeeRuntime"]),
        .testTarget(name: "VeeMenuTests", dependencies: ["VeeMenu"]),
        .testTarget(name: "VeeSearchTests", dependencies: ["VeeSearch"]),
        .testTarget(name: "VeePreferencesTests", dependencies: ["VeePreferences"]),
        .testTarget(name: "VeeTrustTests", dependencies: ["VeeTrust"]),
        .testTarget(name: "VeeCatalogTests", dependencies: ["VeeCatalog"]),
        .testTarget(name: "VeeWidgetSharedTests", dependencies: ["VeeWidgetShared"]),
        .testTarget(name: "VeeCLITests", dependencies: ["VeeCLI"]),
        .testTarget(name: "VeeAppTests", dependencies: ["VeeApp"]),
    ]
)
