import Foundation
import VeeCore

/// A plugin file found in the plugins directory.
public struct DiscoveredPlugin: Sendable, Equatable {
    public var path: String
    public var id: PluginID
    public var filename: PluginFilename
    public var isExecutable: Bool

    public init(path: String, id: PluginID, filename: PluginFilename, isExecutable: Bool) {
        self.path = path
        self.id = id
        self.filename = filename
        self.isExecutable = isExecutable
    }
}

/// Enumerates plugin files in a directory. Pure with respect to its `FileManager`
/// so it can be tested against a temporary directory.
public enum PluginDiscovery {
    /// Extensions that are clearly not plugins (docs/data), skipped so stray
    /// files in the plugins folder don't get run.
    private static let ignoredExtensions: Set<String> = [
        "md", "markdown", "txt", "json", "plist", "log", "lock",
        "png", "jpg", "jpeg", "gif", "svg", "pdf", "yml", "yaml",
    ]

    /// Lists candidate plugins in `directory`, sorted by filename. Skips hidden
    /// files, `.vars.json` preference sidecars, subdirectories (a `disabled/`
    /// subfolder is a common convention for parking plugins), and obvious
    /// non-plugin document/data files.
    public static func enumerate(directory: String, fileManager: FileManager = .default) -> [DiscoveredPlugin] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }

        return names.sorted().compactMap { name -> DiscoveredPlugin? in
            if name.hasPrefix(".") { return nil }
            if name.hasSuffix(".vars.json") { return nil }

            let path = (directory as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }

            let filename = PluginFilename(name)
            if ignoredExtensions.contains(filename.ext.lowercased()) { return nil }

            return DiscoveredPlugin(
                path: path,
                id: PluginID(path: path),
                filename: filename,
                isExecutable: fileManager.isExecutableFile(atPath: path)
            )
        }
    }

    /// The set Vee will run. Includes non-executable plugins (they are run
    /// bash-wrapped, matching SwiftBar), so a plugin without the execute bit is
    /// still loaded.
    public static func enabled(directory: String, fileManager: FileManager = .default) -> [DiscoveredPlugin] {
        enumerate(directory: directory, fileManager: fileManager)
    }
}
