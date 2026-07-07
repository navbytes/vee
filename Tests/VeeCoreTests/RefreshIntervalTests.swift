import XCTest
@testable import VeeCore

final class RefreshIntervalTests: XCTestCase {
    func testParsesEachUnit() {
        XCTAssertEqual(RefreshInterval.parse(token: "500ms"), .milliseconds(500))
        XCTAssertEqual(RefreshInterval.parse(token: "10s"), .seconds(10))
        XCTAssertEqual(RefreshInterval.parse(token: "1m"), .minutes(1))
        XCTAssertEqual(RefreshInterval.parse(token: "2h"), .hours(2))
        XCTAssertEqual(RefreshInterval.parse(token: "1d"), .days(1))
    }

    func testMillisecondsCheckedBeforeMinutes() {
        // "ms" must win over "m" so 500ms is not parsed as 500 minutes.
        XCTAssertEqual(RefreshInterval.parse(token: "500ms"), .milliseconds(500))
        XCTAssertNotEqual(RefreshInterval.parse(token: "500ms"), .minutes(500))
    }

    func testRejectsInvalidTokens() {
        XCTAssertNil(RefreshInterval.parse(token: ""))
        XCTAssertNil(RefreshInterval.parse(token: "abc"))
        XCTAssertNil(RefreshInterval.parse(token: "10"))      // no unit
        XCTAssertNil(RefreshInterval.parse(token: "s"))       // no value
        XCTAssertNil(RefreshInterval.parse(token: "10w"))     // unsupported unit
        XCTAssertNil(RefreshInterval.parse(token: "10 s"))    // space
    }

    /// Regression: a `0` interval (e.g. `cpu.0s.sh`) would arm a repeating timer
    /// with a ~zero period, continuously refiring and pegging a core. A zero
    /// value must be rejected so the plugin falls back to the manual/no-interval
    /// path (see PluginFilenameTests for the filename-level fallback).
    func testRejectsZeroInterval() {
        XCTAssertNil(RefreshInterval.parse(token: "0s"))
        XCTAssertNil(RefreshInterval.parse(token: "0ms"))
        XCTAssertNil(RefreshInterval.parse(token: "0m"))
        XCTAssertNil(RefreshInterval.parse(token: "0h"))
        XCTAssertNil(RefreshInterval.parse(token: "0d"))
        // A genuinely positive interval still parses.
        XCTAssertEqual(RefreshInterval.parse(token: "5s"), .seconds(5))
    }

    func testTimeInterval() {
        XCTAssertEqual(RefreshInterval.milliseconds(500).timeInterval, 0.5)
        XCTAssertEqual(RefreshInterval.seconds(10).timeInterval, 10)
        XCTAssertEqual(RefreshInterval.minutes(2).timeInterval, 120)
        XCTAssertEqual(RefreshInterval.hours(1).timeInterval, 3600)
        XCTAssertEqual(RefreshInterval.days(1).timeInterval, 86_400)
        XCTAssertNil(RefreshInterval.manual.timeInterval)
        XCTAssertNil(RefreshInterval.cron("* * * * *").timeInterval)
    }
}
