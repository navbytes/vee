import Foundation
import XCTest
@testable import FluidHostCore
import FluidProtocol

final class BackoffPolicyTests: XCTestCase {
    func testDelaysGrowThenGiveUp() {
        let policy = BackoffPolicy(initialDelay: 1, multiplier: 2, maxDelay: 5, maxConsecutiveFailures: 4)
        XCTAssertNil(policy.delay(afterFailures: 0))
        XCTAssertEqual(policy.delay(afterFailures: 1), 1)
        XCTAssertEqual(policy.delay(afterFailures: 2), 2)
        XCTAssertEqual(policy.delay(afterFailures: 3), 4)
        XCTAssertEqual(policy.delay(afterFailures: 4), 5, "capped at maxDelay")
        XCTAssertNil(policy.delay(afterFailures: 5), "gives up after maxConsecutiveFailures")
    }
}

final class SandboxEntitlementsTests: XCTestCase {
    func testCapabilitiesMapToEntitlements() throws {
        let quiet = Manifest(id: "a.quiet", name: "Quiet")
        XCTAssertEqual(SandboxEntitlements.entitlements(for: quiet), ["com.apple.security.app-sandbox": true])
        XCTAssertEqual(SandboxEntitlements.summary(for: quiet), ["No network, files, commands or secrets."])

        let busy = Manifest(id: "a.busy", name: "Busy", capabilities: [.network("api.github.com"), .files(paths: ["~/Notes"]), .secret(name: "TOKEN")])
        XCTAssertEqual(SandboxEntitlements.entitlements(for: busy), [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.network.client": true,
            "com.apple.security.files.user-selected.read-write": true,
        ])
        let plist = try SandboxEntitlements.propertyList(for: busy)
        let decoded = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Bool]
        XCTAssertEqual(decoded, SandboxEntitlements.entitlements(for: busy))
        XCTAssertEqual(SandboxEntitlements.summary(for: busy).first, "Connects to api.github.com")
    }
}

final class TreeTextRendererTests: XCTestCase {
    func testRendersControlsWithTheirActionIDs() {
        let tree = ViewNode.stack(axis: .vertical, children: [
            .text("Clock", style: .title),
            .progress(value: 0.5, label: "Day"),
            .toggle(title: "24h", isOn: true, action: "toggle/24h"),
            .list(searchable: true, children: [
                .row(RowNode(key: "1", title: "Fix bug", subtitle: "vee #1", accessories: [.badge("Ready", role: .success)], actions: [ActionRef(id: "row/1/Open", title: "Open", shortcut: "cmd+return")])),
            ]),
            .button(title: "Clear", role: .critical, action: "button/Clear"),
        ])
        XCTAssertEqual(TreeTextRenderer.render(tree), """
        # Clock
        Day [#####.....] 50%
        [x] 24h  {toggle/24h}
        List (searchable)
          * Fix bug - vee #1  [Ready] (success)  <Open (cmd+return)  {row/1/Open}>
        (Clear) (critical)  {button/Clear}
        """)
    }
}

final class PluginBuilderTests: XCTestCase {
    func testParsesCompilerDiagnostics() {
        let log = """
        Building for production...
        /tmp/x/Sources/Plugin/Plugin.swift:12:9: error: cannot find 'foo' in scope
        /tmp/x/Sources/Plugin/Plugin.swift:12:9: error: cannot find 'foo' in scope
        /tmp/x/Sources/Plugin/Plugin.swift:3:1: warning: unused variable 'x'
        error: fatalError
        """
        let diagnostics = PluginBuilder.parseDiagnostics(log)
        XCTAssertEqual(diagnostics, [
            BuildDiagnostic(file: "/tmp/x/Sources/Plugin/Plugin.swift", line: 12, column: 9, severity: .error, message: "cannot find 'foo' in scope"),
            BuildDiagnostic(file: "/tmp/x/Sources/Plugin/Plugin.swift", line: 3, column: 1, severity: .warning, message: "unused variable 'x'"),
        ])
    }

    func testCacheKeysAndNames() {
        XCTAssertEqual(PluginBuilder.cacheKey(Data("a".utf8)), PluginBuilder.cacheKey(Data("a".utf8)))
        XCTAssertNotEqual(PluginBuilder.cacheKey(Data("a".utf8)), PluginBuilder.cacheKey(Data("b".utf8)))
        XCTAssertEqual(PluginBuilder.sanitizedName("my plugin.v2"), "my-plugin-v2")
        XCTAssertTrue(PluginBuilder.manifest(fluidPackage: URL(fileURLWithPath: "/src/Fluid")).contains(#".package(path: "/src/Fluid")"#))
    }

    /// Compiles real plugins with SwiftPM. Slow (it builds FluidKit), so it
    /// runs only when FLUID_BUILD_TESTS=1.
    func testBuildsAPluginAndMapsErrorsBackToItsSource() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FLUID_BUILD_TESTS"] == "1", "set FLUID_BUILD_TESTS=1 to compile plugins")
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("fluid-build-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let builder = PluginBuilder(fluidPackage: package, cacheRoot: work.appendingPathComponent("cache"), configuration: "debug")

        let good = work.appendingPathComponent("Hello.swift")
        try """
        import FluidKit
        @main final class Hello: FluidPlugin {
            static let manifest = Manifest(id: "test.hello", name: "Hello")
            var menuBar: ViewContent { Text("hello") }
        }
        """.write(to: good, atomically: true, encoding: .utf8)
        let first = try builder.build(source: good)
        XCTAssertFalse(first.cached)
        XCTAssertEqual(try PluginProcess.readManifest(executable: first.binary).id, "test.hello")
        XCTAssertTrue(try builder.build(source: good).cached)

        let bad = work.appendingPathComponent("Broken.swift")
        try """
        import FluidKit
        @main final class Broken: FluidPlugin {
            static let manifest = Manifest(id: "test.broken", name: "Broken")
            var menuBar: ViewContent { Text(missingValue) }
        }
        """.write(to: bad, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try builder.build(source: bad)) { error in
            let diagnostics = (error as? PluginBuilder.Failure)?.diagnostics ?? []
            XCTAssertTrue(diagnostics.contains { $0.file == bad.path && $0.line == 4 && $0.severity == .error }, "\(diagnostics)")
        }
    }
}

/// Drives the real example and fixture plugins as child processes.
final class PluginSupervisorTests: XCTestCase {
    static var productsDirectory: URL {
        #if os(macOS)
        if let bundle = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        #endif
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }

    static func helper(_ name: String) -> URL { productsDirectory.appendingPathComponent(name) }

    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ update: PluginSupervisor.Update) {
            if case .log(_, let line) = update { lock.withLock { lines.append(line) } }
        }
        var all: [String] { lock.withLock { lines } }
    }

    func waitUntil(_ timeout: Double = 15, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    func testReadsTheManifestFromTheHelper() throws {
        let manifest = try PluginProcess.readManifest(executable: Self.helper("ClockPlugin"))
        XCTAssertEqual(manifest.id, "dev.fluid.example.clock")
        XCTAssertEqual(manifest.refreshInterval, 1)
    }

    func testRendersBothSurfacesAndHandlesEvents() async throws {
        let log = Log()
        let supervisor = try PluginSupervisor.make(executable: Self.helper("FixturePlugin"), onUpdate: log.add)
        await supervisor.start()
        let startup = supervisor.startupMessageCount
        let started = await waitUntil { await supervisor.settledCount >= startup }
        XCTAssertTrue(started)
        let running = await supervisor.state
        XCTAssertEqual(running, .running)
        var views = await supervisor.views
        XCTAssertEqual(views[.menuBar], .text("count 0", style: .body, role: .primary))
        XCTAssertNotNil(views[.panel])

        await supervisor.event("button/Increment")
        await supervisor.event("button/Print")
        let handled = await waitUntil { await supervisor.settledCount >= startup + 2 }
        XCTAssertTrue(handled)
        views = await supervisor.views
        XCTAssertEqual(views[.menuBar], .text("count 11", style: .body, role: .primary), "a stray print must not corrupt the protocol")
        let sawPrint = await waitUntil(5) { log.all.contains("stray output from plugin code") }
        XCTAssertTrue(sawPrint, "plugin stdout is redirected to the log: \(log.all)")

        await supervisor.stop()
        let stopped = await supervisor.state
        XCTAssertEqual(stopped, .stopped)
    }

    func testRestartsACrashedPluginAndKeepsTheLastTree() async throws {
        let fast = BackoffPolicy(initialDelay: 0.05, multiplier: 1, maxDelay: 0.05, maxConsecutiveFailures: 3)
        let supervisor = try PluginSupervisor.make(executable: Self.helper("FixturePlugin"), policy: fast)
        await supervisor.start()
        let startup = supervisor.startupMessageCount
        _ = await waitUntil { await supervisor.settledCount >= startup }

        await supervisor.event("button/Increment")
        _ = await waitUntil { await supervisor.views[.menuBar] == .text("count 1", style: .body, role: .primary) }
        await supervisor.event("button/Crash")
        let restarted = await waitUntil { await supervisor.restarts == 1 }
        XCTAssertTrue(restarted)
        let back = await waitUntil {
            let state = await supervisor.state
            let settled = await supervisor.settledCount
            return state == .running && settled >= startup
        }
        XCTAssertTrue(back)
        let views = await supervisor.views
        XCTAssertEqual(views[.menuBar], .text("count 0", style: .body, role: .primary), "a restarted plugin starts from fresh state and re-renders")
        await supervisor.stop()
    }

    func testGivesUpAfterTooManyCrashes() async throws {
        let fast = BackoffPolicy(initialDelay: 0.05, multiplier: 1, maxDelay: 0.05, maxConsecutiveFailures: 2)
        let supervisor = try PluginSupervisor.make(executable: Self.helper("FixturePlugin"), policy: fast)
        await supervisor.start()
        for _ in 0..<3 {
            _ = await waitUntil { await supervisor.state == .running }
            await supervisor.event("button/Crash")
            _ = await waitUntil(5) {
                switch await supervisor.state {
                case .restarting, .failed: return true
                default: return false
                }
            }
        }
        let failed = await waitUntil {
            if case .failed = await supervisor.state { return true }
            return false
        }
        XCTAssertTrue(failed)
        await supervisor.stop()
    }
}
