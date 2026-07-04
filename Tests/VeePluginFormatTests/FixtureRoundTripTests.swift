import XCTest
@testable import VeePluginFormat

/// Parses the golden fixtures produced by the TypeScript SDK (plugins/fixtures)
/// and asserts they round-trip through the Swift parser. This ties the SDK's
/// output to the parser: if either drifts, this fails.
final class FixtureRoundTripTests: XCTestCase {
    private func fixturesDirectory() -> URL {
        // .../Tests/VeePluginFormatTests/FixtureRoundTripTests.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("plugins/fixtures")
    }

    func testCPUFixtureParses() throws {
        let url = fixturesDirectory().appendingPathComponent("cpu.txt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let output = OutputParser.parse(source)

        // Title line with color + SF Symbol.
        XCTAssertEqual(output.titleLines.first?.text, "CPU 12%")
        XCTAssertEqual(output.titleLines.first?.params.color, .named("green"))
        XCTAssertEqual(output.titleLines.first?.params.swiftbar.sfimage, "cpu")

        // Body: item(href) · separator · submenu(Details) · item(refresh)
        let items = output.body.compactMap { node -> MenuItem? in
            if case .item(let i) = node { return i }
            return nil
        }
        XCTAssertEqual(items.map(\.text), ["Top processes", "Details", "Refresh"])
        XCTAssertEqual(items[0].params.href?.absoluteString, "https://example.com/procs")
        XCTAssertEqual(items[1].submenu.compactMap { if case .item(let i) = $0 { return i.text } else { return nil } }, ["Load: 1.20", "Cores: 8"])
        XCTAssertEqual(items[2].params.refresh, true)
        XCTAssertTrue(output.body.contains { if case .separator = $0 { return true } else { return false } })
    }
}
