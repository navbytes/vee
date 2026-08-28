import Foundation
import VeeCore

/// Installs a plugin's source into the plugins directory. The directory watcher
/// then loads it automatically.
public enum PluginInstaller {
    /// Writes `source` to `filename` in `directory` — for a brand-new install
    /// AND an in-place update alike (there is no separate "update" entry
    /// point; Discover's Update button calls this same function). `write(
    /// toFile:atomically:)` writes to a temp file in the same directory and
    /// renames it over the destination, so this is a true atomic *replace*:
    /// there is never a moment where `filename` is briefly absent for an
    /// existing plugin being updated, which matters for
    /// `AppController.reconcileDiskState`'s disk-authoritative GC — a
    /// directory listing taken mid-update always shows either the old or the
    /// new content, never "missing".
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
        vendorSDKIfNeeded(for: source, filename: safeName, in: directory, fileManager: fileManager)
        return path
    }

    /// Writes the vendored SDK beside a plugin that imports it, when the
    /// directory has no copy yet.
    ///
    /// A Vee plugin is a single file with no build step, so its SDK travels as
    /// a sibling — `vee.py` next to a Python plugin, `vee.ts` next to a
    /// TypeScript one. That works in the plugin repository, where the file is
    /// checked in beside the plugins, and it works for `vee new`, which writes
    /// both. It did not work for the two paths that install *one* file: a
    /// plugin downloaded from Discover or opened from an `addplugin` link
    /// landed alone, and every run died on `ModuleNotFoundError: No module
    /// named 'vee'` — a traceback in the menu bar for something the user did
    /// nothing to cause and had no way to read as "fetch a second file".
    ///
    /// Best-effort by design: a plugin that has been written is installed, and
    /// failing to place a companion must not undo that or surface as an install
    /// error. The plugin still runs the moment an SDK appears beside it.
    ///
    /// An existing SDK file is never overwritten. A directory that already has
    /// one is a directory someone else is curating — the plugin repository's
    /// own copy, or a newer SDK a previous install vendored — and replacing it
    /// could break the plugins already relying on it.
    private static func vendorSDKIfNeeded(for source: String, filename: String, in directory: String, fileManager: FileManager) {
        guard let language = sdkLanguage(forPlugin: filename, source: source),
              let sdkName = EmbeddedSDK.filename(for: language),
              let sdkSource = EmbeddedSDK.source(for: language)
        else { return }
        let sdkPath = (directory as NSString).appendingPathComponent(sdkName)
        guard !fileManager.fileExists(atPath: sdkPath) else { return }
        try? sdkSource.write(toFile: sdkPath, atomically: true, encoding: .utf8)
    }

    /// The SDK a plugin needs beside it, or nil if it needs none.
    ///
    /// Matched on the import the SDK is actually reached through, not on the
    /// file extension alone: most Python plugins vendor nothing, and writing a
    /// 34 KB `vee.py` next to every `.py` file someone installs would litter
    /// the directory with a dependency they never asked for.
    ///
    /// Go is deliberately absent — a Go plugin is a compiled binary that
    /// imports the module, so there is no sibling file to vendor.
    static func sdkLanguage(forPlugin filename: String, source: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "py":
            // `from vee import X` / `import vee` — anchored so a plugin that
            // merely mentions vee in a comment or its own `vee_` helper isn't
            // mistaken for one that imports the SDK.
            let pattern = #"(?m)^\s*(from\s+vee\s+import\s|import\s+vee\s*$)"#
            return source.range(of: pattern, options: .regularExpression) != nil ? "python" : nil
        case "ts":
            // The vendored SDK is imported by relative path (`./vee.ts`); a
            // package import of `@navbytes/vee` resolves through npm instead
            // and needs no sibling.
            return source.range(of: #"from\s+['"]\./vee(\.ts)?['"]"#, options: .regularExpression) != nil ? "typescript" : nil
        default:
            return nil
        }
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
