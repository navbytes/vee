import Foundation
import VeeCore

/// Which mechanism drives a plugin's periodic refresh.
public enum RefreshStrategy: Sendable, Equatable {
    /// No periodic refresh (manual, or a cron schedule handled separately).
    case none
    /// A high-resolution `DispatchSourceTimer` (short intervals), with leeway so
    /// the system can coalesce wake-ups for energy efficiency.
    case highResolutionTimer(leeway: TimeInterval)
    /// `NSBackgroundActivityScheduler` — the OS batches long-interval refreshes
    /// for minimal energy impact.
    case backgroundActivity
}

/// Chooses the refresh mechanism for an interval and computes timer leeway.
public enum RefreshScheduler {
    /// Intervals at or above this use the energy-friendly background scheduler.
    public static let backgroundThreshold: TimeInterval = 600 // 10 minutes

    public static func strategy(for interval: RefreshInterval) -> RefreshStrategy {
        guard let seconds = interval.timeInterval else { return .none }
        if seconds >= backgroundThreshold {
            return .backgroundActivity
        }
        return .highResolutionTimer(leeway: leeway(forSeconds: seconds))
    }

    /// Leeway ~15% of the interval, clamped to [50 ms, 60 s]. A larger leeway
    /// lets the system coalesce timers; too large hurts perceived freshness.
    public static func leeway(forSeconds seconds: TimeInterval) -> TimeInterval {
        min(max(seconds * 0.15, 0.05), 60)
    }
}

/// A thin repeating-timer driver built on `DispatchSourceTimer`. Fires `handler`
/// every `interval` with the given leeway until cancelled.
/// `@unchecked Sendable`: state is confined to `queue`.
public final class RefreshTimer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vee.refresh-timer")
    private var timer: DispatchSourceTimer?

    public init() {}

    public func start(interval: TimeInterval, leeway: TimeInterval, handler: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(leeway * 1000)))
            t.setEventHandler(handler: handler)
            self.timer = t
            t.resume()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    deinit { timer?.cancel() }
}
