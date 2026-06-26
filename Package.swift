// swift-tools-version: 6.2
import PackageDescription

// Vee — native macOS launcher with a JavaScriptCore plugin platform.
//
// Target graph (see docs/ARCHITECTURE.md and the build plan):
//
//   VeeProtocol            (frozen wire contract; Foundation only)
//     ├─ VeeFuzzy          (leaf)
//     ├─ VeeCache          (leaf)
//     ├─ VeeKeychain       (leaf)
//     └─ VeeJSONPatch      (leaf)
//          ↓
//       VeeEngine   (← Protocol, JSONPatch, Cache, Keychain)
//       VeeServices (← Protocol, Fuzzy, Keychain, Cache)
//          ↓
//       VeeApp      (← Engine, Services, Fuzzy, Protocol)   [library, testable]
//          ↓
//       vee         (thin executable entrypoint)
//
// The four leaf libraries + VeeProtocol build in strict Swift 6 language mode
// (pure value types). VeeEngine/VeeServices/VeeApp relax to the v5 language
// mode locally because JSC (JSContext/JSValue) and AppKit are not Sendable /
// are @MainActor; the contract types crossing target boundaries are Sendable,
// which is what matters for cross-target safety.

let relaxedConcurrency: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Vee",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "vee", targets: ["vee"]),
        .library(name: "VeeProtocol", targets: ["VeeProtocol"]),
        .library(name: "VeeFuzzy", targets: ["VeeFuzzy"]),
        .library(name: "VeeCache", targets: ["VeeCache"]),
        .library(name: "VeeKeychain", targets: ["VeeKeychain"]),
        .library(name: "VeeJSONPatch", targets: ["VeeJSONPatch"]),
        .library(name: "VeeEngine", targets: ["VeeEngine"]),
        .library(name: "VeeServices", targets: ["VeeServices"]),
        .library(name: "VeeApp", targets: ["VeeApp"]),
    ],
    targets: [
        // MARK: Frozen contract (leaf, Foundation only)
        .target(name: "VeeProtocol"),

        // MARK: Leaf libraries (depend only on VeeProtocol)
        .target(name: "VeeFuzzy", dependencies: ["VeeProtocol"]),
        .target(name: "VeeCache", dependencies: ["VeeProtocol"]),
        .target(name: "VeeKeychain", dependencies: ["VeeProtocol"]),
        .target(name: "VeeJSONPatch", dependencies: ["VeeProtocol"]),

        // MARK: Engine + host-native services
        .target(
            name: "VeeEngine",
            dependencies: ["VeeProtocol", "VeeJSONPatch", "VeeCache", "VeeKeychain"],
            swiftSettings: relaxedConcurrency
        ),
        .target(
            name: "VeeServices",
            dependencies: ["VeeProtocol", "VeeFuzzy", "VeeKeychain", "VeeCache"],
            swiftSettings: relaxedConcurrency
        ),

        // MARK: App shell (testable library + thin executable)
        .target(
            name: "VeeApp",
            dependencies: ["VeeEngine", "VeeServices", "VeeFuzzy", "VeeProtocol"],
            swiftSettings: relaxedConcurrency
        ),
        .executableTarget(
            name: "vee",
            dependencies: ["VeeApp"],
            swiftSettings: relaxedConcurrency
        ),

        // MARK: Out-of-process plugin host (child process; JSC + real bridges)
        .executableTarget(
            name: "vee-plugin-host",
            dependencies: ["VeeEngine", "VeeServices", "VeeProtocol"],
            swiftSettings: relaxedConcurrency
        ),

        // MARK: Test targets (one per source target)
        .testTarget(name: "VeeProtocolTests", dependencies: ["VeeProtocol"]),
        .testTarget(name: "VeeFuzzyTests", dependencies: ["VeeFuzzy", "VeeProtocol"]),
        .testTarget(name: "VeeCacheTests", dependencies: ["VeeCache", "VeeProtocol"]),
        .testTarget(name: "VeeKeychainTests", dependencies: ["VeeKeychain", "VeeProtocol"]),
        .testTarget(name: "VeeJSONPatchTests", dependencies: ["VeeJSONPatch", "VeeProtocol"]),
        .testTarget(
            name: "VeeEngineTests",
            dependencies: ["VeeEngine", "VeeProtocol", "VeeJSONPatch", "VeeKeychain"],
            swiftSettings: relaxedConcurrency
        ),
        .testTarget(
            name: "VeeServicesTests",
            dependencies: ["VeeServices", "VeeProtocol", "VeeFuzzy"],
            swiftSettings: relaxedConcurrency
        ),
        .testTarget(
            name: "VeeAppTests",
            dependencies: ["VeeApp", "VeeProtocol"],
            swiftSettings: relaxedConcurrency
        ),
    ]
)
