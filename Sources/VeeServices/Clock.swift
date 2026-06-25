import Foundation

/// An injectable source of "now" so time-dependent logic (clipboard timestamps,
/// frecency decay, calendar windows) is testable without wall-clock sleeps.
///
/// This is VeeServices' own seam (build plan §5 lists `Clock` among the seams
/// this target owns). It is intentionally NOT the `VeeCache.Clock`: the
/// `VeeServicesTests` target does not depend on VeeCache, so keeping the
/// protocol + fake here lets tests construct a `ManualClock` via
/// `@testable import VeeServices` with no extra dependency. Production wires a
/// `SystemClock`.
public protocol Clock: Sendable {
    var now: Date { get }
}

/// Real wall-clock time.
public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock whose time only moves when the test advances it. Thread-safe so a
/// background poll loop and the test thread observe a consistent value.
public final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    public init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self._now = now
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
