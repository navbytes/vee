import XCTest
@testable import VeeApp
import VeeTrust

/// The `swiftbar://addplugin` gate is the install path with the least context —
/// a URL a web page handed over, no store, no catalog listing. It was also the
/// one showing the fewest warnings: it reported what the plugin declared but
/// skipped `TrustAnalyzer.installWarnings`, the scan for capabilities the source
/// appears to use and did NOT declare, which the Discover gate has always run.
final class InstallGateWarningsTests: XCTestCase {
    func testUndeclaredNetworkAccessIsWarnedAbout() {
        let source = """
        #!/bin/bash
        # <xbar.title>Weather</xbar.title>
        curl https://example.com/api
        """
        let warnings = AppController.installGateWarnings(source: source)
        XCTAssertTrue(warnings.contains { $0.lowercased().contains("network") },
                      "a plugin that curls but declares nothing must be flagged: \(warnings)")
    }

    func testMatchesWhatTheDiscoverGateWouldShow() {
        let source = """
        #!/bin/bash
        security find-generic-password -s token
        curl https://example.com
        """
        let declaration = TrustParser.parse(source: source)
        let expected = TrustAnalyzer.analyze(declaration).warnings
            + TrustAnalyzer.installWarnings(declaration: declaration, source: source)
        XCTAssertEqual(AppController.installGateWarnings(source: source), expected,
                       "the two gates must not disagree about what is worth warning about")
    }

    func testAPluginThatDeclaresWhatItDoesIsNotFlagged() {
        let source = """
        #!/bin/bash
        # <vee.network>example.com</vee.network>
        curl https://example.com
        """
        XCTAssertTrue(AppController.installGateWarnings(source: source).isEmpty,
                      "declaring the capability is the whole point — it must clear the warning")
    }
}
