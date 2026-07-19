import Foundation
import VeeCore
import VeeRuntime

/// Resolves the `<plugin>` argument of `vee show` to a concrete file. Accepts
/// either a path (`./cpu.10s.sh`, absolute, or relative to the cwd) or the name
/// of an installed plugin (`cpu`), matched against the plugins directory the way
/// the app resolves it. Pure with respect to its `FileManager` so it is tested
/// against a temporary directory.
enum PluginResolver {
    struct Resolved: Equatable, Sendable {
        var path: String
        var displayName: String
        var interval: RefreshInterval
    }

    enum ResolveError: Error, Equatable {
        /// The argument looked like a path but no file exists there.
        case fileNotFound(String)
        /// The argument was a name with no match; carries the available names.
        case nameNotFound(name: String, available: [String])
    }

    /// Resolves `argument` against `directory` (the plugins folder, used only for
    /// name lookups). `currentDirectory` anchors relative paths.
    static func resolve(
        argument: String,
        directory: String,
        currentDirectory: String,
        fileManager: FileManager = .default
    ) -> Result<Resolved, ResolveError> {
        // A path-shaped argument (has a separator, a tilde, or names an existing
        // file) is taken literally; otherwise it's an installed-plugin name.
        if looksLikePath(argument, currentDirectory: currentDirectory, fileManager: fileManager) {
            let absolute = absolutePath(argument, currentDirectory: currentDirectory)
            guard fileManager.fileExists(atPath: absolute) else {
                return .failure(.fileNotFound(absolute))
            }
            let name = (absolute as NSString).lastPathComponent
            let parsed = PluginFilename(name)
            return .success(Resolved(path: absolute, displayName: parsed.name, interval: parsed.interval))
        }

        let plugins = PluginDiscovery.enabled(directory: directory, fileManager: fileManager)
        // Match on the parsed name (`cpu` for `cpu.10s.sh`) first, then the full
        // filename, both case-insensitively — a forgiving lookup for a human arg.
        let lowered = argument.lowercased()
        if let hit = plugins.first(where: { $0.filename.name.lowercased() == lowered })
            ?? plugins.first(where: { ($0.path as NSString).lastPathComponent.lowercased() == lowered }) {
            return .success(Resolved(path: hit.path, displayName: hit.filename.name, interval: hit.filename.interval))
        }

        let available = plugins.map(\.filename.name).sorted()
        return .failure(.nameNotFound(name: argument, available: available))
    }

    private static func looksLikePath(_ arg: String, currentDirectory: String, fileManager: FileManager) -> Bool {
        if arg.contains("/") || arg.hasPrefix("~") || arg.hasPrefix(".") { return true }
        // A bare token that happens to name a file in the cwd is also a path.
        let candidate = (currentDirectory as NSString).appendingPathComponent(arg)
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: candidate, isDirectory: &isDir) && !isDir.boolValue
    }

    private static func absolutePath(_ arg: String, currentDirectory: String) -> String {
        let expanded = (arg as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath { return expanded }
        return (currentDirectory as NSString).appendingPathComponent(expanded)
    }

    /// The plugins directory, resolved like `VeeApp.PluginsDirectory` but without
    /// the AppKit dependency: `--dir` (passed in) → `VEE_PLUGINS_DIR` → the app's
    /// stored `vee.pluginsDirectory` default → Application Support.
    static func pluginsDirectory(
        override explicit: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> String {
        if let explicit, !explicit.isEmpty { return (explicit as NSString).expandingTildeInPath }
        if let env = environment["VEE_PLUGINS_DIR"], !env.isEmpty { return (env as NSString).expandingTildeInPath }
        if let custom = defaults.string(forKey: "vee.pluginsDirectory"), !custom.isEmpty {
            return (custom as NSString).expandingTildeInPath
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("Vee/plugins").path
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Vee/plugins")
    }
}
