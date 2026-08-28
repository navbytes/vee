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

    /// February 30th parses as a valid expression that no date ever satisfies.
    /// The scheduler has nothing to arm and goes quiet, so callers need to be
    /// able to tell that apart from a schedule that is merely infrequent —
    /// otherwise the plugin's refresh is disabled permanently and silently.
    func testSchedulerReportsAnExpressionThatCanNeverFire() {
        let impossible = CronScheduler(schedules: ["0 0 30 2 *"], onFire: {})
        XCTAssertNotNil(impossible, "it parses — that is the whole problem")
        XCTAssertEqual(impossible?.canEverFire, false, "February has no 30th")

        XCTAssertEqual(CronScheduler(schedules: ["0 0 31 4 *"], onFire: {})?.canEverFire, false, "April has no 31st")
        XCTAssertEqual(CronScheduler(schedules: ["0 3 * * *"], onFire: {})?.canEverFire, true)
    }

    /// The check must be structural, not a forward search. `nextFireDate` only
    /// looks a year ahead, so a legitimate leap-day schedule has no fire within
    /// the window for up to four years — searching would condemn it as
    /// impossible and show the user an error about a schedule that is fine.
    func testLeapDayScheduleIsNotImpossible() {
        XCTAssertEqual(CronScheduler(schedules: ["0 0 29 2 *"], onFire: {})?.canEverFire, true,
                       "Feb 29 exists in a leap year")
    }

    /// Vixie's either-or rule: with day-of-month AND day-of-week both
    /// restricted, a match on either fires — so a restricted weekday rescues an
    /// impossible day-of-month.
    func testRestrictedWeekdayRescuesAnImpossibleDayOfMonth() {
        XCTAssertEqual(CronScheduler(schedules: ["0 0 30 2 1"], onFire: {})?.canEverFire, true,
                       "fires every Monday in February regardless of the 30th")
    }

    /// One impossible expression alongside a workable one is not a dead
    /// schedule — the plugin still refreshes on the good one.
    func testOneWorkableExpressionIsEnough() {
        XCTAssertEqual(CronScheduler(schedules: ["0 0 30 2 *", "0 3 * * *"], onFire: {})?.canEverFire, true)
    }
}
