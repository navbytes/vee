import XCTest
import Foundation
import Darwin
import VeeCore
@testable import VeeRuntime

/// Opt-in reliability soak benchmark. It drives the *real* execution/refresh
/// pipeline (`RefreshTimer` → `PluginExecutor` → `SystemProcessRunner` →
/// `StreamAccumulator`) for a configurable window and encodes Vee's two headline
/// reliability guarantees as assertions:
///
/// 1. **No refresh-death after long uptime.** The `RefreshTimer` must keep firing
///    for the whole window and every refresh must complete cleanly (exit 0, not
///    timed out). A silent stall — the #1 churn complaint against xbar/SwiftBar —
///    fails the test.
/// 2. **No memory creep.** Resident set size (sampled via `task_info` /
///    `mach_task_basic_info`) must not grow beyond a bounded threshold across the
///    run — the #2 churn complaint.
///
/// It is **skipped unless `VEE_SOAK=1`** so it never slows the normal `swift test`.
/// It runs as its own CI job (see `.github/workflows/ci.yml`, job `soak`).
///
/// Tunables (env vars, all optional):
/// - `VEE_SOAK_DURATION_SECONDS` — wall-clock length of the soak (default 60).
/// - `VEE_SOAK_INTERVAL_MS` — refresh cadence in milliseconds (default 100).
/// - `VEE_SOAK_GROWTH_LIMIT_MB` — max tolerated RSS growth (default 25).
/// - `VEE_SOAK_SAMPLES_PATH` — if set, write an `elapsed_s,rss_mb,cpu_pct` CSV
///   time-series here for charting (see `docs/scripts/soak_chart.py`).
final class MemorySoakBenchmarkTests: XCTestCase {
    func testPipelineSoakBoundedMemoryAndNoRefreshDeath() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["VEE_SOAK"] == "1" else {
            throw XCTSkip("Set VEE_SOAK=1 to run the reliability soak benchmark.")
        }

        let duration = env["VEE_SOAK_DURATION_SECONDS"].flatMap(Double.init) ?? 60
        let intervalMS = env["VEE_SOAK_INTERVAL_MS"].flatMap(Double.init) ?? 100
        let growthLimitMB = env["VEE_SOAK_GROWTH_LIMIT_MB"].flatMap(Double.init) ?? 25
        let interval = intervalMS / 1000.0

        // A representative, trivial echo-style plugin: it emits a couple of menu
        // lines around a `~~~` streaming separator so the StreamAccumulator path
        // is exercised on every refresh, just as in production.
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let pluginPath = (dir as NSString).appendingPathComponent("soak.\(Int(intervalMS))ms.sh")
        try """
        #!/bin/bash
        echo "Soak header"
        echo "~~~"
        echo "Soak body | color=green"
        """.write(toFile: pluginPath, atomically: true, encoding: .utf8)

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let context = RuntimeEnvironmentContext(
            pluginPath: pluginPath,
            pluginsDirectory: dir,
            cacheDirectory: dir,
            dataDirectory: dir,
            isDarkMode: false,
            osVersion: (os.majorVersion, os.minorVersion, os.patchVersion),
            appVersion: "soak",
            declaredVariables: [:]
        )

        let executor = PluginExecutor(runner: SystemProcessRunner(), baseEnvironment: ["PATH": "/usr/bin:/bin"])
        let counters = SoakCounters()

        // Drive refreshes with the production timer at the production-derived
        // leeway, so this proves the real scheduling path — not a bespoke loop.
        let leeway = RefreshScheduler.leeway(forSeconds: interval)
        let start = ProcessInfo.processInfo.systemUptime
        let timer = RefreshTimer()
        timer.start(interval: interval, leeway: leeway) {
            counters.recordFire()
            Task {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                let usage = sampleResourceUsage()
                do {
                    let outcome = try await executor.run(pluginPath: pluginPath, context: context, timeout: 5)
                    let healthy = outcome.exitCode == 0 && !outcome.timedOut && Self.parsedBlock(outcome.standardOutput)
                    counters.recordCompletion(success: healthy, elapsed: elapsed, rss: usage.rssBytes, cpuSeconds: usage.cpuSeconds)
                } catch {
                    counters.recordCompletion(success: false, elapsed: elapsed, rss: usage.rssBytes, cpuSeconds: usage.cpuSeconds)
                }
            }
        }

        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        timer.stop()
        // Let refreshes already in flight settle before reading the counters.
        try await Task.sleep(nanoseconds: 500_000_000)

        let fires = counters.fires
        let completions = counters.completions
        let failures = counters.failures
        let allSamples = counters.samples
        let samples = allSamples.map(\.rssBytes)
        let expectedFires = Int(duration / interval)

        // Optional: emit a time-series (elapsed_s, rss_mb, cpu_pct) so a real run
        // can be charted (see docs). CPU% is derived from the delta in cumulative
        // task CPU seconds between consecutive samples over their wall-clock gap.
        if let path = env["VEE_SOAK_SAMPLES_PATH"], !path.isEmpty {
            writeSamplesCSV(allSamples, to: path)
        }

        // (1) No refresh-death: the timer kept firing across the whole window and
        // work actually completed. Generous floor absorbs CI scheduling jitter and
        // energy-coalesced wake-ups, while still catching a true stall.
        XCTAssertGreaterThanOrEqual(
            fires, expectedFires / 2,
            "refresh timer stalled: fired \(fires) times, expected ~\(expectedFires)")
        XCTAssertGreaterThan(completions, 0, "no refresh ever completed")

        // Every refresh that ran must have completed cleanly — a timeout or
        // non-zero exit is exactly the silent-failure mode we guard against.
        XCTAssertEqual(failures, 0, "\(failures) of \(completions) refreshes failed or timed out")

        // (2) No memory creep: compare the median RSS of the first quarter of the
        // run against the last quarter. Medians shrug off transient allocation
        // spikes; sustained growth is what matters.
        guard samples.count >= 8 else {
            return XCTFail("too few memory samples (\(samples.count)) to judge growth")
        }
        let window = max(1, samples.count / 4)
        let baseline = median(Array(samples.prefix(window)))
        let tail = median(Array(samples.suffix(window)))
        let growthMB = (Double(tail) - Double(baseline)) / (1024 * 1024)

        XCTAssertLessThan(
            growthMB, growthLimitMB,
            "RSS grew \(String(format: "%.1f", growthMB)) MB over \(completions) refreshes (limit \(growthLimitMB) MB)")

        print("""
        [soak] duration=\(duration)s interval=\(intervalMS)ms fires=\(fires)/~\(expectedFires) \
        completions=\(completions) failures=\(failures) \
        rss baseline=\(baseline / (1024 * 1024))MB tail=\(tail / (1024 * 1024))MB growth=\(String(format: "%.1f", growthMB))MB
        """)
    }

    // MARK: - Helpers

    /// Feeds a plugin's stdout through `StreamAccumulator` and reports whether a
    /// non-empty render block came out — the same parse the live menu performs.
    private static func parsedBlock(_ output: String) -> Bool {
        var acc = StreamAccumulator()
        var block: String?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let emitted = acc.consume(line) { block = emitted }
        }
        if let flushed = acc.flush() { block = flushed }
        return (block?.isEmpty == false)
    }

    private func makeTempDirectory() throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("vee-soak-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }
}

/// One resource sample taken at a refresh completion.
private struct SoakSample {
    let elapsed: Double      // seconds since the soak started
    let rssBytes: UInt64     // resident set size
    let cpuSeconds: Double   // cumulative task CPU time (user+system)
}

/// Thread-safe tallies for the soak run. `@unchecked Sendable`: all state is
/// guarded by `lock` (mirrors `ProcessRun`'s concurrency discipline).
private final class SoakCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var _fires = 0
    private var _completions = 0
    private var _failures = 0
    private var _samples: [SoakSample] = []

    func recordFire() { lock.withLock { _fires += 1 } }

    func recordCompletion(success: Bool, elapsed: Double, rss: UInt64, cpuSeconds: Double) {
        lock.withLock {
            _completions += 1
            if !success { _failures += 1 }
            if rss > 0 { _samples.append(SoakSample(elapsed: elapsed, rssBytes: rss, cpuSeconds: cpuSeconds)) }
        }
    }

    var fires: Int { lock.withLock { _fires } }
    var completions: Int { lock.withLock { _completions } }
    var failures: Int { lock.withLock { _failures } }
    var samples: [SoakSample] { lock.withLock { _samples } }
}

/// Current resident set size (bytes) and cumulative task CPU time (seconds).
/// RSS comes from `MACH_TASK_BASIC_INFO`; CPU sums that flavor's *terminated*
/// thread time with `TASK_THREAD_TIMES_INFO`'s *live* thread time, so the number
/// reflects Vee's real in-process overhead (spawn syscalls, pipe draining, parse)
/// rather than under-reporting to ~0. RSS is 0 if the basic query fails.
private func sampleResourceUsage() -> (rssBytes: UInt64, cpuSeconds: Double) {
    func seconds(_ t: time_value_t) -> Double { Double(t.seconds) + Double(t.microseconds) / 1_000_000 }

    var basic = mach_task_basic_info()
    var bcount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
    let bkr = withUnsafeMutablePointer(to: &basic) { p in
        p.withMemoryRebound(to: integer_t.self, capacity: Int(bcount)) { ip in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ip, &bcount)
        }
    }
    guard bkr == KERN_SUCCESS else { return (0, 0) }
    var cpu = seconds(basic.user_time) + seconds(basic.system_time)

    var live = task_thread_times_info()
    var tcount = mach_msg_type_number_t(MemoryLayout<task_thread_times_info>.stride / MemoryLayout<natural_t>.stride)
    let tkr = withUnsafeMutablePointer(to: &live) { p in
        p.withMemoryRebound(to: integer_t.self, capacity: Int(tcount)) { ip in
            task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), ip, &tcount)
        }
    }
    if tkr == KERN_SUCCESS {
        cpu += seconds(live.user_time) + seconds(live.system_time)
    }
    return (basic.resident_size, cpu)
}

/// Writes the samples as CSV (`elapsed_s,rss_mb,cpu_pct`) so a real run can be
/// charted. CPU% is the derivative of cumulative CPU seconds over the wall-clock
/// gap between consecutive samples (0 for the first).
private func writeSamplesCSV(_ samples: [SoakSample], to path: String) {
    var lines = ["elapsed_s,rss_mb,cpu_pct"]
    var prev: SoakSample?
    for s in samples {
        let rssMB = Double(s.rssBytes) / (1024 * 1024)
        var cpuPct = 0.0
        if let p = prev {
            let dt = s.elapsed - p.elapsed
            if dt > 0 { cpuPct = max(0, (s.cpuSeconds - p.cpuSeconds) / dt * 100) }
        }
        lines.append(String(format: "%.2f,%.2f,%.1f", s.elapsed, rssMB, cpuPct))
        prev = s
    }
    try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
}

/// Median of a non-empty sample set (0 if empty).
private func median(_ xs: [UInt64]) -> UInt64 {
    guard !xs.isEmpty else { return 0 }
    let sorted = xs.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
    return sorted[mid]
}
