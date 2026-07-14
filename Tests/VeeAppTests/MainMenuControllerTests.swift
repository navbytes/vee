import XCTest
import AppKit
@testable import VeeApp

/// `MainMenuController` — the always-present "Vee" app-controls item.
///
/// Issue #71 follow-up ("one icon total" in compact mode): while
/// `AppPreferences.compactMenuBar` is on, this controller's own item is
/// hidden and its rows fold into `CompactMenuBarController`'s shared icon as
/// a footer instead (`AppController.applyCompactMode`,
/// `CompactMenuBarController.installFooter`) — see
/// `CompactMenuBarControllerTests`'s "App-controls footer" section for that
/// side.
///
/// These tests exercise this controller at the model level via
/// `attachesStatusItem: false` — the same seam `CompactMenuBarControllerTests`
/// uses to never touch `NSApplication.shared`/`NSStatusBar` (unsafe from a
/// unit test: it rebinds the MainActor executor process-wide and starves
/// other suites under CI load).
@MainActor
final class MainMenuControllerTests: XCTestCase {
    private struct Recorder {
        var manager = 0, discover = 0, preferences = 0, refreshAll = 0, searchAll = 0, openFolder = 0
    }

    private final class Box {
        var recorder = Recorder()
    }

    private func makeController(_ box: Box = Box()) -> MainMenuController {
        MainMenuController(
            onManager: { box.recorder.manager += 1 },
            onDiscover: { box.recorder.discover += 1 },
            onPreferences: { box.recorder.preferences += 1 },
            onRefreshAll: { box.recorder.refreshAll += 1 },
            onSearchAll: { box.recorder.searchAll += 1 },
            onOpenFolder: { box.recorder.openFolder += 1 },
            attachesStatusItem: false
        )
    }

    /// Invokes an `NSMenuItem`'s action the same way AppKit would on a click —
    /// `perform(_:with:)` runs the target/action pair directly via the
    /// Objective-C runtime, with no `NSApplication`/event-loop involvement, so
    /// it's safe to call from a unit test.
    private func fire(_ item: NSMenuItem?, file: StaticString = #filePath, line: UInt = #line) {
        guard let item, let action = item.action, let target = item.target as? NSObject else {
            XCTFail("row has no target/action", file: file, line: line)
            return
        }
        _ = target.perform(action, with: item)
    }

    // MARK: - Visibility (hidden while compact mode folds this under the shared icon)

    func testDefaultsVisible() {
        XCTAssertTrue(makeController().isVisible, "the app item must be visible by default — zero behavior change until compact mode is on")
    }

    func testSetVisibleTracksTheRequestWithNoRealStatusItem() {
        let controller = makeController()

        controller.setVisible(false)
        XCTAssertFalse(controller.isVisible)

        controller.setVisible(true)
        XCTAssertTrue(controller.isVisible)
    }

    // MARK: - buildAppItems (the seam CompactMenuBarController's footer reuses)

    func testOwnMenuContainsTheExpectedRowsInOrder() {
        XCTAssertEqual(
            makeController().menu.items.map(\.title),
            ["Preferences…", "Plugin Manager…", "Discover Plugins…", "Refresh All Plugins", "Search All Plugins…", "", "Launch Vee at Login", "Open Plugins Folder…", "", "Quit Vee"]
        )
    }

    /// `buildAppItems` must be reusable against ANY menu, not just the one
    /// built in `init` — the exact seam `CompactMenuBarController.installFooter`
    /// depends on to avoid duplicating this list.
    func testBuildAppItemsIsReusableAgainstASecondMenuWithIdenticalContent() {
        let controller = makeController()
        let footerMenu = NSMenu()

        let footerLogin = MainMenuController.buildAppItems(in: footerMenu, target: controller)

        XCTAssertEqual(footerMenu.items.map(\.title), controller.menu.items.map(\.title), "titles must be identical between the standalone menu and a second built menu")
        XCTAssertEqual(footerMenu.items.map(\.keyEquivalent), controller.menu.items.map(\.keyEquivalent), "key equivalents must be identical too")
        XCTAssertNotIdentical(footerLogin, controller.menu.items.first { $0.title == "Launch Vee at Login" }, "a second build must create its OWN item instances — an NSMenuItem can only belong to one menu at a time")
    }

    // MARK: - Callbacks fire (model-level — no NSApplication/event loop involved)

    /// `toggleLogin` (real `SMAppService` side effects) and `quit`
    /// (`NSApp.terminate`, which would kill the test process) are
    /// deliberately never fired here — only the plain callback-forwarding
    /// rows are exercised.
    func testEachRowsCallbackFiresThroughTargetAction() {
        let box = Box()
        let controller = makeController(box) // kept alive: NSMenuItem.target is weak, so an unretained controller would leave every row's target nil
        let items = controller.menu.items

        fire(items.first { $0.title == "Preferences…" })
        fire(items.first { $0.title == "Plugin Manager…" })
        fire(items.first { $0.title == "Discover Plugins…" })
        fire(items.first { $0.title == "Refresh All Plugins" })
        fire(items.first { $0.title == "Search All Plugins…" })
        fire(items.first { $0.title == "Open Plugins Folder…" })

        XCTAssertEqual(box.recorder.preferences, 1)
        XCTAssertEqual(box.recorder.manager, 1)
        XCTAssertEqual(box.recorder.discover, 1)
        XCTAssertEqual(box.recorder.refreshAll, 1)
        XCTAssertEqual(box.recorder.searchAll, 1)
        XCTAssertEqual(box.recorder.openFolder, 1)
    }

    /// The same callbacks must fire identically when built into a SEPARATE
    /// menu (the footer's shape), not just this controller's own menu.
    func testCallbacksFireIdenticallyWhenBuiltIntoASeparateFooterMenu() {
        let box = Box()
        let controller = makeController(box)
        let footerMenu = NSMenu()
        MainMenuController.buildAppItems(in: footerMenu, target: controller)

        fire(footerMenu.items.first { $0.title == "Refresh All Plugins" })
        fire(footerMenu.items.first { $0.title == "Discover Plugins…" })

        XCTAssertEqual(box.recorder.refreshAll, 1)
        XCTAssertEqual(box.recorder.discover, 1)
    }
}
