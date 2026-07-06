import Foundation
import VeeCore

/// Installs a plugin's source into the plugins directory. The directory watcher
/// then loads it automatically.
public enum PluginInstaller {
    @discardableResult
    public static func install(filename: String, source: String, into directory: String, fileManager: FileManager = .default) throws -> String {
        // A plugin filename is attacker-influenced (it can come from a
        // `swiftbar://addplugin?src=…` URL's last path component, which is
        // percent-decoded — so `..%2f..%2fevil.sh` decodes to `../../evil.sh`).
        // Reduce to a single, safe path component before touching the disk, and
        // verify the resolved path stays inside the plugins directory.
        let safeName = try sanitizedFilename(filename)
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = (directory as NSString).appendingPathComponent(safeName)
        try assertContained(path, in: directory, requested: filename)
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    public static func isInstalled(filename: String, in directory: String, fileManager: FileManager = .default) -> Bool {
        guard let safeName = try? sanitizedFilename(filename) else { return false }
        return fileManager.fileExists(atPath: (directory as NSString).appendingPathComponent(safeName))
    }

    /// Validates that an untrusted filename is a single safe path component,
    /// throwing `VeeError.unsafePluginFilename` otherwise. It rejects rather than
    /// silently rewrites, so a hostile `src` can't quietly land as its basename
    /// (which might overwrite a legitimately-named plugin). Callers that want a
    /// fallback catch the throw. Rejects separators, `.`/`..`, hidden/dotfiles,
    /// path/HFS separators, control characters, and empties.
    public static func sanitizedFilename(_ raw: String) throws -> String {
        let invalid = raw.isEmpty
            || raw == "."
            || raw == ".."
            || raw.hasPrefix(".")
            || raw.contains("/")
            || raw.contains(":")
            || raw.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        guard !invalid else { throw VeeError.unsafePluginFilename(raw) }
        return raw
    }

    /// Defense in depth: confirm the final path's directory is exactly the
    /// intended plugins directory after `..`/symlink normalization.
    private static func assertContained(_ path: String, in directory: String, requested: String) throws {
        let parent = ((path as NSString).standardizingPath as NSString).deletingLastPathComponent
        let target = (directory as NSString).standardizingPath
        guard parent == target else { throw VeeError.unsafePluginFilename(requested) }
    }
}
