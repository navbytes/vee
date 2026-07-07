import XCTest
@testable import VeeCore

final class PluginFilenameTests: XCTestCase {
    func testNameIntervalExt() {
        let f = PluginFilename("cpu.10s.sh")
        XCTAssertEqual(f.name, "cpu")
        XCTAssertEqual(f.interval, .seconds(10))
        XCTAssertEqual(f.ext, "sh")
    }

    func testDottedNameIsPreserved() {
        let f = PluginFilename("my.plugin.5m.py")
        XCTAssertEqual(f.name, "my.plugin")
        XCTAssertEqual(f.interval, .minutes(5))
        XCTAssertEqual(f.ext, "py")
    }

    func testNoIntervalToken() {
        let f = PluginFilename("weather.sh")
        XCTAssertEqual(f.name, "weather")
        XCTAssertEqual(f.interval, .manual)
        XCTAssertEqual(f.ext, "sh")
    }

    func testBareNameNoExtension() {
        let f = PluginFilename("notes")
        XCTAssertEqual(f.name, "notes")
        XCTAssertEqual(f.interval, .manual)
        XCTAssertEqual(f.ext, "")
    }

    func testIntervalTokenWithoutNameIsTreatedAsName() {
        // "10s.sh" has no name before the token → name "10s", manual.
        let f = PluginFilename("10s.sh")
        XCTAssertEqual(f.name, "10s")
        XCTAssertEqual(f.interval, .manual)
        XCTAssertEqual(f.ext, "sh")
    }

    func testMillisecondsInterval() {
        XCTAssertEqual(PluginFilename("poll.250ms.sh").interval, .milliseconds(250))
    }

    /// Regression: a `0` interval token fails to parse (RefreshInterval rejects
    /// it to avoid arming a near-zero repeating timer), so the filename must
    /// fall back to the manual/no-interval path — folding the token into the
    /// name — rather than crashing or silently keeping an unsafe interval.
    func testZeroIntervalTokenFallsBackToManual() {
        let f = PluginFilename("cpu.0s.sh")
        XCTAssertEqual(f.name, "cpu.0s")
        XCTAssertEqual(f.interval, .manual)
        XCTAssertEqual(f.ext, "sh")
    }
}
