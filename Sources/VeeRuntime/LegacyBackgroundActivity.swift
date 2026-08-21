import Foundation

/// Removes `NSBackgroundActivityScheduler` registrations left behind by earlier
/// versions of Vee.
///
/// Vee used to drive long-interval (≥10 min) refreshes with
/// `NSBackgroundActivityScheduler`. That registers a **repeating XPC activity
/// with launchd, pointed at the app's own launchd job** — and XPC activities are
/// *launch-on-demand*. So once such a plugin existed, launchd would relaunch Vee
/// to service the activity within moments of the user quitting it, and Vee could
/// not be quit at all:
///
///     event triggers = {
///         com.vee.refresh.prs-and-jira.10m.js => {
///             service    = application.com.vee.app…   ← relaunches Vee
///             "Repeating" => true
///             "Interval"  => 600
///         }
///     }
///     immediate reason = launch job demand
///
/// The registration lives in launchd, not in the app, so it survives the update
/// that stops creating it. Anyone upgrading from an affected version keeps the
/// un-quittable behavior until the activity is explicitly invalidated —
/// constructing a scheduler with the same identifier and invalidating it is the
/// only way to refer to one that a previous process registered.
///
/// This exists purely to unstick those installs and can be deleted once no
/// affected version is in the wild.
public enum LegacyBackgroundActivity {
    /// The identifiers earlier versions used, for one plugin ID.
    public static func identifiers(forPluginID pluginID: String) -> [String] {
        ["com.vee.refresh.\(pluginID)", "com.vee.refresh.widget.\(pluginID)"]
    }

    /// Invalidates any activity previously registered under these identifiers.
    /// Invalidating one that was never registered is a no-op, so this is safe to
    /// call unconditionally on every launch.
    public static func clear(forPluginID pluginID: String) {
        for identifier in identifiers(forPluginID: pluginID) {
            NSBackgroundActivityScheduler(identifier: identifier).invalidate()
        }
    }
}
