import XCTest
@testable import VeeRuntime

/// The sweep that keeps Vee quittable.
///
/// What is asserted here is which identifiers get **named**, because that is
/// the whole of the bug: an activity survives in launchd, its identifier can
/// only be built from the plugin ID that registered it, and a plugin deleted
/// before this shipped left an identifier nothing could construct. Whether an
/// invalidated identifier was actually registered is unobservable —
/// `NSBackgroundActivityScheduler.invalidate()` returns nothing and does not
/// distinguish a hit from a miss — so naming the right set is the property
/// worth pinning, and the only one available.
final class LegacyBackgroundActivityTests: XCTestCase {
    func testBothIdentifierFormsAreCoveredForOnePlugin() {
        XCTAssertEqual(
            LegacyBackgroundActivity.identifiers(forPluginID: "prs.10m.js"),
            ["com.vee.refresh.prs.10m.js", "com.vee.refresh.widget.prs.10m.js"]
        )
    }

    func testClearAllCoversEveryIdentifierFormForEveryPlugin() {
        let swept = LegacyBackgroundActivity.clearAll(pluginIDs: ["a.10m.sh", "b.30s.sh"])
        XCTAssertEqual(
            Set(swept),
            [
                "com.vee.refresh.a.10m.sh", "com.vee.refresh.widget.a.10m.sh",
                "com.vee.refresh.b.30s.sh", "com.vee.refresh.widget.b.30s.sh"
            ]
        )
    }

    func testClearAllOnAnEmptySetIsANoOp() {
        XCTAssertTrue(LegacyBackgroundActivity.clearAll(pluginIDs: [String]()).isEmpty)
    }

    /// The case the whole change exists for: an ID with no plugin behind it any
    /// more is still swept. Nothing about the sweep consults the filesystem.
    func testAnIDWhosePluginIsGoneIsStillSwept() {
        let swept = LegacyBackgroundActivity.clearAll(pluginIDs: ["deleted-long-ago.10m.js"])
        XCTAssertEqual(
            swept,
            ["com.vee.refresh.deleted-long-ago.10m.js", "com.vee.refresh.widget.deleted-long-ago.10m.js"]
        )
    }

    /// Sweeping twice must behave identically — there is no "already migrated"
    /// flag, because a stale registration can reappear via a downgrade, a
    /// restored backup, or synced preferences.
    func testSweepingIsRepeatable() {
        let first = LegacyBackgroundActivity.clearAll(pluginIDs: ["a.10m.sh"])
        let second = LegacyBackgroundActivity.clearAll(pluginIDs: ["a.10m.sh"])
        XCTAssertEqual(first, second)
    }
}
