import XCTest
import VeePluginFormat
import VeePreferences
@testable import VeeUI

/// Compact mode (issue #45): the Settings toggle backed by `AppPreferences.
/// compactMenuBar`, wired the same way `launchAtLogin` already is — see
/// `GeneralSettingsView.swift`.
@MainActor
final class GeneralSettingsModelTests: XCTestCase {
    /// An `AppPreferences` backed by an ephemeral, uniquely-named suite so
    /// these tests never touch the real user's preferences.
    private func makePrefs() -> (prefs: AppPreferences, suiteName: String) {
        let suiteName = "vee-ui-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AppPreferences(defaults: defaults), suiteName)
    }

    // MARK: - AppPreferences.compactMenuBar round-trip

    func testCompactMenuBarDefaultsFalse() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        XCTAssertFalse(prefs.compactMenuBar, "compact mode must default off — zero behavior change until a user opts in")
    }

    func testCompactMenuBarRoundTrips() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        prefs.compactMenuBar = true
        XCTAssertTrue(prefs.compactMenuBar)
        prefs.compactMenuBar = false
        XCTAssertFalse(prefs.compactMenuBar)
    }

    /// Every already-running `StatusItemController` learns about a live
    /// toggle through this notification (see `reconcileMode()`).
    func testCompactMenuBarChangePostsNotification() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let posted = expectation(description: "compact mode change notification")
        let token = NotificationCenter.default.addObserver(
            forName: AppPreferences.compactMenuBarDidChangeNotification, object: nil, queue: .main
        ) { _ in posted.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        prefs.compactMenuBar = true

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
            compactMenuBar: true,
            onCompactMenuBar: { written = $0 }
        )
        XCTAssertTrue(model.compactMenuBar, "the model must start from the injected current value, not read AppPreferences.shared itself")

        // Mirrors what the Settings toggle's Binding does: write the model's
        // published value, then forward it through the callback.
        model.compactMenuBar = false
        model.onCompactMenuBar(false)

        XCTAssertEqual(written, false, "flipping the toggle must forward the new value through onCompactMenuBar")
    }

    // MARK: - AppPreferences.searchAllHotkey* round-trip (cross-plugin search)

    func testSearchAllHotkeyDefaultsOffWithNoCombo() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        XCTAssertFalse(prefs.searchAllHotkeyEnabled, "no default combo may ever be squatted — off until the user opts in")
        XCTAssertNil(prefs.searchAllHotkeyCombo)
    }

    func testSearchAllHotkeyEnabledRoundTrips() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        prefs.searchAllHotkeyEnabled = true
        XCTAssertTrue(prefs.searchAllHotkeyEnabled)
        prefs.searchAllHotkeyEnabled = false
        XCTAssertFalse(prefs.searchAllHotkeyEnabled)
    }

    func testSearchAllHotkeyComboRoundTrips() {
        let (prefs, suiteName) = makePrefs()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        prefs.searchAllHotkeyCombo = "cmd+shift+/"
        XCTAssertEqual(prefs.searchAllHotkeyCombo, "cmd+shift+/")
        prefs.searchAllHotkeyCombo = nil
        XCTAssertNil(prefs.searchAllHotkeyCombo)
    }

    // MARK: - GeneralSettingsModel wiring (cross-plugin search hotkey)

    func testModelStartsFromInjectedSearchAllHotkeyValuesAndForwardsWrites() {
        var applied: (enabled: Bool, combo: String)?
        let model = GeneralSettingsModel(
            currentDirectory: "/tmp",
            launchAtLogin: false,
            onLaunchAtLogin: { _ in },
            onChooseFolder: {},
            onOpenFolder: {},
            onRefreshAll: {},
            searchAllHotkeyEnabled: true,
            searchAllHotkeyCombo: "cmd+shift+/",
            searchAllHotkeyStatus: .active("⌘⇧/"),
            onApplySearchAllHotkey: { enabled, combo in
                applied = (enabled, combo)
                return .unavailable("⌘⇧/")
            }
        )
        XCTAssertTrue(model.searchAllHotkeyEnabled, "must start from the injected value, not read AppPreferences.shared itself")
        XCTAssertEqual(model.searchAllHotkeyCombo, "cmd+shift+/")
        XCTAssertEqual(model.searchAllHotkeyStatus, .active("⌘⇧/"))

        // Mirrors what the toggle/text field bindings do: mutate the published
        // value, then trigger the apply that round-trips through the app layer.
        model.searchAllHotkeyEnabled = false
        model.searchAllHotkeyCombo = "cmd+shift+k"
        model.applySearchAllHotkey()

        XCTAssertEqual(applied?.enabled, false)
        XCTAssertEqual(applied?.combo, "cmd+shift+k")
        XCTAssertEqual(model.searchAllHotkeyStatus, .unavailable("⌘⇧/"), "the model must reflect whatever status onApplySearchAllHotkey returns")
    }
}
