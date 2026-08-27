import XCTest
@testable import VeeApp
import VeeMenu
import VeePluginFormat
import VeePreferences
import VeeSearch

/// Bookkeeping for detached plugin windows, exercised through the
/// `attachesWindows: false` seam so no real `NSWindow` (and no live
/// `NSApplication`) is ever constructed — the same discipline
/// `CompactMenuBarControllerTests` follows for status items.
@MainActor
final class DetachedPluginWindowsTests: XCTestCase {
    /// Records what it was asked to do instead of running anything.
    private final class SpyHandler: MenuActionHandling {
        var performed: [MenuItem] = []
        var commits: [(MenuItem, Double)] = []
        func perform(_ item: MenuItem) { performed.append(item) }
        func commitControl(_ item: MenuItem, value: Double) { commits.append((item, value)) }
    }

    /// Pin state is persisted now, so each manager gets its own defaults suite:
    /// a test must neither read the developer's real pin choices nor write into
    /// them.
    private func manager() -> DetachedPluginWindows {
        DetachedPluginWindows(
            attachesWindows: false,
            prefs: AppPreferences(defaults: UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!)
        )
    }

    private func body(_ titles: [String]) -> [MenuNode] {
        titles.map { title in
            var params = LineParams()
            params.href = URL(string: "https://example.com")
            return .item(MenuItem(text: title, params: params))
        }
    }

    // MARK: - One window per plugin

    func testShowTracksThePluginAsOpen() {
        let windows = manager()
        XCTAssertTrue(windows.isEmpty)

        windows.show(pluginName: "sysmon", body: body(["CPU 12%"]), handler: SpyHandler())

        XCTAssertFalse(windows.isEmpty)
        XCTAssertEqual(windows.openPlugins, ["sysmon"])
    }

    func testReopeningTheSamePluginDoesNotStackASecondWindow() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU 12%"]), handler: SpyHandler())
        windows.show(pluginName: "sysmon", body: body(["CPU 15%"]), handler: SpyHandler())

        XCTAssertEqual(windows.openPlugins, ["sysmon"], "re-invoking focuses, never duplicates")
    }

    func testSeveralPluginsAreTrackedIndependently() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())
        windows.show(pluginName: "caffeinate", body: body(["Awake"]), handler: SpyHandler())

        XCTAssertEqual(windows.openPlugins, ["caffeinate", "sysmon"], "sorted, so the menu listing is stable")

        windows.close(pluginName: "sysmon")
        XCTAssertEqual(windows.openPlugins, ["caffeinate"], "closing one leaves the other alone")
    }

    func testClosingEvictsThePluginSoReopeningIsAFreshWindow() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())
        windows.close(pluginName: "sysmon")

        XCTAssertTrue(windows.isEmpty)
        XCTAssertEqual(windows.openPlugins, [])

        windows.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())
        XCTAssertEqual(windows.openPlugins, ["sysmon"])
    }

    func testCloseAllEmptiesTheList() {
        let windows = manager()
        windows.show(pluginName: "a", body: body(["1"]), handler: SpyHandler())
        windows.show(pluginName: "b", body: body(["2"]), handler: SpyHandler())

        windows.closeAll()

        XCTAssertTrue(windows.isEmpty)
    }

    func testFocusingAPluginWithNoWindowIsANoOp() {
        let windows = manager()
        windows.focus(pluginName: "never-opened")
        XCTAssertTrue(windows.isEmpty, "a hotkey bound to a plugin with no window must not conjure one")
    }

    /// `focusAll` is pure effect — ordering real windows — so the seam has
    /// nothing to observe beyond it leaving the tracking alone. What it must not
    /// do is open anything: the bring-all hotkey retrieves windows, it never
    /// conjures them, and a press with nothing open must stay silent.
    func testBringingAllToTheFrontOpensNothing() {
        let windows = manager()
        windows.focusAll()
        XCTAssertTrue(windows.isEmpty)

        windows.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())
        windows.show(pluginName: "caffeinate", body: body(["Awake"]), handler: SpyHandler())

        windows.focusAll()

        XCTAssertEqual(windows.openPlugins, ["caffeinate", "sysmon"], "retrieval never changes what is open")
    }

    // MARK: - Liveness

    func testUpdateReplacesTheWindowsContentWholesale() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU 12%"]), handler: SpyHandler())

        windows.update(pluginName: "sysmon", body: body(["CPU 15%", "Disk 68%"]))

        XCTAssertEqual(
            windows.visibleRowTitles(pluginName: "sysmon"),
            ["CPU 15%", "Disk 68%"],
            "nothing from the previous parse is retained"
        )
    }

    /// A window asks for the `window` surface's tree, on the first open and on
    /// every live update alike — so a row the plugin targeted at the dropdown
    /// alone never reaches one.
    func testWindowsResolveTheirOwnSurface() {
        func targeted() -> [MenuNode] {
            var menuOnly = LineParams()
            menuOnly.href = URL(string: "https://example.com")
            menuOnly.swiftbar.visibleOn = [.menu]
            return body(["Everywhere"]) + [.item(MenuItem(text: "Menu only", params: menuOnly))]
        }
        let windows = manager()
        windows.show(pluginName: "sysmon", body: targeted(), handler: SpyHandler())
        XCTAssertEqual(windows.visibleRowTitles(pluginName: "sysmon"), ["Everywhere"])

        windows.update(pluginName: "sysmon", body: targeted())
        XCTAssertEqual(windows.visibleRowTitles(pluginName: "sysmon"), ["Everywhere"], "and again on refresh")
    }

    func testUpdateForAPluginWithNoWindowIsHarmless() {
        let windows = manager()
        windows.update(pluginName: "not-open", body: body(["x"]))
        XCTAssertTrue(windows.isEmpty)
    }

    func testMarkStaleThenRecovery() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU 12%"]), handler: SpyHandler())
        XCTAssertFalse(windows.isStale(pluginName: "sysmon"))

        windows.markStale(pluginName: "sysmon")
        XCTAssertTrue(windows.isStale(pluginName: "sysmon"))

        XCTAssertEqual(
            windows.visibleRowTitles(pluginName: "sysmon"),
            ["CPU 12%"],
            "a stale window keeps showing its last output rather than blanking"
        )

        windows.update(pluginName: "sysmon", body: body(["CPU 9%"]))
        XCTAssertFalse(windows.isStale(pluginName: "sysmon"), "fresh output clears the flag")
    }

    func testMarkFreshClearsStaleWithoutChangingContent() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU 12%"]), handler: SpyHandler())
        windows.markStale(pluginName: "sysmon")

        windows.markFresh(pluginName: "sysmon")

        XCTAssertFalse(windows.isStale(pluginName: "sysmon"))
        XCTAssertEqual(windows.visibleRowTitles(pluginName: "sysmon"), ["CPU 12%"])
    }

    // MARK: - Level and collection behavior move as a pair

    func testPinnedResolvesToFloatingThatSurvivesSpacesAndFullScreen() {
        let settings = DetachedWindowPinning.settings(pinned: true)

        XCTAssertEqual(settings.level, .floating)
        XCTAssertTrue(
            settings.behavior.contains(.fullScreenAuxiliary),
            "a floating window that vanishes behind a full-screen app fails the case floating exists for"
        )
        XCTAssertTrue(
            settings.behavior.contains(.canJoinAllSpaces),
            "and it must follow the user across Spaces rather than stay on the one it was born on"
        )
    }

    func testUnpinnedResolvesToAnOrdinaryManagedWindow() {
        let settings = DetachedWindowPinning.settings(pinned: false)

        XCTAssertEqual(settings.level, .normal)
        XCTAssertEqual(
            settings.behavior, .managed,
            "Mission Control is the only system retrieval path for an accessory app's window, and it needs .managed"
        )
    }

    func testTheTwoHalvesAreNeverResolvedIndependently() {
        // The pairing is the invariant: there is no combination of level and
        // behavior other than these two, because a `.floating` window left on
        // `.managed` is the exact bug this type exists to make unrepresentable.
        for pinned in [true, false] {
            let settings = DetachedWindowPinning.settings(pinned: pinned)
            XCTAssertEqual(settings.level == .floating, settings.behavior.contains(.fullScreenAuxiliary))
            XCTAssertEqual(settings.level == .normal, settings.behavior == .managed)
        }
    }

    // MARK: - Pinning

    func testNewWindowsFloatByDefault() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())

        XCTAssertTrue(windows.isPinned(pluginName: "sysmon"))
    }

    func testPinningAWindowResolvesTheMatchingPair() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())

        XCTAssertEqual(windows.pinning(pluginName: "sysmon").level, .floating)

        windows.setPinned(false, pluginName: "sysmon")

        XCTAssertEqual(windows.pinning(pluginName: "sysmon").level, .normal)
        XCTAssertEqual(windows.pinning(pluginName: "sysmon").behavior, .managed)
    }

    func testPinStateIsRememberedAcrossCloseAndReopenWithinTheSession() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())
        windows.setPinned(false, pluginName: "sysmon")
        windows.close(pluginName: "sysmon")

        windows.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())

        XCTAssertFalse(windows.isPinned(pluginName: "sysmon"), "reopens the way it was left")
    }

    /// The pin outlives the session, not just the window: a manager built over
    /// the same defaults — the shape a relaunch has — opens the plugin the way
    /// the user last left it, with no session dictionary carried over.
    func testPinStateSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!
        let firstLaunch = DetachedPluginWindows(attachesWindows: false, prefs: AppPreferences(defaults: defaults))
        firstLaunch.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())
        firstLaunch.setPinned(false, pluginName: "sysmon")
        firstLaunch.close(pluginName: "sysmon")

        let relaunched = DetachedPluginWindows(attachesWindows: false, prefs: AppPreferences(defaults: defaults))
        relaunched.show(pluginName: "sysmon", body: body(["CPU"]), handler: SpyHandler())

        XCTAssertFalse(relaunched.isPinned(pluginName: "sysmon"))
        XCTAssertEqual(relaunched.pinning(pluginName: "sysmon").level, .normal)
    }

    func testPinPreferenceIsPerPlugin() {
        let windows = manager()
        windows.show(pluginName: "a", body: body(["1"]), handler: SpyHandler())
        windows.show(pluginName: "b", body: body(["2"]), handler: SpyHandler())

        windows.setPinned(false, pluginName: "a")

        XCTAssertFalse(windows.isPinned(pluginName: "a"))
        XCTAssertTrue(windows.isPinned(pluginName: "b"))
    }
}
