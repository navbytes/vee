import XCTest
import VeeCore
@testable import VeeRuntime

/// Records the invocation it was handed and returns a canned outcome — lets us
/// test executor/runtime wiring without spawning a process.
actor RecordingProcessRunner: ProcessRunning {
    private(set) var lastInvocation: ProcessInvocation?
    var stub: ProcessOutcome

    init(stub: ProcessOutcome) { self.stub = stub }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
        lastInvocation = invocation
        return stub
    }
}

private func makeContext(pluginPath: String) -> RuntimeEnvironmentContext {
    RuntimeEnvironmentContext(
        pluginPath: pluginPath,
        pluginsDirectory: "/plugins",
        cacheDirectory: "/cache",
        dataDirectory: "/data",
        isDarkMode: true,
        osVersion: (26, 1, 0),
        appVersion: "0.1.0",
        declaredVariables: ["API_TOKEN": "secret"]
    )
}

final class EnvironmentBuilderTests: XCTestCase {
    func testInjectedVariables() {
        let env = EnvironmentBuilder.injected(makeContext(pluginPath: "/plugins/x.5s.sh"))
        XCTAssertEqual(env["XBARDarkMode"], "true")
        XCTAssertEqual(env["OS_APPEARANCE"], "Dark")
        XCTAssertEqual(env["SWIFTBAR"], "1")
        XCTAssertEqual(env["SWIFTBAR_PLUGIN_PATH"], "/plugins/x.5s.sh")
        XCTAssertEqual(env["OS_VERSION_MAJOR"], "26")
        XCTAssertEqual(env["VEE"], "1")
        XCTAssertEqual(env["API_TOKEN"], "secret") // declared var injected
    }

    func testMergeOverridesBase() {
        let base = ["PATH": "/usr/bin", "XBARDarkMode": "stale"]
        let merged = EnvironmentBuilder.merged(base: base, context: makeContext(pluginPath: "/p"))
        XCTAssertEqual(merged["PATH"], "/usr/bin")        // inherited
        XCTAssertEqual(merged["XBARDarkMode"], "true")    // injected wins
    }
}

final class PluginExecutorTests: XCTestCase {
    func testBashWrapByDefault() async throws {
        let runner = RecordingProcessRunner(stub: ProcessOutcome(standardOutput: "", standardError: "", exitCode: 0, timedOut: false))
        let exec = PluginExecutor(runner: runner, baseEnvironment: [:])
        _ = try await exec.run(pluginPath: "/plugins/cpu.5s.sh", context: makeContext(pluginPath: "/plugins/cpu.5s.sh"))
        let inv = await runner.lastInvocation
        XCTAssertEqual(inv?.launchPath, "/bin/bash")
        XCTAssertEqual(inv?.arguments, ["/plugins/cpu.5s.sh"])
        XCTAssertEqual(inv?.workingDirectory, "/plugins")
        XCTAssertEqual(inv?.environment["VEE"], "1")
    }

    func testDirectExecWhenNotBash() async throws {
        let runner = RecordingProcessRunner(stub: ProcessOutcome(standardOutput: "", standardError: "", exitCode: 0, timedOut: false))
        let exec = PluginExecutor(runner: runner, baseEnvironment: [:])
        _ = try await exec.run(pluginPath: "/plugins/w.py", context: makeContext(pluginPath: "/plugins/w.py"), runInBash: false)
        let inv = await runner.lastInvocation
        XCTAssertEqual(inv?.launchPath, "/plugins/w.py")
        XCTAssertEqual(inv?.arguments, [])
    }
}

final class ShebangLaunchTests: XCTestCase {
    private func tempFile(_ contents: String) -> String {
        let path = NSTemporaryDirectory() + "vee-shebang-" + UUID().uuidString
        // Test setup; a write failure should fail the test loudly.
        // swiftlint:disable:next force_try
        try! contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testDirectExecWhenNotBash() {
        let (path, args) = PluginExecutor.launchCommand(pluginPath: "/x/p.sh", runInBash: false)
        XCTAssertEqual(path, "/x/p.sh")
        XCTAssertEqual(args, [])
    }

    func testBashWhenNoShebang() {
        let p = tempFile("echo hi\n"); defer { try? FileManager.default.removeItem(atPath: p) }
        let (path, args) = PluginExecutor.launchCommand(pluginPath: p, runInBash: true)
        XCTAssertEqual(path, "/bin/bash")
        XCTAssertEqual(args, [p])
    }

    func testHonorsShebangInterpreter() {
        // A non-executable .ts/.py plugin with a shebang runs with its interpreter.
        let p = tempFile("#!/usr/bin/env node\nconsole.log('hi')\n"); defer { try? FileManager.default.removeItem(atPath: p) }
        let (path, args) = PluginExecutor.launchCommand(pluginPath: p, runInBash: true)
        XCTAssertEqual(path, "/usr/bin/env")
        XCTAssertEqual(args, ["node", p])
    }
}

final class PluginRuntimeTests: XCTestCase {
    func testRefreshParsesOutput() async throws {
        let stub = ProcessOutcome(standardOutput: "CPU 5%\n---\nDetails | color=red", standardError: "", exitCode: 0, timedOut: false)
        let runtime = PluginRuntime(executor: PluginExecutor(runner: RecordingProcessRunner(stub: stub), baseEnvironment: [:]))
        let result = try await runtime.refresh(pluginPath: "/plugins/cpu.5s.sh", context: makeContext(pluginPath: "/plugins/cpu.5s.sh"))
        XCTAssertEqual(result.output.titleLines.map(\.text), ["CPU 5%"])
        guard case .item(let item)? = result.output.body.first else {
            return XCTFail("expected a menu item")
        }
        XCTAssertEqual(item.params.color, .named("red"))
    }
}

final class RefreshSchedulerTests: XCTestCase {
    func testStrategySelection() {
        XCTAssertEqual(RefreshScheduler.strategy(for: .manual), .none)
        XCTAssertEqual(RefreshScheduler.strategy(for: .cron("* * * * *")), .none)
        XCTAssertEqual(RefreshScheduler.strategy(for: .minutes(10)), .backgroundActivity)
        XCTAssertEqual(RefreshScheduler.strategy(for: .hours(1)), .backgroundActivity)
        if case .highResolutionTimer = RefreshScheduler.strategy(for: .seconds(5)) {} else {
            XCTFail("short interval should use a high-resolution timer")
        }
    }

    func testLeewayClamped() {
        XCTAssertEqual(RefreshScheduler.leeway(forSeconds: 10), 1.5, accuracy: 0.0001)
        XCTAssertEqual(RefreshScheduler.leeway(forSeconds: 0.1), 0.05, accuracy: 0.0001) // floor
        XCTAssertEqual(RefreshScheduler.leeway(forSeconds: 100_000), 60, accuracy: 0.0001) // ceiling
    }
}

final class PluginDiscoveryTests: XCTestCase {
    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "vee-disc-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testEnumerationFiltersAndSorts() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let fm = FileManager.default

        // Two plugins (one executable), a sidecar, a hidden file, a doc file, and a subdir.
        fm.createFile(atPath: dir + "/cpu.5s.sh", contents: Data("x".utf8), attributes: [.posixPermissions: 0o755])
        fm.createFile(atPath: dir + "/weather.1m.py", contents: Data("x".utf8), attributes: [.posixPermissions: 0o644])
        fm.createFile(atPath: dir + "/cpu.5s.sh.vars.json", contents: Data("{}".utf8))
        fm.createFile(atPath: dir + "/README.md", contents: Data("# doc".utf8))
        fm.createFile(atPath: dir + "/.hidden", contents: Data())
        try fm.createDirectory(atPath: dir + "/disabled", withIntermediateDirectories: true)

        // Sidecar, hidden, doc (.md), and subdir are excluded.
        let all = PluginDiscovery.enumerate(directory: dir)
        XCTAssertEqual(all.map { $0.filename.name }, ["cpu", "weather"])
        XCTAssertEqual(all[0].filename.interval, .seconds(5))

        // Non-executable plugins are now included (run bash-wrapped, like SwiftBar).
        let enabled = PluginDiscovery.enabled(directory: dir)
        XCTAssertEqual(enabled.map { $0.filename.name }, ["cpu", "weather"])
        XCTAssertEqual(enabled.first { $0.filename.name == "weather" }?.isExecutable, false)
    }

    func testMissingDirectory() {
        XCTAssertTrue(PluginDiscovery.enumerate(directory: "/no/such/dir/here").isEmpty)
    }
}
