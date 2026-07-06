import XCTest
import VeePluginFormat
@testable import VeeCLI

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

    func testTsContentsParseWithNoErrorDiagnostics() {
        assertClean(.ts, trust: ["network", "secrets"])
    }

    func testPyContentsParseWithNoErrorDiagnostics() {
        assertClean(.py, trust: ["exec", "filesystem"])
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
}
