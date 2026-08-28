import XCTest
@testable import VeeApp
import VeeCore
import VeePluginFormat
import VeeRuntime

/// A clicked menu action must run in the same plugin context a render runs in.
///
/// Renders go through `PluginExecutor`, which merges `EnvironmentBuilder`'s
/// `SWIFTBAR_*`/`VEE_*` variables over the inherited environment. Clicked
/// actions went through `AppActionDispatcher` with the *bare* inherited
/// environment, so the two passes disagreed about every path variable.
///
/// The concrete failure: a plugin that keeps session state in
/// `$SWIFTBAR_PLUGIN_DATA_PATH` (with the documented `$TMPDIR` fallback) wrote
/// it from a click — where the variable was unset, so the fallback won — and
/// looked for it at render, where the variable *was* set. The state was always
/// in the directory the other half wasn't reading, so a session started from
/// the menu read back as "not running", and the plugin's own child process
/// showed up as an untracked stray.
final class ActionEnvironmentTests: XCTestCase {
    private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _invocations: [ProcessInvocation] = []
        private var _onRun: (@Sendable () -> Void)?

        var invocations: [ProcessInvocation] { lock.withLock { _invocations } }

        func setOnRun(_ cb: @escaping @Sendable () -> Void) { lock.withLock { _onRun = cb } }

        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            let cb: (@Sendable () -> Void)? = lock.withLock {
                _invocations.append(invocation)
                return _onRun
            }
            cb?()
            return ProcessOutcome(standardOutput: "", standardError: "", exitCode: 0, timedOut: false)
        }
    }

    /// Uses a `.widget`-surface plugin so the coordinator builds no
    /// `NSStatusItem` — the safe construction `WidgetActionRefreshTests`
    /// established (never touches `NSApplication.shared`).
    @MainActor
    private func makeCoordinator() throws -> (PluginCoordinator, RecordingRunner, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-actionenv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("stateful.sh").path
        let source = "#!/bin/bash\n# <vee.surface>widget</vee.surface>\necho hi\n"
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        let plugin = DiscoveredPlugin(
            path: path,
            id: PluginID(path: path),
            filename: PluginFilename("stateful.sh"),
            isExecutable: true
        )
        let runner = RecordingRunner()
        let runtime = PluginRuntime(executor: PluginExecutor(runner: runner, baseEnvironment: [:]))
        let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: dir.path, runtime: runtime, baseEnvironment: [:])
        return (coordinator, runner, dir)
    }

    /// The regression: every variable a plugin can use to locate its own state
    /// must resolve identically whether the plugin was invoked to render or by
    /// a click. Compared against a *real* render's environment rather than
    /// hardcoded paths, so the two can never drift apart again.
    @MainActor
    func testActionEnvironmentMatchesRenderEnvironment() throws {
        let (coordinator, runner, dir) = try makeCoordinator()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rendered = expectation(description: "render")
        runner.setOnRun { rendered.fulfill() }
        coordinator.forceRefresh()
        wait(for: [rendered], timeout: 5)

        let renderEnv = try XCTUnwrap(runner.invocations.last?.environment)
        let actionEnv = coordinator.actionEnvironment()

        for key in ["SWIFTBAR_PLUGIN_DATA_PATH", "SWIFTBAR_PLUGIN_CACHE_PATH", "SWIFTBAR_PLUGINS_PATH", "SWIFTBAR_PLUGIN_PATH", "VEE_PLUGIN_PATH", "VEE_PLUGIN_ID"] {
            let renderValue = renderEnv[key] ?? ""
            XCTAssertFalse(renderValue.isEmpty, "\(key) should be injected for a render")
            XCTAssertEqual(actionEnv[key], renderValue,
                           "a clicked action must see the same \(key) a render sees, or plugin state written by a click lands where the render never looks")
        }
    }

    /// The dispatcher must ask for the environment on every click rather than
    /// capturing one at construction. The coordinator builds it once per
    /// plugin and lives for the whole app session, while the context keeps
    /// moving underneath: `<xbar.var>` preferences change whenever the user
    /// edits plugin settings, and dark mode flips. A snapshot would pin an
    /// action to whatever was true at launch.
    @MainActor
    func testDispatcherResolvesEnvironmentOnEveryClick() throws {
        let runner = RecordingRunner()
        var token = "first"
        let dispatcher = AppActionDispatcher(
            runner: runner,
            environment: { ["VEE_TEST_TOKEN": token] },
            onRefresh: {}
        )

        // The `---` matters: lines before it are the status-item title, so a
        // clickable body row has to come after one.
        let parsed = OutputParser.parse("Title\n---\nGo | shell=/bin/echo param1=hi")
        guard case .item(let item)? = parsed.body.first else {
            return XCTFail("fixture should parse to one clickable item")
        }

        let firstRun = expectation(description: "first click")
        runner.setOnRun { firstRun.fulfill() }
        dispatcher.perform(item)
        wait(for: [firstRun], timeout: 5)

        token = "second"
        let secondRun = expectation(description: "second click")
        runner.setOnRun { secondRun.fulfill() }
        dispatcher.perform(item)
        wait(for: [secondRun], timeout: 5)

        XCTAssertEqual(runner.invocations.map { $0.environment["VEE_TEST_TOKEN"] }, ["first", "second"],
                       "each click must resolve the environment afresh, not reuse one captured at construction")
    }
}
