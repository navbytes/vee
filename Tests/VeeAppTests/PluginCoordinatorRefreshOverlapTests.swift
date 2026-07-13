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
