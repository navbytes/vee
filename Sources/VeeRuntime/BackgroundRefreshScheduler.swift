import Foundation

/// Drives long-interval refreshes via `NSBackgroundActivityScheduler` so the
/// system can batch them for minimal energy/thermal impact — the right tool for
/// plugins that refresh every 10+ minutes.
/// `@unchecked Sendable`: the scheduler is thread-safe and `onFire` is `@Sendable`.
public final class BackgroundRefreshScheduler: @unchecked Sendable {
    private let scheduler: NSBackgroundActivityScheduler
    private let onFire: @Sendable () -> Void

    public init(identifier: String, interval: TimeInterval, onFire: @escaping @Sendable () -> Void) {
        self.scheduler = NSBackgroundActivityScheduler(identifier: identifier)
        self.scheduler.repeats = true
        self.scheduler.interval = interval
        self.scheduler.tolerance = min(interval * 0.1, 300)
        self.scheduler.qualityOfService = .background
        self.onFire = onFire
    }

    public func start() {
        scheduler.schedule { [onFire] completion in
            onFire()
            completion(.finished)
        }
    }

    public func stop() {
        scheduler.invalidate()
    }

    deinit { scheduler.invalidate() }
}
