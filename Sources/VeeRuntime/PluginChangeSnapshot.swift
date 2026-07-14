import Foundation

/// A per-file identity snapshot of a set of discovered plugins — detects an
/// in-place edit to an *existing* plugin (same path, changed content), which a
/// bare path-set comparison would miss. `AppController.reload()` keys its
/// rebuild-or-skip decision on equality between two snapshots taken across a
/// rescan. Pure with respect to its `FileManager` so it's unit-testable
/// against a temporary directory (mirrors `PluginDiscovery`).
public enum PluginChangeSnapshot {
    /// One file's identity: modification time paired with size, so two writes
    /// landing in the same filesystem mtime tick (coarse on some volumes)
    /// still register as a change if their byte count differs.
    public struct FileIdentity: Sendable, Equatable {
        public var modified: TimeInterval
        public var size: Int
    }

    /// A path → identity map for `plugins`. Two snapshots compare equal only
    /// if every plugin's path, mtime, and size all match — an in-place edit
    /// (same path, new mtime/size) or an add/remove (path set differs) both
    /// break equality.
    public static func snapshot(_ plugins: [DiscoveredPlugin], fileManager: FileManager = .default) -> [String: FileIdentity] {
        var result: [String: FileIdentity] = [:]
        for plugin in plugins {
            let attrs = try? fileManager.attributesOfItem(atPath: plugin.path)
            let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attrs?[.size] as? Int) ?? 0
            result[plugin.path] = FileIdentity(modified: modified, size: size)
        }
        return result
    }
}
