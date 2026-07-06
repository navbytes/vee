import XCTest
@testable import VeeMenu
import VeePluginFormat

/// Regression guard for the "menu clicks are silent no-ops" bug: `MenuActionTarget`
/// must keep its handler alive. `NSMenuItem.target` is weak and the app creates
/// the handler (`AppActionDispatcher`) inline, so if the target only referenced
/// it weakly the handler would deallocate immediately and every click would call
/// a nil handler.
@MainActor
final class MenuActionTargetRetentionTests: XCTestCase {
    private final class Probe: MenuActionHandling {
        func perform(_ item: MenuItem) {}
    }

    func testTargetRetainsHandler() {
        weak var weakHandler: Probe?
        let target: MenuActionTarget
        do {
            let probe = Probe()
            weakHandler = probe
            target = MenuActionTarget(handler: probe)
            // `probe`'s only strong reference goes out of scope here.
        }
        withExtendedLifetime(target) {
            XCTAssertNotNil(
                weakHandler,
                "MenuActionTarget must retain its handler, else NSStatusItem menu clicks hit a nil handler and silently no-op")
        }
    }
}
