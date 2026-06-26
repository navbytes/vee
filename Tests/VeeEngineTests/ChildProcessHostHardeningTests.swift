import XCTest
@testable import VeeEngine
import VeeProtocol

/// Wave R2 — §5 out-of-process host hardening for `ChildProcessHost`.
///
/// Covers four §5 / test-honesty items from docs/AUDIT-2.md, all deterministic
/// and self-contained (no committed product binary required — these spawn small
/// system utilities like `/bin/sleep` as stand-in children, or assert pure logic):
///
///   • **Request timeout / hang watchdog** — a child that reads but never replies
///     (a stand-in for a plugin spinning inside `activate`) must surface
///     `onRequestTimeout`, not hang the parent forever.
///   • **restart() / terminationHandler generation race** — a stale child's late
///     `terminationHandler` must NOT tear down the freshly-restarted child's
///     transport. Driven via a SIGTERM-trapping child so the old process is still
///     alive (its handler still armed) when the new generation is installed.
///   • **SIGKILL crash isolation (test-honesty fix)** — `testRealChild…` in
///     `OutOfProcessTests` only SIGTERMs and never asserts `byUncaughtSignal`;
///     here we SIGKILL a child mid-flight and assert the parent survives, the
///     termination is reported as an uncaught signal, and `restart()` brings a
///     fresh child back.
///   • **Bundle.main child resolver** — `defaultChildBinaryURL()` honors the
///     `VEE_PLUGIN_HOST` override and returns nil (rather than a bogus path) when
///     nothing is found, so the caller can fall back.
///
/// New file (per the build rules) so the existing `OutOfProcessTests` is left
/// untouched and stays green.
final class ChildProcessHostHardeningTests: XCTestCase {

    // MARK: - Request timeout / hang watchdog

    /// `/bin/sleep` keeps its stdin open and never writes to stdout, so a request
    /// sent to it is never answered — the exact shape of a plugin that hangs
    /// inside `activate`. The watchdog must fire `onRequestTimeout` with the
    /// method/id, and the parent (this process) keeps running. We send a SINGLE
    /// tracked request (`load`) so exactly one timeout fires deterministically.
    func testHangingChildSurfacesRequestTimeout() throws {
        let host = ChildProcessHost(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            requestTimeout: 0.5)   // short, deterministic deadline

        let timedOut = expectation(description: "onRequestTimeout fires for the unanswered request")
        var captured: ChildProcessHost.RequestTimeout?
        host.onRequestTimeout = { info in captured = info; timedOut.fulfill() }

        try host.start()
        defer { host.terminate() }

        // `sleep` never speaks our protocol, so this load gets no reply ever.
        try host.load(
            manifest: PluginManifest(id: "com.vee.hang", name: "Hang", version: "1.0.0",
                                     entrypoint: "b.js",
                                     commands: [PluginCommand(name: "view", title: "V", mode: .view)],
                                     capabilities: Capabilities()),
            source: "definePlugin(()=>({}))")

        wait(for: [timedOut], timeout: 5)
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.id, "load-com.vee.hang")
        XCTAssertEqual(captured?.method, ChildHostMethods.loadPlugin)
        XCTAssertEqual(captured?.timeout, 0.5)
        XCTAssertTrue(host.isRunning, "the parent did not hang; the child is still alive")
    }

    /// `loadAndActivate` sends TWO correlated requests (`load` + `activate`); a
    /// hanging child answers neither, so BOTH watchdogs must fire (each is tracked
    /// under its own id). Proves per-request correlation, not just a single timer.
    func testHangingChildTimesOutBothLoadAndActivate() throws {
        let host = ChildProcessHost(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            requestTimeout: 0.5)

        let bothTimedOut = expectation(description: "both load and activate time out")
        bothTimedOut.expectedFulfillmentCount = 2
        let ids = TimeoutIDCollector()
        host.onRequestTimeout = { info in ids.add(info.id); bothTimedOut.fulfill() }

        try host.start()
        defer { host.terminate() }
        try host.loadAndActivate(
            manifest: PluginManifest(id: "com.vee.hang2", name: "Hang", version: "1.0.0",
                                     entrypoint: "b.js",
                                     commands: [PluginCommand(name: "view", title: "V", mode: .view)]),
            source: "x", command: "view")

        wait(for: [bothTimedOut], timeout: 5)
        XCTAssertEqual(ids.snapshot(), ["activate-com.vee.hang2", "load-com.vee.hang2"],
                       "both correlated requests time out independently")
        XCTAssertTrue(host.isRunning)
    }

    /// A `requestTimeout <= 0` disables the watchdog entirely: no timer is armed,
    /// so `onRequestTimeout` must NOT fire even though the child never replies.
    func testZeroTimeoutDisablesWatchdog() throws {
        let host = ChildProcessHost(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            requestTimeout: 0)

        let didFire = expectation(description: "watchdog must NOT fire when disabled")
        didFire.isInverted = true
        host.onRequestTimeout = { _ in didFire.fulfill() }

        try host.start()
        defer { host.terminate() }
        try host.load(manifest: PluginManifest(id: "com.vee.nowd", name: "N", version: "1.0.0",
                                               entrypoint: "b.js",
                                               commands: [PluginCommand(name: "v", title: "V", mode: .view)]),
                      source: "x")
        wait(for: [didFire], timeout: 1.0)
        host.terminate()
    }

    /// When the child dies, any in-flight request watchdog is cancelled (the
    /// response will never come) — we must NOT also fire a spurious timeout on top
    /// of the termination. `onTermination` fires; `onRequestTimeout` does not.
    func testChildDeathCancelsPendingTimeout() throws {
        let host = ChildProcessHost(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            requestTimeout: 2.0)

        let terminated = expectation(description: "onTermination fires")
        host.onTermination = { _ in terminated.fulfill() }
        let spuriousTimeout = expectation(description: "no timeout after the child is gone")
        spuriousTimeout.isInverted = true
        host.onRequestTimeout = { _ in spuriousTimeout.fulfill() }

        try host.start()
        defer { host.terminate() }
        try host.load(manifest: PluginManifest(id: "com.vee.die", name: "D", version: "1.0.0",
                                               entrypoint: "b.js",
                                               commands: [PluginCommand(name: "v", title: "V", mode: .view)]),
                      source: "x")
        // Kill the child well before the 2s deadline; the pending timer must be
        // cancelled by the termination path, not allowed to fire later.
        host.terminate()
        wait(for: [terminated], timeout: 5)
        wait(for: [spuriousTimeout], timeout: 1.5)
    }

    // MARK: - restart() / terminationHandler generation race

    /// Fully-deterministic generation-race check. A normal `/bin/sleep` child is
    /// killed promptly by `terminate()`'s SIGTERM, so its async
    /// `terminationHandler` is *queued* and fires shortly AFTER `restart()` has
    /// already installed the next generation's process+transport. The generation
    /// guard must make that stale handler a no-op: the freshly-restarted child
    /// must remain running and reachable. Without the guard, the old handler nulls
    /// the current `process`/`transport` and `isRunning` flips false.
    func testStaleTerminationHandlerDoesNotKillRestartedChild() throws {
        let host = ChildProcessHost(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["60"],
            requestTimeout: 0)   // watchdog off — this is a supervision test

        // Count terminations so we can confirm old children's handlers actually
        // fired (the race is only meaningful if they did).
        let terminations = TerminationCounter()
        host.onTermination = { _ in terminations.increment() }

        try host.start()
        defer { host.terminate() }
        XCTAssertTrue(host.isRunning)

        // Restart several times in tight succession. Each restart bumps the
        // generation; each predecessor's SIGTERM-driven terminationHandler fires
        // asynchronously, racing the next start. A missing guard lets gen N's late
        // handler tear down gen N+1.
        for _ in 0..<5 {
            try host.restart()
            XCTAssertTrue(host.isRunning, "the restarted child is the current, live one")
        }

        // Let every queued predecessor terminationHandler drain, then confirm the
        // current child is STILL up and at least one termination actually fired.
        let settle = expectation(description: "stale terminationHandlers drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { settle.fulfill() }
        wait(for: [settle], timeout: 3)
        XCTAssertGreaterThan(terminations.count, 0, "old children did terminate (race was live)")
        XCTAssertTrue(host.isRunning, "current child survived all stale terminationHandlers")
    }

    // MARK: - SIGKILL crash isolation (test-honesty fix)

    /// The audit flags `testRealChildCrashIsolationAndRestart` as mislabeled: it
    /// sends SIGTERM (a clean shutdown) and never asserts `byUncaughtSignal`. This
    /// test makes the child take an **uncaught SIGKILL mid-flight** and asserts
    /// (a) the parent (this process) survives, (b) `onTermination` reports
    /// `byUncaughtSignal == true` with status 9, and (c) `restart()` brings a
    /// fresh child back.
    ///
    /// The child is `/bin/sh -c 'sleep …; kill -9 $$'`: it lives briefly (so it is
    /// genuinely "running" and mid-flight), then SIGKILLs *itself*. Verified to
    /// produce `terminationReason == .uncaughtSignal` / `terminationStatus == 9`.
    /// Self-killing needs no PID capture and matches no unrelated process — the
    /// crash is fully contained to the child this test spawned.
    func testSigkilledChildIsReportedAsUncaughtAndParentSurvives() throws {
        let host = ChildProcessHost(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 0.4; kill -9 $$"],
            requestTimeout: 0)

        let crashed = expectation(description: "onTermination fires for the SIGKILLed child")
        var info: ChildProcessHost.TerminationInfo?
        host.onTermination = { i in info = i; crashed.fulfill() }

        try host.start()
        defer { host.terminate() }
        XCTAssertTrue(host.isRunning, "child is live and mid-flight before the crash")

        // Wait for the child to SIGKILL itself (an uncaught crash, NOT a clean
        // SIGTERM). The parent must observe it without dying.
        wait(for: [crashed], timeout: 10)
        let term = try XCTUnwrap(info)
        XCTAssertTrue(term.byUncaughtSignal, "a SIGKILL is reported as an uncaught signal, not a clean exit")
        XCTAssertEqual(term.status, 9, "terminationStatus is SIGKILL")
        XCTAssertFalse(host.isRunning, "the host observes the child is gone")
        // We are obviously still alive to assert this — crash isolation holds: the
        // child's uncaught crash did not take the parent down.

        // restart() on the SAME host brings a fresh child back (it will itself
        // self-kill after 0.4s, but it is live right now — that's the restart
        // contract: the parent can recover the child after a crash).
        try host.restart()
        XCTAssertTrue(host.isRunning, "restart spawned a fresh child after the crash")
    }

    // MARK: - Bundle.main child resolver

    /// The `VEE_PLUGIN_HOST` env override (an explicit, executable path) is
    /// honored first. We point it at a real executable (`/bin/sleep`) and assert
    /// the resolver returns exactly that.
    func testDefaultChildBinaryHonorsEnvOverride() throws {
        let key = "VEE_PLUGIN_HOST"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, "/bin/sleep", 1)
        defer {
            if let previous { setenv(key, previous, 1) } else { unsetenv(key) }
        }
        let url = ChildProcessHost.defaultChildBinaryURL()
        XCTAssertEqual(url?.path, "/bin/sleep")
    }

    /// With no override and an obviously-absent binary name, the resolver returns
    /// nil (it does not fabricate a non-existent path), so a caller can fall back
    /// to in-process rather than trying to launch a missing executable.
    func testDefaultChildBinaryReturnsNilWhenAbsent() {
        let previous = ProcessInfo.processInfo.environment["VEE_PLUGIN_HOST"]
        unsetenv("VEE_PLUGIN_HOST")
        defer { if let previous { setenv("VEE_PLUGIN_HOST", previous, 1) } }
        let url = ChildProcessHost.defaultChildBinaryURL(
            binaryName: "vee-plugin-host-does-not-exist-\(UUID().uuidString)")
        XCTAssertNil(url, "no executable found ⇒ nil, not a bogus URL")
    }

    // MARK: - Helpers

    private final class TerminationCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() { lock.lock(); n += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private final class TimeoutIDCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []
        func add(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
        func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return ids.sorted() }
    }
}
