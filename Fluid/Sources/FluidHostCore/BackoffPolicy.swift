import Foundation

/// How the supervisor restarts a plugin that keeps exiting.
///
/// Delays grow geometrically (1s, 2s, 4s… up to `maxDelay`) so a plugin that
/// crashes on start can't spin a CPU core, and after `maxConsecutiveFailures`
/// the supervisor gives up and shows the plugin as failed. A plugin that stayed
/// up for `stableAfter` seconds before exiting starts the count again: one
/// crash a day is not a crash loop.
public struct BackoffPolicy: Equatable, Sendable {
    public var initialDelay: Double
    public var multiplier: Double
    public var maxDelay: Double
    public var maxConsecutiveFailures: Int
    public var stableAfter: Double

    public init(initialDelay: Double = 1, multiplier: Double = 2, maxDelay: Double = 60, maxConsecutiveFailures: Int = 5, stableAfter: Double = 60) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.stableAfter = stableAfter
    }

    public static let standard = BackoffPolicy()

    /// Seconds to wait before restart number `failures` (1-based), or `nil`
    /// when the supervisor should stop trying.
    public func delay(afterFailures failures: Int) -> Double? {
        guard failures >= 1, failures <= maxConsecutiveFailures else { return nil }
        return min(maxDelay, initialDelay * pow(multiplier, Double(failures - 1)))
    }
}
