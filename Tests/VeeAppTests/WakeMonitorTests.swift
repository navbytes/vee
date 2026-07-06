import XCTest
import AppKit
@testable import VeeApp

@MainActor
final class WakeMonitorTests: XCTestCase {
    func testFiresOnWakeAndStops() {
        let center = NotificationCenter()
        var count = 0
        let monitor = WakeMonitor(center: center) { count += 1 }

        monitor.start()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(count, 1, "wake should trigger a refresh")

        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(count, 2, "each wake re-runs plugins")

        monitor.stop()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(count, 2, "no refresh after stop")
    }
}
