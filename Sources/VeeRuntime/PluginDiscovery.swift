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
    /// Lists candidate plugins in `directory`, sorted by filename. Skips hidden
    /// files, `.vars.json` preference sidecars, and subdirectories (a `disabled/`
    /// subfolder is a common convention for parking plugins).
    public static func enumerate(directory: String, fileManager: FileManager = .default) -> [DiscoveredPlugin] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }

        return names.sorted().compactMap { name -> DiscoveredPlugin? in
            if name.hasPrefix(".") { return nil }
            if name.hasSuffix(".vars.json") { return nil }

            let path = (directory as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }

            return DiscoveredPlugin(
                path: path,
                id: PluginID(path: path),
                filename: PluginFilename(name),
                isExecutable: fileManager.isExecutableFile(atPath: path)
            )
        }
    }

    /// The subset that is executable (the set Vee will actually run).
    public static func enabled(directory: String, fileManager: FileManager = .default) -> [DiscoveredPlugin] {
        enumerate(directory: directory, fileManager: fileManager).filter(\.isExecutable)
    }
}
