import XCTest
@testable import VeeApp
import VeeMenu
import VeePluginFormat
import VeePreferences

/// Compact mode (issue #45 — menu-bar crowding): an opt-in preference that
/// collapses every enabled plugin's status item into a submenu of ONE shared
/// "Vee" status item.
///
/// These tests deliberately never construct a real `NSStatusItem` (and so
/// never touch `NSApplication.shared`, even indirectly): doing so from a unit
/// test rebinds the MainActor executor process-wide and starves other suites
/// under CI load — see `WidgetActionRefreshTests`'s note on the same hazard.
/// `CompactMenuBarController(attachesStatusItem: false)` short-circuits before
/// ever reaching `NSStatusBar`, and every `StatusItemController` below is
/// constructed with compact mode already forced on via injected
/// `AppPreferences`, so its `NSStatusBar.system.statusItem(...)` branch (the
/// pre-existing, unchanged standalone path) never runs either.
@MainActor
final class CompactMenuBarControllerTests: XCTestCase {
    private final class DummyHandler: MenuActionHandling {
        func perform(_ item: MenuItem) {}
    }

    /// An `AppPreferences` backed by an ephemeral, uniquely-named suite (never
    /// the real `UserDefaults.standard`) with compact mode already on.
    private func makeCompactPrefs() -> AppPreferences {
        let defaults = UserDefaults(suiteName: "vee-app-tests-\(UUID().uuidString)")!
        let prefs = AppPreferences(defaults: defaults)
        prefs.compactMenuBar = true
        return prefs
    }

    private func makeController(prefs: AppPreferences, compact: CompactMenuBarController, name: String = "Plugin") -> StatusItemController {
        StatusItemController(
            pluginName: name,
            handler: DummyHandler(),
            onRefresh: {},
            prefs: prefs,
            compactController: compact
        )
    }

    private func output(title: String, itemTitle: String = "Row") -> ParsedOutput {
        ParsedOutput(
            titleLines: [TitleLine(text: title)],
            body: [.item(MenuItem(text: itemTitle))]
        )
    }

    // MARK: - CompactMenuBarController row bookkeeping (model-level)

    func testAddEntryNeverTouchesStatusBarWhenDetached() {
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let item = compact.addEntry()
        XCTAssertEqual(compact.menu.items.count, 1)
        XCTAssertIdentical(compact.menu.items.first, item)
    }

    func testRemoveEntryTearsDownItsOwnRowOnly() {
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let a = compact.addEntry()
        let b = compact.addEntry()
        XCTAssertEqual(compact.menu.items.count, 2)

        compact.removeEntry(a)

        XCTAssertEqual(compact.menu.items.count, 1, "tear down: removing one row must not disturb the other")
        XCTAssertIdentical(compact.menu.items.first, b)
    }

    // MARK: - StatusItemController registers/updates/removes its row

    func testControllerRegistersExactlyOneRowInCompactMode() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let controller = makeController(prefs: prefs, compact: compact)
        withExtendedLifetime(controller) {
            XCTAssertEqual(compact.menu.items.count, 1, "compact mode must add exactly one row per plugin, never a standalone status item")
        }
    }

    func testRenderUpdatesRowTitleAndReusesMenuConstruction() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let controller = makeController(prefs: prefs, compact: compact)

        controller.render(output(title: "42%", itemTitle: "Detail"))

        let row = compact.menu.items[0]
        XCTAssertEqual(row.attributedTitle?.string, "42%", "the submenu title must track the plugin's current menu-bar title")
        XCTAssertEqual(row.submenu?.items.first?.title, "Detail", "the submenu content must reuse the plugin's own dropdown construction, not a rebuilt copy")
    }

    func testRenderErrorUpdatesRowWithFallbackTitle() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let controller = makeController(prefs: prefs, compact: compact, name: "Flaky")

        controller.renderError("boom")

        let row = compact.menu.items[0]
        XCTAssertEqual(row.attributedTitle?.string, "Flaky", "an error surface has no title text either, so it falls back the same way a good render does")
        XCTAssertEqual(row.submenu?.items.first?.title, "boom")
    }

    /// A plugin whose title is blank (icon-only — fine in the real menu bar,
    /// where the icon alone is enough) would otherwise show an unlabeled row
    /// once several plugins are stacked into one shared menu.
    func testBlankTitleFallsBackToPluginNameInCompactRow() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let controller = makeController(prefs: prefs, compact: compact, name: "Weather")

        var params = LineParams()
        params.swiftbar.sfimage = "cloud.fill"
        controller.render(ParsedOutput(titleLines: [TitleLine(text: "", params: params)], body: []))

        XCTAssertEqual(compact.menu.items[0].attributedTitle?.string, "Weather")
    }

    /// The critical "must not rebuild the whole menu while it might be open"
    /// guarantee: refreshing one plugin must not touch a sibling's row.
    func testUpdatingOnePluginDoesNotDisturbAnothersRow() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let a = makeController(prefs: prefs, compact: compact, name: "A")
        let b = makeController(prefs: prefs, compact: compact, name: "B")
        b.render(output(title: "B-title"))
        let bRowBeforeRefresh = compact.menu.items[1]

        a.render(output(title: "A-title"))

        XCTAssertIdentical(compact.menu.items[1], bRowBeforeRefresh, "B's row must be the same NSMenuItem instance, not recreated")
        XCTAssertEqual(compact.menu.items[1].attributedTitle?.string, "B-title", "B's own content must be unaffected by A refreshing")
        XCTAssertEqual(compact.menu.items[0].attributedTitle?.string, "A-title")
    }

    func testRemoveTearsDownItsRowAndTheSharedItemWhenLast() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let controller = makeController(prefs: prefs, compact: compact)
        XCTAssertEqual(compact.menu.items.count, 1)

        controller.remove()

        XCTAssertEqual(compact.menu.items.count, 0, "remove() must tear down this plugin's row")
    }

    // MARK: - Lifecycle churn (disable/delete one plugin, enable another)

    /// Disabling/deleting a plugin (`remove()`, as `PluginCoordinator.stop()`
    /// calls) from the *middle* of several rows, then a different plugin
    /// enabling, must leave no orphan row behind and must not double-count —
    /// the existing add/remove tests above never combine more than two rows
    /// or a "remove-then-add" sequence.
    func testDisablingAPluginThenEnablingAnotherLeavesNoOrphanRow() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let a = makeController(prefs: prefs, compact: compact, name: "A")
        let b = makeController(prefs: prefs, compact: compact, name: "B")
        let c = makeController(prefs: prefs, compact: compact, name: "C")
        a.render(output(title: "A-title"))
        b.render(output(title: "B-title"))
        c.render(output(title: "C-title"))
        XCTAssertEqual(compact.menu.items.count, 3)

        b.remove() // simulates disabling/deleting the middle plugin

        XCTAssertEqual(compact.menu.items.count, 2, "the disabled plugin's row must be gone, not orphaned")
        XCTAssertEqual(compact.menu.items.map { $0.attributedTitle?.string }, ["A-title", "C-title"])

        let d = makeController(prefs: prefs, compact: compact, name: "D") // simulates enabling a new plugin
        d.render(output(title: "D-title"))

        XCTAssertEqual(compact.menu.items.count, 3, "no double-add: exactly one new row for the newly-enabled plugin")
        XCTAssertEqual(
            compact.menu.items.map { $0.attributedTitle?.string },
            ["A-title", "C-title", "D-title"],
            "no orphan row left over from B, and no duplicate row for D"
        )
        withExtendedLifetime((a, c, d)) {}
    }

    // MARK: - Mode-switch notification churn

    /// A "notification storm" where `compactMenuBarDidChangeNotification` fires
    /// repeatedly without the preference actually changing (e.g. redundant sets
    /// from rapid, no-op UI churn) must be a no-op every time: `reconcileMode()`
    /// guards on the live value actually differing from its current surface.
    /// Only this direction (already-compact, notified again while still compact)
    /// is safely unit-testable — the actual compact⇄standalone flip always
    /// creates/removes a real `NSStatusItem` (see the file-level note above).
    func testRedundantModeChangeNotificationIsIdempotent() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let controller = makeController(prefs: prefs, compact: compact)
        let rowBefore = compact.menu.items[0]

        for _ in 0..<5 {
            NotificationCenter.default.post(name: AppPreferences.compactMenuBarDidChangeNotification, object: nil)
        }

        // Notification observers registered with `queue: .main` are dispatched
        // onto the main (serial) queue rather than run synchronously inside
        // `post()`; enqueue a marker after the storm and wait for it so every
        // `reconcileMode()` call above has actually run before asserting.
        let drained = expectation(description: "main queue drained past the notification storm")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)

        XCTAssertEqual(compact.menu.items.count, 1, "a same-value notification storm must never add a duplicate row")
        XCTAssertIdentical(compact.menu.items[0], rowBefore, "the row must be the same instance, not rebuilt")
        withExtendedLifetime(controller) {}
    }
}
