import XCTest
@testable import VeeApp

final class NotificationRoutingTests: XCTestCase {
    // MARK: - Suppressor

    func testSuppressorSilencesPerPlugin() {
        var suppressor = NotificationSuppressor()
        XCTAssertFalse(suppressor.isSilenced("cpu.5s.sh"))

        suppressor.silence("cpu.5s.sh")
        XCTAssertTrue(suppressor.isSilenced("cpu.5s.sh"))
        // Silencing one plugin does not affect others.
        XCTAssertFalse(suppressor.isSilenced("weather.1m.py"))
    }

    func testSuppressorSilenceIsIdempotent() {
        var suppressor = NotificationSuppressor()
        suppressor.silence("x")
        suppressor.silence("x")
        XCTAssertTrue(suppressor.isSilenced("x"))
    }

    // MARK: - Category / action identifiers

    func testActionIdentifiersAreStable() {
        XCTAssertEqual(NotificationRouter.categoryID, "VEE_PLUGIN_ALERT")
        XCTAssertEqual(NotificationRouter.rerunAction, "RERUN")
        XCTAssertEqual(NotificationRouter.silenceAction, "SILENCE")
        XCTAssertEqual(NotificationRouter.openLogAction, "OPEN_LOG")
    }

    // MARK: - Routing

    func testRouteRerunSilenceOpenLog() {
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: "RERUN", pluginID: "cpu.5s.sh", href: nil),
            .rerun(pluginID: "cpu.5s.sh")
        )
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: "SILENCE", pluginID: "cpu.5s.sh", href: nil),
            .silence(pluginID: "cpu.5s.sh")
        )
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: "OPEN_LOG", pluginID: "cpu.5s.sh", href: nil),
            .openLog(pluginID: "cpu.5s.sh")
        )
    }

    func testRouteCustomActionWithoutPluginIsNone() {
        XCTAssertEqual(NotificationRouter.route(actionIdentifier: "RERUN", pluginID: nil, href: nil), .none)
        XCTAssertEqual(NotificationRouter.route(actionIdentifier: "SILENCE", pluginID: nil, href: nil), .none)
        XCTAssertEqual(NotificationRouter.route(actionIdentifier: "OPEN_LOG", pluginID: nil, href: nil), .none)
    }

    func testDefaultTapOpensHref() {
        let url = URL(string: "https://example.com")!
        // The system default-tap identifier is not one of our custom actions,
        // so it falls through to opening the click-through URL.
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", pluginID: "cpu.5s.sh", href: url),
            .openHref(url)
        )
        // No href and no custom action => nothing to do.
        XCTAssertEqual(
            NotificationRouter.route(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", pluginID: nil, href: nil),
            .none
        )
    }
}
