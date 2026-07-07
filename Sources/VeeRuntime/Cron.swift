import Foundation

/// A 5-field cron expression (`minute hour day-of-month month day-of-week`).
/// Supports `*`, single values, lists (`a,b`), ranges (`a-b`), and steps
/// (`*/n`, `a-b/n`). Day-of-week is 0–6 (0 = Sunday).
public struct CronExpression: Equatable, Sendable {
    let minutes: Set<Int>
    let hours: Set<Int>
    let daysOfMonth: Set<Int>
    let months: Set<Int>
    let daysOfWeek: Set<Int>
    let domRestricted: Bool
    let dowRestricted: Bool

    public init?(_ expression: String) {
        let fields = expression.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard fields.count == 5,
              let mins = Self.parseField(fields[0], min: 0, max: 59),
              let hrs = Self.parseField(fields[1], min: 0, max: 23),
              let dom = Self.parseField(fields[2], min: 1, max: 31),
              let mon = Self.parseField(fields[3], min: 1, max: 12),
              let dow = Self.parseField(fields[4], min: 0, max: 6)
        else { return nil }
        self.minutes = mins
        self.hours = hrs
        self.daysOfMonth = dom
        self.months = mon
        self.daysOfWeek = dow
        self.domRestricted = fields[2] != "*"
        self.dowRestricted = fields[4] != "*"
    }

    static func parseField(_ field: String, min lo: Int, max hi: Int) -> Set<Int>? {
        var result = Set<Int>()
        for part in field.split(separator: ",") {
            let stepSplit = part.split(separator: "/", maxSplits: 1)
            let rangePart = String(stepSplit[0])
            let step = stepSplit.count > 1 ? Int(stepSplit[1]) : 1
            guard let step, step > 0 else { return nil }

            var start = lo, end = hi
            if rangePart == "*" {
                // full range
            } else if rangePart.contains("-") {
                let bounds = rangePart.split(separator: "-")
                guard bounds.count == 2, let a = Int(bounds[0]), let b = Int(bounds[1]) else { return nil }
                start = a; end = b
            } else {
                guard let v = Int(rangePart) else { return nil }
                start = v; end = v
            }
            guard start >= lo, end <= hi, start <= end else { return nil }
            var v = start
            while v <= end { result.insert(v); v += step }
        }
        return result.isEmpty ? nil : result
    }

    public func matches(_ date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let mm = c.minute, let hh = c.hour, let dd = c.day, let mo = c.month, let wd = c.weekday else {
            return false
        }
        // Calendar weekday is 1=Sunday…7=Saturday → cron 0=Sunday…6=Saturday.
        let dow = wd - 1
        guard minutes.contains(mm), hours.contains(hh), months.contains(mo) else { return false }

        let domMatch = daysOfMonth.contains(dd)
        let dowMatch = daysOfWeek.contains(dow)
        // Vixie-cron rule: if both DOM and DOW are restricted, match on either.
        if domRestricted && dowRestricted {
            return domMatch || dowMatch
        }
        return domMatch && dowMatch
    }

    /// The next minute strictly after `date` that matches, or `nil` if none
    /// within a year.
    public func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let truncated = calendar.date(from: comps) else { return nil }
        var candidate = truncated.addingTimeInterval(60) // next whole minute
        let limit = date.addingTimeInterval(366 * 24 * 3600)
        while candidate <= limit {
            if matches(candidate, calendar: calendar) { return candidate }
            candidate = candidate.addingTimeInterval(60)
        }
        return nil
    }
}

/// Fires a callback on a cron schedule (one or more expressions). Reschedules to
/// the soonest next fire after each trigger.
/// `@unchecked Sendable`: state is confined to `queue`.
public final class CronScheduler: @unchecked Sendable {
    private let expressions: [CronExpression]
    private let onFire: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.vee.cron")
    private var timer: DispatchSourceTimer?

    public init?(schedules: [String], onFire: @escaping @Sendable () -> Void) {
        let parsed = schedules.compactMap(CronExpression.init)
        guard !parsed.isEmpty else { return nil }
        self.expressions = parsed
        self.onFire = onFire
    }

    public func start() { queue.async { [weak self] in self?.scheduleNext() } }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    private func scheduleNext() {
        let now = Date()
        guard let next = expressions.compactMap({ $0.nextFireDate(after: now) }).min() else { return }
        let delay = max(1, next.timeIntervalSince(now))
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Wall-clock, not monotonic: `deadline:` pauses while the system sleeps,
        // so a cron fire due mid-sleep would land hours late on wake instead of
        // promptly — cron is wall-clock by definition. `wallDeadline:` fires
        // immediately on wake once the deadline has passed, and scheduleNext()
        // realigns to the next matching minute from there.
        t.schedule(wallDeadline: .now() + delay, leeway: .seconds(1))
        t.setEventHandler { [weak self] in
            self?.onFire()
            self?.scheduleNext()
        }
        timer = t
        t.resume()
    }

    deinit { timer?.cancel() }
}
