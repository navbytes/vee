import XCTest
import AppKit
@testable import VeeApp
import VeeCore
import VeeRuntime

/// Regression coverage for the per-plugin widget-card **Refresh** action.
///
/// A card's `refresh` button must re-run the plugin on its *widget* surface
/// (`VEE_TARGET=widget`) so the card itself updates — not the menu surface.
/// The menu-mode `refresh()` path publishes nothing for a `.both`/`.widget`
/// plugin (`publishScrape` is gated to `.menu`), so routing the button through
/// `forceRefresh()` (menu) left the card stale until the next widget-cadence
/// tick. `AppController.widgetActionRequestFired()` must therefore route a
/// `.refresh` request through `forceRefreshWidget()`.
///
/// Uses a `.widget`-surface plugin so the coordinator builds no `NSStatusItem`
/// (nothing to render into a menu bar during a unit test), and a fake
/// `ProcessRunning` that records each run's injected `VEE_TARGET`.
final class WidgetActionRefreshTests: XCTestCase {
    /// Records the `VEE_TARGET` of every run and returns a canned card on stdout.
    private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
        let stdout: String
        private let lock = NSLock()
        private var _targets: [String] = []
        private var _onRun: (@Sendable () -> Void)?

        init(stdout: String) { self.stdout = stdout }

        var targets: [String] { lock.withLock { _targets } }

        func setOnRun(_ cb: @escaping @Sendable () -> Void) { lock.withLock { _onRun = cb } }

        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            let cb: (@Sendable () -> Void)? = lock.withLock {
                _targets.append(invocation.environment["VEE_TARGET"] ?? "<none>")
                return _onRun
            }
            cb?()
            return ProcessOutcome(standardOutput: stdout, standardError: "", exitCode: 0, timedOut: false)
        }
    }

    private static let card = #"{"vee_widget":1,"template":"stat","title":"Revenue","value":"$1"}"#

    /// Writes a widget-only plugin to a temp dir and returns (coordinator, runner, dir).
    @MainActor
    private func makeCoordinator() throws -> (PluginCoordinator, RecordingRunner, URL) {
        // `PluginsDirectory.context` reads `NSApp.effectiveAppearance`; ensure a
        // shared application exists so it isn't a nil implicit-unwrap in the
        // headless test process.
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("revenue.sh").path
        let source = "#!/bin/bash\n# <vee.surface>widget</vee.surface>\necho '\(Self.card)'\n"
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        let plugin = DiscoveredPlugin(
            path: path,
            id: PluginID(path: path),
            filename: PluginFilename("revenue.sh"),
            isExecutable: true
        )
        let runner = RecordingRunner(stdout: Self.card)
        let runtime = PluginRuntime(executor: PluginExecutor(runner: runner, baseEnvironment: [:]))
        let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: dir.path, runtime: runtime, baseEnvironment: [:])
        return (coordinator, runner, dir)
    }

    /// The bug fix: the widget refresh action runs the plugin in *widget* mode.
    @MainActor
    func testForceRefreshWidgetRunsWidgetMode() throws {
        let (coordinator, runner, dir) = try makeCoordinator()
        defer { try? FileManager.default.removeItem(at: dir) }

        let ran = expectation(description: "widget-mode run")
        runner.setOnRun { ran.fulfill() }
        coordinator.forceRefreshWidget()
        wait(for: [ran], timeout: 5)

        XCTAssertEqual(runner.targets.last, "widget",
                       "a widget-card Refresh must re-run the plugin with VEE_TARGET=widget")
    }

    /// Guards the distinction: the plain refresh path stays menu-mode, so this
    /// fix doesn't accidentally turn every refresh into a widget run.
    @MainActor
    func testForceRefreshRunsMenuMode() throws {
        let (coordinator, runner, dir) = try makeCoordinator()
        defer { try? FileManager.default.removeItem(at: dir) }

        let ran = expectation(description: "menu-mode run")
        runner.setOnRun { ran.fulfill() }
        coordinator.forceRefresh()
        wait(for: [ran], timeout: 5)

        XCTAssertEqual(runner.targets.last, "menu",
                       "forceRefresh() must stay on the menu surface (VEE_TARGET=menu)")
    }
}
