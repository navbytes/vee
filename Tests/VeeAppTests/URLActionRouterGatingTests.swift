import XCTest
@testable import VeeApp

/// D8: `enableplugin`/`disableplugin`/`toggleplugin` (enabling makes a plugin
/// RUN; toggling can land on either — same bypass as both, not a separate
/// risk) and a `notify` carrying a click-through `href` (phishing bait a
/// spoofed "Vee" notification can carry) must not silently reach the app's
/// existing dispatch — see `URLActionRouter.routeGated`. `parse(_:)` itself
/// is untouched by this fix (see `URLActionRouterTests.swift`); these tests
/// cover the new gated entry point only.
///
/// `confirm` is a process-global test seam standing in for a real `NSAlert`
/// (which a headless test run must never pop) — every test saves/restores it
/// so this file can't leak a stub into any other test. `@MainActor` because
/// `routeGated` now is (it gates a real `NSAlert` in production).
@MainActor
final class URLActionRouterGatingTests: XCTestCase {
    private var savedConfirm: ((String, String) -> Bool)!

    override func setUp() {
        super.setUp()
        savedConfirm = URLActionRouter.confirm
    }

    override func tearDown() {
        URLActionRouter.confirm = savedConfirm
        super.tearDown()
    }

    private func route(_ string: String) -> URLAction {
        URLActionRouter.routeGated(URL(string: string)!)
    }

    func testEnablePluginProceedsOnlyWhenConfirmed() {
        URLActionRouter.confirm = { _, _ in true }
        XCTAssertEqual(route("swiftbar://enableplugin?name=x"), .enablePlugin(name: "x"))

        URLActionRouter.confirm = { _, _ in false }
        XCTAssertEqual(route("swiftbar://enableplugin?name=x"), .unknown, "enabling makes a plugin run — a declined confirmation must not reach the existing enable path")
    }

    func testDisablePluginProceedsOnlyWhenConfirmed() {
        URLActionRouter.confirm = { _, _ in true }
        XCTAssertEqual(route("swiftbar://disableplugin?name=x"), .disablePlugin(name: "x"))

        URLActionRouter.confirm = { _, _ in false }
        XCTAssertEqual(route("swiftbar://disableplugin?name=x"), .unknown, "a declined confirmation must not reach the existing disable path")
    }

    func testTogglePluginGatedTheSameWayAsDisable() {
        URLActionRouter.confirm = { _, _ in false }
        XCTAssertEqual(route("swiftbar://toggleplugin?name=x"), .unknown, "toggle can silently disable too — same bypass as disableplugin")

        URLActionRouter.confirm = { _, _ in true }
        XCTAssertEqual(route("swiftbar://toggleplugin?name=x"), .togglePlugin(name: "x"))
    }

    func testHrefBearingNotifyProceedsOnlyWhenConfirmed() {
        URLActionRouter.confirm = { _, _ in false }
        XCTAssertEqual(route("swiftbar://notify?body=x&href=https://example.com"), .unknown)

        URLActionRouter.confirm = { _, _ in true }
        XCTAssertEqual(
            route("swiftbar://notify?body=x&href=https://example.com"),
            .notify(title: "", subtitle: "", body: "x", href: URL(string: "https://example.com"), pluginID: nil)
        )
    }

    func testHrefLessNotifyNeedsNoConfirmation() {
        URLActionRouter.confirm = { _, _ in
            XCTFail("an href-less notify must not prompt")
            return false
        }
        XCTAssertEqual(route("swiftbar://notify?body=Only"), .notify(title: "", subtitle: "", body: "Only", href: nil, pluginID: nil))
    }

    func testRefreshNeedsNoConfirmation() {
        URLActionRouter.confirm = { _, _ in
            XCTFail("refresh must not prompt")
            return false
        }
        XCTAssertEqual(route("swiftbar://refreshallplugins"), .refreshAll)
        XCTAssertEqual(route("swiftbar://refreshplugin?name=x"), .refreshPlugin(name: "x"))
    }

    /// `addplugin` already has its own trust/capability gate downstream in
    /// `AppController.confirmInstall` — this router must not double-prompt.
    func testAddPluginPassesThroughUngated() {
        URLActionRouter.confirm = { _, _ in
            XCTFail("addplugin has its own gate in AppController; this router must not prompt")
            return false
        }
        XCTAssertEqual(
            route("swiftbar://addplugin?src=https://example.com/x.5m.sh"),
            .addPlugin(src: URL(string: "https://example.com/x.5m.sh")!)
        )
    }

    func testNeedsConfirmationCoversExactlyTheGatedActions() {
        XCTAssertTrue(URLActionRouter.needsConfirmation(.enablePlugin(name: "x")))
        XCTAssertTrue(URLActionRouter.needsConfirmation(.disablePlugin(name: "x")))
        XCTAssertTrue(URLActionRouter.needsConfirmation(.togglePlugin(name: "x")))
        XCTAssertTrue(URLActionRouter.needsConfirmation(.notify(title: "", subtitle: "", body: "", href: URL(string: "https://example.com"), pluginID: nil)))

        XCTAssertFalse(URLActionRouter.needsConfirmation(.refreshAll))
        XCTAssertFalse(URLActionRouter.needsConfirmation(.refreshPlugin(name: "x")))
        XCTAssertFalse(URLActionRouter.needsConfirmation(.addPlugin(src: URL(string: "https://example.com")!)))
        XCTAssertFalse(URLActionRouter.needsConfirmation(.setEphemeralPlugin(name: "x", content: "y", exitAfter: nil)))
        XCTAssertFalse(URLActionRouter.needsConfirmation(.notify(title: "", subtitle: "", body: "", href: nil, pluginID: nil)))
        XCTAssertFalse(URLActionRouter.needsConfirmation(.unknown))
    }
}
