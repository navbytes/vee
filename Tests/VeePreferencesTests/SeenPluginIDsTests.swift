import XCTest
@testable import VeePreferences

/// The record of every plugin Vee has ever loaded.
///
/// It exists so a legacy launchd activity can still be named after the plugin
/// that registered it is gone — so the assertions that matter are about
/// *persistence past deletion*, not about tracking what is installed.
final class SeenPluginIDsTests: XCTestCase {
    private func makePrefs() -> (AppPreferences, String) {
        let suiteName = "vee.tests.seen.\(UUID().uuidString)"
        return (AppPreferences(defaults: UserDefaults(suiteName: suiteName)!), suiteName)
    }

    func testStartsEmpty() {
        let (prefs, suite) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        XCTAssertTrue(prefs.seenPluginIDs().isEmpty)
    }

    func testRecordingRoundTrips() {
        let (prefs, suite) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        prefs.recordSeenPlugins(["a.30s.sh", "b.10m.js"])
        XCTAssertEqual(prefs.seenPluginIDs(), ["a.30s.sh", "b.10m.js"])
    }

    func testRecordingAccumulatesAcrossCalls() {
        let (prefs, suite) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        prefs.recordSeenPlugins(["a.30s.sh"])
        prefs.recordSeenPlugins(["b.10m.js"])
        XCTAssertEqual(prefs.seenPluginIDs(), ["a.30s.sh", "b.10m.js"])
    }

    func testRecordingTheSameIDsAgainChangesNothing() {
        let (prefs, suite) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        prefs.recordSeenPlugins(["a.30s.sh"])
        prefs.recordSeenPlugins(["a.30s.sh"])
        XCTAssertEqual(prefs.seenPluginIDs(), ["a.30s.sh"])
    }

    func testRecordingNothingIsHarmless() {
        let (prefs, suite) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        prefs.recordSeenPlugins(["a.30s.sh"])
        prefs.recordSeenPlugins([String]())
        XCTAssertEqual(prefs.seenPluginIDs(), ["a.30s.sh"])
    }

    /// The point of the whole record: an ID outlives its plugin. Nothing prunes
    /// this set, because a plugin's removal is exactly what it exists to
    /// survive.
    func testAnIDSurvivesItsPluginBeingUninstalled() {
        let (prefs, suite) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        prefs.recordSeenPlugins(["deleted.10m.js", "kept.30s.sh"])

        // A later launch sees only the surviving plugin on disk.
        prefs.recordSeenPlugins(["kept.30s.sh"])

        XCTAssertTrue(
            prefs.seenPluginIDs().contains("deleted.10m.js"),
            "a plugin that is gone is precisely the one whose activity must still be nameable"
        )
    }

    func testTheRecordPersistsAcrossInstances() {
        let suiteName = "vee.tests.seen.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        AppPreferences(defaults: UserDefaults(suiteName: suiteName)!).recordSeenPlugins(["a.30s.sh"])
        XCTAssertEqual(
            AppPreferences(defaults: UserDefaults(suiteName: suiteName)!).seenPluginIDs(),
            ["a.30s.sh"]
        )
    }
}
