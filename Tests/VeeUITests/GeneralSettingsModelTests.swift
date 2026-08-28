import XCTest
import VeePluginFormat
import VeePreferences
@testable import VeeUI

/// The Settings toggle that sets the app-wide *default* menu-bar placement
/// (issue #45 — menu-bar crowding), wired the same way `launchAtLogin` already
/// is — see `GeneralSettingsView.swift`.
@MainActor
final class GeneralSettingsModelTests: XCTestCase {
    /// An `AppPreferences` backed by an ephemeral, uniquely-named suite so
    /// these tests never touch the real user's preferences.
    private func makePrefs() -> (prefs: AppPreferences, suiteName: String) {
        let suiteName = "vee-ui-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AppPreferences(defaults: defaults), suiteName)
    }

    // MARK: - AppPreferences.defaultPlacement round-trip

    func testDefaultPlacementDefaultsToItsOwnItem() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(prefs.defaultPlacement, .own, "one item per plugin is the shipped default — zero behavior change until a user opts in")
    }

    func testDefaultPlacementRoundTrips() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        prefs.defaultPlacement = .foldedDefault
        XCTAssertEqual(prefs.defaultPlacement, .foldedDefault)
        prefs.defaultPlacement = .own
        XCTAssertEqual(prefs.defaultPlacement, .own)
    }

    /// The migration that must not move anyone's plugins: an install that only
    /// ever set the pre-placement `compactMenuBar` boolean resolves to the
    /// matching default, in both directions.
    func testDefaultPlacementMigratesFromTheLegacyCompactMenuBarSetting() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        prefs.compactMenuBar = true
        XCTAssertEqual(prefs.defaultPlacement, .foldedDefault, "an install with combine-all on must keep every plugin folded")

        prefs.compactMenuBar = false
        XCTAssertEqual(prefs.defaultPlacement, .own, "an install with combine-all off must keep every plugin on its own item")
    }

    /// Once a default is stored it is authoritative: a stale legacy value left
    /// in the domain (a downgrade, a restored backup, synced preferences) must
    /// not be able to move plugins back.
    func testStoredDefaultOutranksTheLegacySetting() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        prefs.defaultPlacement = .own
        prefs.compactMenuBar = true

        XCTAssertEqual(prefs.defaultPlacement, .own, "the stored default wins over the legacy boolean")
    }

    /// Every already-running `StatusItemController` learns about a live change
    /// through this notification (see `reconcilePlacement()`).
    func testDefaultPlacementChangePostsNotification() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let posted = expectation(description: "placement change notification")
        let token = NotificationCenter.default.addObserver(
            forName: AppPreferences.barPlacementDidChangeNotification, object: nil, queue: .main
        ) { _ in posted.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        prefs.defaultPlacement = .foldedDefault

        wait(for: [posted], timeout: 2)
    }

    // MARK: - GeneralSettingsModel wiring

    func testModelStartsFromInjectedValueAndForwardsWrites() {
        var written: Bool?
        let model = GeneralSettingsModel(
            currentDirectory: "/tmp",
            launchAtLogin: false,
            onLaunchAtLogin: { _ in },
            onChooseFolder: {},
            onOpenFolder: {},
            onRefreshAll: {},
            foldPluginsByDefault: true,
            onFoldPluginsByDefault: { written = $0 }
        )
        XCTAssertTrue(model.foldPluginsByDefault, "the model must start from the injected current value, not read AppPreferences.shared itself")

        // Mirrors what the Settings toggle's Binding does: write the model's
        // published value, then forward it through the callback.
        model.foldPluginsByDefault = false
        model.onFoldPluginsByDefault(false)

        XCTAssertEqual(written, false, "flipping the toggle must forward the new value through onFoldPluginsByDefault")
    }
}
