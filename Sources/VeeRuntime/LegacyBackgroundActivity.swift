import Foundation
import VeeCore

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
/// This exists purely to unstick those installs. It cannot be deleted until no
/// affected version is in the wild — a condition demonstrably not yet met: an
/// install was found in this state on 2026-08-23, relaunching within seconds of
/// every quit.
public enum LegacyBackgroundActivity {
    private static let log = VeeLog.make("legacy-activity")

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

    /// Clears every supplied plugin ID, and reports what it swept.
    ///
    /// `pluginIDs` must be every ID Vee has **ever** loaded, not the ones
    /// installed now. An activity outlives the plugin that registered it, and
    /// its identifier can only be built from that plugin's ID — so sweeping only
    /// what is currently on disk leaves a deleted plugin's activity permanently
    /// unnameable, which is how an install stays stuck.
    ///
    /// Runs unconditionally on every launch, with no "already migrated" flag: a
    /// stale registration can be reintroduced by downgrading, by restoring a
    /// backup, or by a second machine syncing preferences, and the sweep is a
    /// no-op when there is nothing to clear.
    ///
    /// ponytail: this reports what it *attempted*, not what it found.
    /// `NSBackgroundActivityScheduler` offers no way to ask whether an
    /// identifier was registered — `invalidate()` returns nothing and does not
    /// distinguish a hit from a miss — so "cleared" here means "named and
    /// invalidated". Anything that wanted to tell a user their stuck app was
    /// just fixed would need that distinction, and the API cannot provide it.
    @discardableResult
    public static func clearAll(pluginIDs: some Sequence<String>) -> [String] {
        let swept = pluginIDs.flatMap(identifiers(forPluginID:))
        guard !swept.isEmpty else { return [] }
        for identifier in swept {
            NSBackgroundActivityScheduler(identifier: identifier).invalidate()
        }
        log.info("swept \(swept.count, privacy: .public) legacy activity identifier(s)")
        return swept
    }
}
