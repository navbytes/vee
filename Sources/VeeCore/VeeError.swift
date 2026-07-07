import Foundation

/// Errors surfaced across Vee's subsystems.
public enum VeeError: Error, Equatable, Sendable {
    /// The plugin file could not be launched (missing, not executable, …).
    case launchFailed(pluginID: PluginID, reason: String)
    /// A plugin install was rejected because the requested filename was unsafe
    /// (path traversal, separators, or an empty/hidden name).
    case unsafePluginFilename(String)
}
