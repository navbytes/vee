import Foundation

/// Context used to compute the environment variables injected into a plugin.
public struct RuntimeEnvironmentContext: Sendable {
    public var pluginPath: String
    public var pluginsDirectory: String
    public var cacheDirectory: String
    public var dataDirectory: String
    public var isDarkMode: Bool
    public var osVersion: (major: Int, minor: Int, patch: Int)
    public var appVersion: String
    /// Values from the plugin's declared `<xbar.var>` preferences.
    public var declaredVariables: [String: String]

    public init(pluginPath: String, pluginsDirectory: String, cacheDirectory: String, dataDirectory: String, isDarkMode: Bool, osVersion: (major: Int, minor: Int, patch: Int), appVersion: String, declaredVariables: [String: String] = [:]) {
        self.pluginPath = pluginPath
        self.pluginsDirectory = pluginsDirectory
        self.cacheDirectory = cacheDirectory
        self.dataDirectory = dataDirectory
        self.isDarkMode = isDarkMode
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.declaredVariables = declaredVariables
    }
}

/// Builds the environment variables Vee injects into plugins, matching the
/// xbar (`XBARDarkMode`) and SwiftBar (`SWIFTBAR_*`, `OS_*`) conventions so
/// existing plugins that read them keep working, plus Vee's own `VEE_*`.
public enum EnvironmentBuilder {
    /// The variables Vee injects (to be merged over the inherited user env).
    public static func injected(_ ctx: RuntimeEnvironmentContext) -> [String: String] {
        var env: [String: String] = [:]

        // xbar
        env["XBARDarkMode"] = ctx.isDarkMode ? "true" : "false"

        // SwiftBar compatibility
        env["SWIFTBAR"] = "1"
        env["SWIFTBAR_VERSION"] = ctx.appVersion
        env["SWIFTBAR_BUILD"] = ctx.appVersion
        env["SWIFTBAR_PLUGINS_PATH"] = ctx.pluginsDirectory
        env["SWIFTBAR_PLUGIN_PATH"] = ctx.pluginPath
        env["SWIFTBAR_PLUGIN_CACHE_PATH"] = ctx.cacheDirectory
        env["SWIFTBAR_PLUGIN_DATA_PATH"] = ctx.dataDirectory
        env["OS_APPEARANCE"] = ctx.isDarkMode ? "Dark" : "Light"
        env["OS_VERSION_MAJOR"] = String(ctx.osVersion.major)
        env["OS_VERSION_MINOR"] = String(ctx.osVersion.minor)
        env["OS_VERSION_PATCH"] = String(ctx.osVersion.patch)

        // Vee-native
        env["VEE"] = "1"
        env["VEE_VERSION"] = ctx.appVersion
        env["VEE_PLUGIN_PATH"] = ctx.pluginPath
        // The plugin's id (its filename) — matches `PluginID`, so a plugin can
        // post an actionable alert with `swiftbar://notify?plugin=$VEE_PLUGIN_ID`
        // and Vee resolves the Re-run / Silence / Open-log actions back to it.
        env["VEE_PLUGIN_ID"] = (ctx.pluginPath as NSString).lastPathComponent

        // Declared preferences win over everything else.
        for (key, value) in ctx.declaredVariables { env[key] = value }
        return env
    }

    /// The inherited user environment merged with the injected variables.
    public static func merged(base: [String: String], context ctx: RuntimeEnvironmentContext) -> [String: String] {
        base.merging(injected(ctx)) { _, injected in injected }
    }
}
