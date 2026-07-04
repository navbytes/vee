import Foundation

/// Installs a plugin's source into the plugins directory. The directory watcher
/// then loads it automatically.
public enum PluginInstaller {
    @discardableResult
    public static func install(filename: String, source: String, into directory: String, fileManager: FileManager = .default) throws -> String {
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = (directory as NSString).appendingPathComponent(filename)
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    public static func isInstalled(filename: String, in directory: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: (directory as NSString).appendingPathComponent(filename))
    }
}
