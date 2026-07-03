import Foundation

/// A stable identifier for a plugin, derived from its filename (without path).
/// Two files with the same basename in different directories are considered the
/// same logical plugin for the purposes of preferences and trust storage.
public struct PluginID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Derives the id from a filesystem path (uses the last path component).
    public init(path: String) {
        self.rawValue = (path as NSString).lastPathComponent
    }

    public var description: String { rawValue }
}
