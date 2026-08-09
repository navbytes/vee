import XCTest
@testable import VeeApp
import VeeCore
import VeeRuntime

/// Cross-package seam: a plugin's `<vee.timeout>` header
/// (`VeePluginFormat.HeaderParser` → `VeeRuntime.PluginRuntime`) combined with
/// `PluginCoordinator`'s in-flight guard. No per-package test drives this
/// combination end-to-end: `VeeRuntimeTests` stubs `PluginRuntime.refresh`
/// directly with a hand-built `HeaderMetadata` (never a parsed plugin file),
/// and nothing in `VeeAppTests` exercises `PluginCoordinator`'s overlap
/// guard at all. This does both at once, through the real coordinator.
///
/// Uses a `.widget`-surface plugin so the coordinator builds no `NSStatusItem`
/// — the same safe construction `WidgetActionRefreshTests` established
/// (never touches `NSApplication.shared`).
final class PluginCoordinatorRefreshOverlapTests: XCTestCase {
    /// Records every invocation (in particular its resolved `timeout`) without
    /// ever spawning a real process.
    private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _invocations: [ProcessInvocation] = []
        var invocations: [ProcessInvocation] { lock.withLock { _invocations } }

        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            lock.withLock { _invocations.append(invocation) }
            return ProcessOutcome(standardOutput: "", standardError: "", exitCode: 0, timedOut: false)
        }
    }

    /// Writes a widget-only plugin declaring a `<vee.timeout>` override to a
    /// temp dir and returns (coordinator, runner, dir) — mirrors
    /// `WidgetActionRefreshTests.makeCoordinator()`.
    @MainActor
    private func makeCoordinator() throws -> (PluginCoordinator, RecordingRunner, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-overlap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("slow.sh").path
        let source = "#!/bin/bash\n# <vee.surface>widget</vee.surface>\n# <vee.timeout>90s</vee.timeout>\necho hi\n"
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        let plugin = DiscoveredPlugin(
            path: path,
            id: PluginID(path: path),
            filename: PluginFilename("slow.sh"),
            isExecutable: true
        )
        let runner = RecordingRunner()
        let runtime = PluginRuntime(executor: PluginExecutor(runner: runner, baseEnvironment: [:]))
        let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: dir.path, runtime: runtime, baseEnvironment: [:])
        return (coordinator, runner, dir)
    }

    /// Three back-to-back triggers with no suspension in between:
    /// `refreshWidget()` sets its in-flight flag synchronously, before its
    /// `Task` is even created, so the second and third calls must see it
    /// already set and return without launching a second process — no
    /// overlap, regardless of the header's declared timeout. Once the first
    /// run settles, a later trigger must still go through: serialized, not
    /// permanently stuck.
    @MainActor
    func testOverlappingWidgetRefreshesAreSerializedNotOverlapped() throws {
        let (coordinator, runner, dir) = try makeCoordinator()
        defer { try? FileManager.default.removeItem(at: dir) }

        let firstSettled = expectation(description: "first run settles")
        coordinator.onPublish = { _ in firstSettled.fulfill() }

        coordinator.forceRefreshWidget()
        coordinator.forceRefreshWidget()
        coordinator.forceRefreshWidget()

        wait(for: [firstSettled], timeout: 5)
        XCTAssertEqual(runner.invocations.count, 1, "two overlapping triggers while a run is in flight must be dropped, not queued")
        XCTAssertEqual(runner.invocations.first?.timeout, 90, "the header's <vee.timeout> must reach the actual process invocation")

        let secondSettled = expectation(description: "second run settles")
        coordinator.onPublish = { _ in secondSettled.fulfill() }
        coordinator.forceRefreshWidget()
        wait(for: [secondSettled], timeout: 5)

        XCTAssertEqual(runner.invocations.count, 2, "a trigger after the in-flight run settles must go through, not stay stuck")
    }
}

/// Regression: `AppController.reload()` calls `coordinator.stop()` then
/// immediately builds and starts a replacement coordinator for the same
/// plugin — but `stop()` used to only stop schedulers/timers, never the
/// in-flight one-shot `refresh()` itself (a fire-and-forget `Task` with no
/// stored handle), so the old run's child process kept going, racing the
/// replacement's run of the same plugin (both writing
/// `SWIFTBAR_PLUGIN_DATA_PATH`). `stop()` must now cancel the stored refresh
/// Task, and that cancellation must be observable all the way down through
/// `PluginRuntime`/`PluginExecutor` to the injected `ProcessRunning` — which
/// is exactly what `SystemProcessRunner` maps to an actual child kill in
/// production (see its `withTaskCancellationHandler`, covered separately by
/// `VeeRuntimeTests.ProcessRunnerIntegrationTests.
/// testCancellingAwaitingTaskTerminatesChild`).
final class PluginCoordinatorStopCancelsRefreshTests: XCTestCase {
    /// Never spawns a real process; instead blocks (polling `Task.isCancelled`
    /// rather than a long fixed sleep, so the test settles as soon as `stop()`
    /// cancels it) to simulate a slow/hung child.
    private final class SlowRunner: ProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _startedCount = 0
        private var _observedCancelled = false
        var startedCount: Int { lock.withLock { _startedCount } }
        var observedCancelled: Bool { lock.withLock { _observedCancelled } }

        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            lock.withLock { _startedCount += 1 }
            for _ in 0..<200 { // up to ~2s
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            lock.withLock { _observedCancelled = Task.isCancelled }
            return ProcessOutcome(standardOutput: "", standardError: "", exitCode: 0, timedOut: false)
        }
    }

    @MainActor
    private func makeCoordinator(runner: ProcessRunning) throws -> (PluginCoordinator, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-stopcancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("slow.sh").path
        let source = "#!/bin/bash\n# <vee.surface>widget</vee.surface>\necho hi\n"
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        let plugin = DiscoveredPlugin(
            path: path,
            id: PluginID(path: path),
            filename: PluginFilename("slow.sh"),
            isExecutable: true
        )
        let runtime = PluginRuntime(executor: PluginExecutor(runner: runner, baseEnvironment: [:]))
        let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: dir.path, runtime: runtime, baseEnvironment: [:])
        return (coordinator, dir)
    }

    @MainActor
    func testStopCancelsInFlightMenuRefreshRunner() async throws {
        let runner = SlowRunner()
        let (coordinator, dir) = try makeCoordinator(runner: runner)
        defer { try? FileManager.default.removeItem(at: dir) }

        coordinator.forceRefresh()

        let startDeadline = Date().addingTimeInterval(2)
        while runner.startedCount == 0, Date() < startDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(runner.startedCount, 1)

        coordinator.stop()

        let cancelDeadline = Date().addingTimeInterval(3)
        while !runner.observedCancelled, Date() < cancelDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(runner.observedCancelled, "stop() must cancel the in-flight refresh's Task so the runner (and, in production, the real subprocess) actually stops")

        // No further runs after stop() either.
        coordinator.forceRefresh()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(runner.startedCount, 1, "no new run should start after stop()")
    }

    /// Same guard, the widget-mode cadence: `.both`/`.widget` plugins refresh
    /// on an independent `refreshWidget()` Task, which needed the identical
    /// fix (`refreshWidgetTask`).
    @MainActor
    func testStopCancelsInFlightWidgetRefreshRunner() async throws {
        let runner = SlowRunner()
        let (coordinator, dir) = try makeCoordinator(runner: runner)
        defer { try? FileManager.default.removeItem(at: dir) }

        coordinator.forceRefreshWidget()

        let startDeadline = Date().addingTimeInterval(2)
        while runner.startedCount == 0, Date() < startDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(runner.startedCount, 1)

        coordinator.stop()

        let cancelDeadline = Date().addingTimeInterval(3)
        while !runner.observedCancelled, Date() < cancelDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(runner.observedCancelled, "stop() must cancel the in-flight widget refresh's Task too")
    }
}

/// Regression: two plugins declaring the same `<vee.shortcut>` used to fail
/// silently — `GlobalHotKeys.shared.register` returns `nil` for the second
/// registration (the combo is already claimed), but that was only ever
/// reflected in the per-plugin Settings hotkey status, never in
/// `lastError`/the Plugin Manager's error badge that the row already renders.
///
/// Exercises the real Carbon `RegisterEventHotKey` (there is no seam to fake
/// it through — `GlobalHotKeys.shared` is a hardcoded singleton, deliberately
/// not touched here to keep this fix minimal), with an obscure four-modifier
/// combo unlikely to collide with anything else running. Skips (rather than
/// fails) on an environment that can't register a global hotkey at all, e.g.
/// a locked-down CI sandbox, so it never reports a false failure there.
final class PluginCoordinatorDuplicateHotkeyTests: XCTestCase {
    private struct NoopRunner: ProcessRunning, @unchecked Sendable {
        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            ProcessOutcome(standardOutput: "", standardError: "", exitCode: 0, timedOut: false)
        }
    }

    @MainActor
    private func makeCoordinator(name: String, combo: String) throws -> (PluginCoordinator, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-hotkey-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        let source = "#!/bin/bash\n# <vee.surface>widget</vee.surface>\n# <vee.shortcut>\(combo)</vee.shortcut>\necho hi\n"
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        let plugin = DiscoveredPlugin(path: path, id: PluginID(path: path), filename: PluginFilename(name), isExecutable: true)
        let runtime = PluginRuntime(executor: PluginExecutor(runner: NoopRunner(), baseEnvironment: [:]))
        let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: dir.path, runtime: runtime, baseEnvironment: [:])
        return (coordinator, dir)
    }

    @MainActor
    func testDuplicateShortcutAcrossPluginsSurfacesOnTheSecondPlugin() throws {
        let combo = "ctrl+opt+shift+cmd+f12"
        let (first, dir1) = try makeCoordinator(name: "first.sh", combo: combo)
        let (second, dir2) = try makeCoordinator(name: "second.sh", combo: combo)
        defer {
            first.stop()
            second.stop()
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }

        first.start()
        second.start()

        try XCTSkipIf(first.displayError != nil, "this environment does not support registering a global hotkey at all — skipping")
        XCTAssertNil(first.displayError, "the plugin that claims the hotkey first must register cleanly")
        XCTAssertNotNil(second.displayError, "the second plugin's colliding <vee.shortcut> must be surfaced, not dropped silently")
    }
}
