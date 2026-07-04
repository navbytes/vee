import XCTest
@testable import VeeRuntime

final class CronTests: XCTestCase {
    private func utc() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        utc().date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testParsesValidAndRejectsInvalid() {
        XCTAssertNotNil(CronExpression("*/15 * * * *"))
        XCTAssertNotNil(CronExpression("0 9 * * 1-5"))
        XCTAssertNil(CronExpression("* * *"))         // too few fields
        XCTAssertNil(CronExpression("60 * * * *"))    // minute out of range
        XCTAssertNil(CronExpression("abc * * * *"))   // non-numeric
        XCTAssertNil(CronExpression("* * * * 9"))     // dow out of range
    }

    func testFieldListsRangesSteps() {
        XCTAssertEqual(CronExpression.parseField("1,2,3", min: 0, max: 59), [1, 2, 3])
        XCTAssertEqual(CronExpression.parseField("10-12", min: 0, max: 59), [10, 11, 12])
        XCTAssertEqual(CronExpression.parseField("*/20", min: 0, max: 59), [0, 20, 40])
        XCTAssertEqual(CronExpression.parseField("0-30/15", min: 0, max: 59), [0, 15, 30])
    }

    func testEveryFifteenMinutes() {
        let expr = CronExpression("*/15 * * * *")!
        let next = expr.nextFireDate(after: date(2026, 7, 4, 10, 7), calendar: utc())
        XCTAssertEqual(next, date(2026, 7, 4, 10, 15))
    }

    func testDailyRollsToNextDay() {
        let expr = CronExpression("0 9 * * *")!
        let next = expr.nextFireDate(after: date(2026, 7, 4, 10, 0), calendar: utc())
        XCTAssertEqual(next, date(2026, 7, 5, 9, 0))
    }

    func testDayOfWeek() {
        // Monday 08:30. 2026-07-04 is a Saturday → next Monday is 2026-07-06.
        let expr = CronExpression("30 8 * * 1")!
        let next = expr.nextFireDate(after: date(2026, 7, 4, 0, 0), calendar: utc())
        XCTAssertEqual(next, date(2026, 7, 6, 8, 30))
    }

    func testSchedulerRequiresValidExpression() {
        XCTAssertNil(CronScheduler(schedules: ["not a cron"], onFire: {}))
        XCTAssertNotNil(CronScheduler(schedules: ["* * * * *"], onFire: {}))
    }
}
