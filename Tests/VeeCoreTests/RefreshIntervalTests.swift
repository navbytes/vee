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
