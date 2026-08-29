import XCTest
import VeePluginFormat
import VeeRuntime
@testable import VeeCLI

/// `vee new` never spawns anything; the runner is only there to satisfy the
/// shared `VeeCLI.run` signature.
private struct UnusedRunner: ProcessRunning {
    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
        ProcessOutcome(standardOutput: "", standardError: "", exitCode: 0, timedOut: false)
    }
}

final class ScaffoldTests: XCTestCase {
    func testFilenameIsNameIntervalExt() {
        let (filename, _) = Scaffold.render(lang: .sh, interval: "5s", name: "My Plugin", trust: [])
        XCTAssertEqual(filename, "my-plugin.5s.sh")

        let (ts, _) = Scaffold.render(lang: .ts, interval: "10m", name: "GitHub Status", trust: [])
        XCTAssertEqual(ts, "github-status.10m.ts")

        let (py, _) = Scaffold.render(lang: .py, interval: "1h", name: "disk", trust: [])
        XCTAssertEqual(py, "disk.1h.py")
    }

    func testShContentsParseWithNoErrorDiagnostics() {
        assertClean(.sh, trust: [])
    }

    // TS/Python templates are self-contained: no SDK import, so the only way
    // to prove they're accepted is to actually run them through `vee render`
    // (the same seam the app uses) and check its JSON output parses clean.
    func testTsOutputIsAcceptedByVeeRender() async throws {
        guard ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            .contains(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { throw XCTSkip("node is not installed on this machine") }
        try await assertRenderAccepts(.ts, trust: ["network", "secrets"])
    }

    func testPyOutputIsAcceptedByVeeRender() async throws {
        try await assertRenderAccepts(.py, trust: ["exec", "filesystem"])
    }

    func testHeaderMetadataRoundTrips() {
        let (_, contents) = Scaffold.render(lang: .sh, interval: "10s", name: "Weather", trust: ["network"])
        let meta = HeaderParser.parse(source: contents)
        XCTAssertEqual(meta.title, "Weather")
        XCTAssertEqual(meta.version, "1.0")
    }

    // Feeds the generated file through the output parser and asserts zero error
    // diagnostics (the body must be valid xbar/SwiftBar output).
    private func assertClean(_ lang: Scaffold.Language, trust: [String]) {
        let (_, contents) = Scaffold.render(lang: lang, interval: "10s", name: "Example", trust: trust)
        let parsed = OutputParser.parse(contents)
        let errors = parsed.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "\(lang): \(errors)")
    }

    /// Scaffolds `lang` into a temp dir and runs it through `vee render`,
    /// asserting a clean, non-empty result.
    private func assertRenderAccepts(_ lang: Scaffold.Language, trust: [String]) async throws {
        let dir = NSTemporaryDirectory() + "vee-scaffold-render-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }

        var out = "", err = ""
        var code = await VeeCLI.run(
            ["new", "--lang", lang.rawValue, "--name", "Example", "--interval", "10s", "--out", dir, "--trust", trust.joined(separator: ",")],
            runner: SystemProcessRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 0, err)
        let path = dir + "/example.10s.\(lang.ext)"

        out = ""; err = ""
        code = await VeeCLI.run(["render", path], runner: SystemProcessRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 0, "\(lang): stdout=\(out) stderr=\(err)")
        XCTAssertTrue(out.contains("Example"), "\(lang): \(out)")
    }
    /// `vee new` vendors the SDK beside the plugin and skips it when present
    /// ("Kept … already present"). The plugin file itself had no such guard, so
    /// re-running the command destroyed whatever the author had written into it
    /// — and a scaffold is generated from flags, so nothing of the original is
    /// recoverable from what replaces it.
    func testNewRefusesToOverwriteAnExistingPlugin() async throws {
        let dir = NSTemporaryDirectory() + "vee-new-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }

        var out = "", err = ""
        var code = await VeeCLI.run(["new", "--lang", "sh", "--name", "Clock", "--interval", "10s", "--out", dir],
                                    runner: UnusedRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 0, err)
        let path = dir + "/clock.10s.sh"
        try "# my real work\n".write(toFile: path, atomically: true, encoding: .utf8)

        out = ""; err = ""
        code = await VeeCLI.run(["new", "--lang", "sh", "--name", "Clock", "--interval", "10s", "--out", dir],
                                runner: UnusedRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(err.contains("already exists"), err)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "# my real work\n",
                       "the author's file must be untouched")
    }

    func testNewForceOverwritesDeliberately() async throws {
        let dir = NSTemporaryDirectory() + "vee-new-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/clock.10s.sh"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "# stale\n".write(toFile: path, atomically: true, encoding: .utf8)

        var out = "", err = ""
        let code = await VeeCLI.run(["new", "--lang", "sh", "--name", "Clock", "--interval", "10s", "--out", dir, "--force"],
                                    runner: UnusedRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 0, err)
        XCTAssertNotEqual(try String(contentsOfFile: path, encoding: .utf8), "# stale\n")
    }

}
