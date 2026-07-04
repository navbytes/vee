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
    private let onStopped: (String) -> Void
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
        onStopped: @escaping (String) -> Void
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

    private func runLoop() async {
        while !Task.isCancelled {
            let startedAt = clock.now
            var accumulator = StreamAccumulator()
            do {
                for try await line in runner.lines(makeInvocation()) {
                    if let block = accumulator.consume(line) {
                        onUpdate(OutputParser.parseAuto(block))
                    }
                }
                if let block = accumulator.flush() {
                    onUpdate(OutputParser.parseAuto(block))
                }
            } catch {
                // Launch failure: fall through to restart handling.
            }

            if Task.isCancelled { break }

            // Reset the backoff counter if the process ran healthily for a while.
            if clock.now.timeIntervalSince(startedAt) >= stableRunThreshold {
                attempt = 0
            }
            attempt += 1

            if detector.record(now: clock.now) {
                onStopped("Plugin stopped — restarting too frequently")
                break
            }
            onStopped("Plugin stopped — restarting…")
            try? await clock.sleep(for: BackoffPolicy.delay(attempt: attempt))
        }
    }
}
