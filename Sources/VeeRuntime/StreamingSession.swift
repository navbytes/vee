import Foundation
import VeeCore
import VeePluginFormat

/// Exponential backoff between streaming-plugin restarts.
public enum BackoffPolicy {
    /// 0.5s, 1s, 2s, 4s, … capped at 30s. `attempt` starts at 1.
    public static func delay(attempt: Int) -> TimeInterval {
        min(30, 0.5 * pow(2, Double(max(0, attempt - 1))))
    }
}

/// Flags a plugin that is restarting too often (crash-looping) so the session
/// can stop thrashing.
public struct CrashLoopDetector {
    public let maxRestarts: Int
    public let window: TimeInterval
    private var timestamps: [Date] = []

    public init(maxRestarts: Int = 5, window: TimeInterval = 60) {
        self.maxRestarts = maxRestarts
        self.window = window
    }

    /// Records a restart. Returns `true` if the restart rate exceeds the limit.
    public mutating func record(now: Date) -> Bool {
        timestamps.append(now)
        timestamps = timestamps.filter { now.timeIntervalSince($0) <= window }
        return timestamps.count > maxRestarts
    }
}

/// Runs a streamable plugin: launches a long-lived process, emits a parsed
/// menu on every `~~~`, and restarts with backoff when it exits — until it
/// crash-loops or is stopped.
@MainActor
public final class StreamingSession {
    private let runner: StreamingProcessRunning
    private let makeInvocation: @Sendable () -> ProcessInvocation
    private let onUpdate: (ParsedOutput) -> Void
    /// Called when the stream ends. `isFinal` distinguishes "backing off, will
    /// try again" from "given up" — the second needs a way back, because
    /// nothing else will start it.
    private let onStopped: (_ message: String, _ isFinal: Bool) -> Void
    private let clock: VeeClock

    private var task: Task<Void, Never>?
    private var detector = CrashLoopDetector()
    private var attempt = 0

    /// A stream that ran at least this long is considered healthy; the backoff
    /// attempt counter resets afterward.
    private let stableRunThreshold: TimeInterval = 10

    public init(
        runner: StreamingProcessRunning,
        clock: VeeClock = SystemClock(),
        makeInvocation: @escaping @Sendable () -> ProcessInvocation,
        onUpdate: @escaping (ParsedOutput) -> Void,
        onStopped: @escaping (_ message: String, _ isFinal: Bool) -> Void
    ) {
        self.runner = runner
        self.clock = clock
        self.makeInvocation = makeInvocation
        self.onUpdate = onUpdate
        self.onStopped = onStopped
    }

    public func start() {
        task = Task { [weak self] in await self?.runLoop() }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Starts the plugin again after it crash-looped and the session gave up.
    ///
    /// Giving up is right — a plugin failing on launch would otherwise respawn
    /// forever — but it left the plugin dead with no way back short of toggling
    /// it off and on in the Manager, which is not something the menu it left
    /// behind suggests. The crash-loop window and the backoff counter both
    /// reset, so this is a genuine fresh start and not one more doomed attempt
    /// against an already-tripped detector.
    public func restart() {
        stop()
        detector = CrashLoopDetector()
        attempt = 0
        start()
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let startedAt = clock.now
            var accumulator = StreamAccumulator()
            var failure: String?
            do {
                for try await line in runner.lines(makeInvocation()) {
                    if let block = accumulator.consume(line) {
                        onUpdate(OutputParser.parseAuto(block))
                    }
                }
                // A cancelled session (stop()) must not flush whatever
                // partial, separator-less block was sitting in the
                // accumulator when the stream ended — that's a garbled,
                // stale render, not a real update. Mirrors the check just
                // below for the rest of the restart/backoff handling.
                if !Task.isCancelled, let block = accumulator.flush() {
                    onUpdate(OutputParser.parseAuto(block))
                }
            } catch {
                // A bad exit or a launch failure. Keep the reason: it is the
                // only description of the problem the user will ever get, and
                // the restart message alone ("stopped — restarting…") says
                // nothing about why the plugin keeps dying.
                failure = (error as? StreamingPluginError)?.summary
                    ?? (error as? VeeError).map { "\($0)" }
            }

            if Task.isCancelled { break }

            // Reset the backoff counter if the process ran healthily for a while.
            if clock.now.timeIntervalSince(startedAt) >= stableRunThreshold {
                attempt = 0
            }
            attempt += 1

            let reason = failure.map { ": \($0)" } ?? ""
            if detector.record(now: clock.now) {
                onStopped("Plugin stopped — restarting too frequently\(reason)", true)
                break
            }
            onStopped("Plugin stopped — restarting…\(reason)", false)
            try? await clock.sleep(for: BackoffPolicy.delay(attempt: attempt))
        }
    }
}
