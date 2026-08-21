import Foundation
import VeeCore

/// Which mechanism drives a plugin's periodic refresh.
public enum RefreshStrategy: Sendable, Equatable {
    /// No periodic refresh (manual, or a cron schedule handled separately).
    case none
    /// A high-resolution `DispatchSourceTimer` (short intervals), with leeway so
    /// the system can coalesce wake-ups for energy efficiency.
    case highResolutionTimer(leeway: TimeInterval)
}

/// Chooses the refresh mechanism for an interval and computes timer leeway.
public enum RefreshScheduler {
    /// Every interval, however long, is driven by an in-process
    /// `DispatchSourceTimer`.
    ///
    /// Intervals of 10 minutes or more used to go to
    /// `NSBackgroundActivityScheduler` so the OS could batch wake-ups. That
    /// registers a *launch-on-demand* XPC activity against Vee's own launchd
    /// job, which made the app impossible to quit: launchd relaunched it within
    /// moments to service the activity. Energy batching is not worth an app the
    /// user cannot close — and it bought little here, since Vee is a resident
    /// menu-bar app that is already running. Timer leeway (below) still lets the
    /// system coalesce these wake-ups. See `LegacyBackgroundActivity` for
    /// clearing registrations left by earlier versions.
    public static func strategy(for interval: RefreshInterval) -> RefreshStrategy {
        guard let seconds = interval.timeInterval else { return .none }
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
            // Defense in depth: a zero/near-zero interval (e.g. a malformed
            // filename token that slipped past RefreshInterval's own floor)
            // would otherwise arm a repeating timer that refires continuously
            // and pegs a core.
            let safeInterval = max(interval, 0.1)
            t.schedule(deadline: .now() + safeInterval, repeating: safeInterval, leeway: .milliseconds(Int(leeway * 1000)))
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
