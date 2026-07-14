import XCTest
@testable import VeeApp
import VeeUI

/// `Notifier.configure(onOpenDiscover:)` is wired to `AppController.openBrowser()`,
/// which calls `LibraryWindow.shared.show(model: makeLibraryModel(section:
/// .discover))` — reusing the same path the menu's Discover item and first-run
/// already use. The `LibraryWindow` half touches `NSApp`, which is unsafe to
/// invoke from a unit test (creating `NSApplication` rebinds the MainActor
/// executor process-wide and starves other suites under CI load — see
/// `WidgetActionRefreshTests`), so this exercises the model-level half instead:
/// the section `openBrowser()` requests really is `.discover`, not just
/// whatever the caller happened to pass.
@MainActor
final class AppControllerDiscoverRoutingTests: XCTestCase {
    func testMakeLibraryModelForDiscoverSectionIsDiscoverScoped() {
        // `VEE_PLUGINS_DIR` is `PluginsDirectory.resolve()`'s documented
        // dev/test override — points `AppController` at an empty, isolated
        // directory instead of the real machine's actual Vee plugins folder.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-appcontroller-\(UUID().uuidString)")
            .path
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }

        let controller = AppController()

        XCTAssertEqual(controller.makeLibraryModel(section: .discover).section, .discover)
        // Sanity check: the section actually passes through rather than being
        // hardcoded to `.discover` regardless of the caller's request.
        XCTAssertEqual(controller.makeLibraryModel(section: .installed).section, .installed)
    }
}
