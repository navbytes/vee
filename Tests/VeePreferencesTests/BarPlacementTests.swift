import XCTest
@testable import VeePreferences

/// `BarPlacement` and its storage: where a plugin appears in the menu bar
/// (`plugin-bar-placement`). The value is the user's — no plugin declaration
/// reaches it — and the migration below is the one that must not move a single
/// plugin on an install upgrading into placements.
final class BarPlacementTests: XCTestCase {
    private func makePrefs() -> (prefs: AppPreferences, suiteName: String) {
        let suiteName = "vee-placement-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AppPreferences(defaults: defaults), suiteName)
    }

    // MARK: - Encoding

    func testEveryPlacementRoundTrips() {
        let placements: [BarPlacement] = [.own, .foldedDefault, .folded(group: "Work"), .hidden]
        for placement in placements {
            XCTAssertEqual(BarPlacement(encoded: placement.encoded), placement, "\(placement) must survive a storage round trip")
        }
    }

    func testFoldedKeepsItsGroupName() {
        XCTAssertEqual(BarPlacement.foldedDefault.encoded, "folded:Vee", "the group is stored so a later multi-group build reads today's values unchanged")
    }

    /// A group name is free-form, so it may itself contain the separator; the
    /// decode must split on the first one only.
    func testGroupNameMayContainTheSeparator() {
        let placement = BarPlacement.folded(group: "a:b")
        XCTAssertEqual(BarPlacement(encoded: placement.encoded), placement)
    }

    /// Anything this build does not recognise decodes to `nil` so the caller
    /// falls back to the default, rather than being stranded on a surface this
    /// build cannot draw.
    func testUnrecognisedEncodingsDecodeToNil() {
        for encoded in ["", "own:extra", "folded", "folded:", "pinned", "hidden:x", ":Vee"] {
            XCTAssertNil(BarPlacement(encoded: encoded), "\(encoded) must not decode to a placement")
        }
    }

    func testOnlyHiddenLacksBarPresence() {
        XCTAssertTrue(BarPlacement.own.hasBarPresence)
        XCTAssertTrue(BarPlacement.foldedDefault.hasBarPresence)
        XCTAssertFalse(BarPlacement.hidden.hasBarPresence)
    }

    // MARK: - Per-plugin override vs. the default

    func testAPluginWithNoOverrideFollowsTheDefault() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        XCTAssertNil(prefs.placementOverride("a.sh"))
        XCTAssertEqual(prefs.placement("a.sh"), .own)

        prefs.defaultPlacement = .foldedDefault
        XCTAssertEqual(prefs.placement("a.sh"), .foldedDefault, "with no override of its own, a plugin moves with the default")
    }

    func testAnOverrideOutranksTheDefault() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        prefs.setPlacement(BarPlacement.own, id: "pinned.sh")
        prefs.defaultPlacement = .foldedDefault

        XCTAssertEqual(prefs.placement("pinned.sh"), .own, "a plugin the user placed by hand must not move when the default changes")
        XCTAssertEqual(prefs.placement("other.sh"), .foldedDefault, "every other plugin still follows the default")
    }

    func testClearingAnOverrideReturnsThePluginToTheDefault() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        prefs.defaultPlacement = .foldedDefault
        prefs.setPlacement(BarPlacement.hidden, id: "a.sh")
        XCTAssertEqual(prefs.placement("a.sh"), .hidden)

        prefs.setPlacement(nil, id: "a.sh")

        XCTAssertNil(prefs.placementOverride("a.sh"))
        XCTAssertEqual(prefs.placement("a.sh"), .foldedDefault)
    }

    /// The map holds only plugins the user placed by hand, so it stays empty
    /// for the overwhelming majority of installs.
    func testOnlyExplicitlyPlacedPluginsAreEnumerated() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(prefs.placementIDs().isEmpty)
        prefs.setPlacement(BarPlacement.hidden, id: "a.sh")
        prefs.setPlacement(BarPlacement.own, id: "b.sh")

        XCTAssertEqual(prefs.placementIDs(), ["a.sh", "b.sh"])
    }

    // MARK: - Migration from the pre-placement setting

    func testTheLegacyCombineAllSettingSeedsTheDefaultInBothDirections() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        prefs.compactMenuBar = true
        XCTAssertEqual(prefs.placement("a.sh"), .foldedDefault, "an upgrade with combine-all on must leave every plugin folded")

        prefs.compactMenuBar = false
        XCTAssertEqual(prefs.placement("a.sh"), .own, "an upgrade with combine-all off must leave every plugin on its own item")
    }

    // MARK: - Garbage collection

    func testClearAllStateCollectsThePlacement() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        prefs.setPlacement(BarPlacement.hidden, id: "gone.sh")
        prefs.setPlacement(BarPlacement.hidden, id: "stays.sh")

        prefs.clearAllState(id: "gone.sh")

        XCTAssertNil(prefs.placementOverride("gone.sh"), "a plugin whose file is confirmed gone must not leave a placement behind")
        XCTAssertEqual(prefs.placementOverride("stays.sh"), .hidden, "every other plugin's placement is untouched")
    }
}
