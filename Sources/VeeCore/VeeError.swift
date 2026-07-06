import Foundation

/// Errors surfaced across Vee's subsystems.
public enum VeeError: Error, Equatable, Sendable {
    /// A plugin process exceeded its execution deadline and was terminated.
    case executionTimedOut(pluginID: PluginID, seconds: TimeInterval)
    /// A plugin process exited with a non-zero status.
    case nonZeroExit(pluginID: PluginID, code: Int32, stderr: String)
    /// The plugin file could not be launched (missing, not executable, …).
    case launchFailed(pluginID: PluginID, reason: String)
    /// A plugin's stdout could not be decoded as text.
    case undecodableOutput(pluginID: PluginID)
    /// A plugin install was rejected because the requested filename was unsafe
    /// (path traversal, separators, or an empty/hidden name).
    case unsafePluginFilename(String)
}
