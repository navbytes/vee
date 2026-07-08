import XCTest
@testable import VeeApp

/// Regression coverage for the search-panel focus bug: selecting a row used to
/// leave Vee itself frontmost (since presenting the panel force-activates Vee
/// so its search field can become key), so a plugin's simulated ⌘V — e.g. the
/// clipboard plugin's autopaste — landed in Vee instead of the app the user
/// invoked the panel from.
final class FrontmostAppRestorerTests: XCTestCase {
    func testRestoresTheCapturedAppExactlyOnce() {
        var restorer = FrontmostAppRestorer()
        let app = NSRunningApplication.current // a real instance obtainable in-process
        restorer.capture(app)

        var activated: [NSRunningApplication] = []
        restorer.restore { activated.append($0) }

        XCTAssertEqual(activated, [app])
    }

    func testRestoreIsANoOpWhenNothingWasCaptured() {
        var restorer = FrontmostAppRestorer()

        var activatorCalled = false
        restorer.restore { _ in activatorCalled = true }

        XCTAssertFalse(activatorCalled)
    }

    func testRestoringTwiceOnlyActivatesOnce() {
        // Covers dismiss() being called twice in a row (e.g. a row activation,
        // which dismisses then runs the action, followed by some other path
        // also calling dismiss) — the second call must not re-fire activation.
        var restorer = FrontmostAppRestorer()
        restorer.capture(NSRunningApplication.current)

        var activationCount = 0
        restorer.restore { _ in activationCount += 1 }
        restorer.restore { _ in activationCount += 1 }

        XCTAssertEqual(activationCount, 1)
    }

    func testCapturingReplacesAnyPriorUnrestoredApp() {
        var restorer = FrontmostAppRestorer()
        restorer.capture(NSRunningApplication.current)
        restorer.capture(nil) // e.g. present() called again before a dismiss

        var activatorCalled = false
        restorer.restore { _ in activatorCalled = true }

        XCTAssertFalse(activatorCalled)
    }
}
