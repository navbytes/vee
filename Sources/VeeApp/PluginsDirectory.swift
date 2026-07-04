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

    private static func support(_ leaf: String) -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Vee/\(leaf)").path
    }

    static func ensureExists(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    @MainActor
    static func context(pluginPath: String, pluginsDirectory: String, declaredVariables: [String: String] = [:]) -> RuntimeEnvironmentContext {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        ensureExists(cacheDirectory())
        ensureExists(dataDirectory())
        return RuntimeEnvironmentContext(
            pluginPath: pluginPath,
            pluginsDirectory: pluginsDirectory,
            cacheDirectory: cacheDirectory(),
            dataDirectory: dataDirectory(),
            isDarkMode: dark,
            osVersion: (os.majorVersion, os.minorVersion, os.patchVersion),
            appVersion: version,
            declaredVariables: declaredVariables
        )
    }
}
