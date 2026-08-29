import AppKit
import Foundation
import VeePreferences
import VeeRuntime

/// Resolves the directories Vee uses and builds the per-run environment context.
enum PluginsDirectory {
    /// The plugins directory. Precedence: `VEE_PLUGINS_DIR` env (dev/testing) →
    /// a user-chosen folder → the default under Application Support.
    static func resolve() -> String {
        if let override = ProcessInfo.processInfo.environment["VEE_PLUGINS_DIR"], !override.isEmpty {
            return (override as NSString).expandingTildeInPath
        }
        if let custom = AppPreferences.shared.pluginsDirectory, !custom.isEmpty {
            return (custom as NSString).expandingTildeInPath
        }
        return support("plugins")
    }

    static func cacheDirectory() -> String { support("cache") }
    static func dataDirectory() -> String { support("data") }
    /// Vee's own copy of the plugin SDKs, put on each plugin's import path so a
    /// plugin that imports the SDK runs without one sitting beside it. Vee's to
    /// manage: rewritten to match the running build, never read from a user's
    /// plugins folder.
    static func sdkDirectory() -> String { SDKProvisioner.defaultRoot }

    private static func support(_ leaf: String) -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Vee/\(leaf)").path
    }

    static func ensureExists(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    @MainActor
    static func context(pluginPath: String, pluginsDirectory: String, declaredVariables: [String: String] = [:], target: PluginTarget = .menu) -> RuntimeEnvironmentContext {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        // `NSApp` is nil until the app finishes launching (and in unit tests) —
        // in production this is only ever called from a running app, but guard
        // the implicit unwrap so a nil `NSApp` degrades to light mode instead of
        // crashing (and so this stays callable without a live NSApplication).
        let dark = (NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua) == .darkAqua
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.2"
        ensureExists(cacheDirectory())
        ensureExists(dataDirectory())
        // Refreshed here rather than once at launch so an upgraded Vee serves
        // its own SDK on the very next plugin run, and a support directory
        // deleted underneath us is rebuilt rather than silently missing.
        let sdkRoot = SDKProvisioner.provision(into: sdkDirectory())
        return RuntimeEnvironmentContext(
            pluginPath: pluginPath,
            pluginsDirectory: pluginsDirectory,
            cacheDirectory: cacheDirectory(),
            dataDirectory: dataDirectory(),
            isDarkMode: dark,
            osVersion: (os.majorVersion, os.minorVersion, os.patchVersion),
            appVersion: version,
            declaredVariables: declaredVariables,
            target: target,
            sdkDirectory: sdkRoot
        )
    }
}
