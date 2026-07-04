import Foundation

/// An injectable clock so time-dependent logic (the refresh scheduler, backoff,
/// timeouts) can be driven deterministically in tests. Named `VeeClock` to avoid
/// collision with the standard-library `Clock` protocol.
public protocol VeeClock: Sendable {
    /// The current wall-clock instant.
    var now: Date { get }
    /// Suspends for at least `seconds`.
    func sleep(for seconds: TimeInterval) async throws
}

/// The production clock, backed by the system wall clock and `Task.sleep`.
public struct SystemClock: VeeClock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
