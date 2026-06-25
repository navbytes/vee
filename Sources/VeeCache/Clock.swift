import Foundation

/// An injectable source of "now" so TTL / staleness logic is testable without
/// wall-clock sleeps. Production code uses ``SystemClock``; tests drive a
/// ``FakeClock`` they advance by hand.
public protocol Clock: Sendable {
    var now: Date { get }
}

/// Real wall-clock time.
public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock whose time only moves when the test advances it. Thread-safe so
/// concurrent reads (e.g. the in-flight de-dup test) observe a consistent value.
public final class FakeClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    public init(start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self._now = start
    }

    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    /// Move time forward by `interval` seconds.
    public func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(interval)
    }

    /// Jump to an absolute instant.
    public func set(to date: Date) {
        lock.lock(); defer { lock.unlock() }
        _now = date
    }
}
