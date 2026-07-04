import XCTest
@testable import VeeTrust

final class TrustParserTests: XCTestCase {
    func testParsesTagsAndInfersCapabilities() {
        let src = """
        #!/bin/bash
        # <vee.network>api.github.com, *.example.com</vee.network>
        # <vee.filesystem.read>~/Documents</vee.filesystem.read>
        # <vee.secrets>GITHUB_TOKEN</vee.secrets>
        # <vee.exec>git, curl</vee.exec>
        """
        let d = TrustParser.parse(source: src)
        XCTAssertEqual(d.networkDomains, ["api.github.com", "*.example.com"])
        XCTAssertEqual(d.fsReadPaths, ["~/Documents"])
        XCTAssertEqual(d.secretsUsed, ["GITHUB_TOKEN"])
        XCTAssertEqual(d.externalBinaries, ["git", "curl"])
        // Capabilities inferred from the detail tags.
        XCTAssertEqual(d.capabilities, [.network, .filesystem, .secrets, .exec])
    }

    func testExplicitCapabilities() {
        let d = TrustParser.parse(source: "# <vee.capabilities>clipboard, notifications</vee.capabilities>")
        XCTAssertEqual(d.capabilities, [.clipboard, .notifications])
    }

    func testEmptyWhenNoTags() {
        XCTAssertTrue(TrustParser.parse(source: "echo hi").isEmpty)
    }
}

final class TrustAnalyzerTests: XCTestCase {
    func testUndeclared() {
        let s = TrustAnalyzer.analyze(TrustDeclaration())
        XCTAssertEqual(s.level, .undeclared)
        XCTAssertTrue(s.badges.isEmpty)
    }

    func testNetworkWithoutDomainsIsPartialAndWarns() {
        let d = TrustDeclaration(capabilities: [.network])
        let s = TrustAnalyzer.analyze(d)
        XCTAssertEqual(s.level, .partial)
        XCTAssertEqual(s.badges.first?.severity, .high)
        XCTAssertTrue(s.warnings.contains { $0.contains("no domains") })
    }

    func testSpecificDomainsAreLowSeverity() {
        let d = TrustDeclaration(capabilities: [.network], networkDomains: ["api.github.com"])
        let s = TrustAnalyzer.analyze(d)
        XCTAssertEqual(s.level, .declared)
        XCTAssertEqual(s.badges.first?.severity, .low)
    }

    func testWildcardDomainWarns() {
        let d = TrustParser.parse(source: "# <vee.network>*.example.com</vee.network>")
        let s = TrustAnalyzer.analyze(d)
        XCTAssertTrue(s.warnings.contains { $0.contains("wildcard") })
        XCTAssertEqual(s.badges.first?.severity, .medium)
    }

    func testBroadWriteIsHighSeverity() {
        let d = TrustDeclaration(capabilities: [.filesystem], fsWritePaths: ["~"])
        let s = TrustAnalyzer.analyze(d)
        let fs = s.badges.first { $0.capability == .filesystem }
        XCTAssertEqual(fs?.severity, .high)
        XCTAssertTrue(s.warnings.contains { $0.contains("broad") })
    }
}

final class SourceScanTests: XCTestCase {
    func testDetectsNetworkAndSecrets() {
        let source = "#!/bin/bash\nTOKEN=$API_TOKEN\ncurl https://api.github.com\n"
        let caps = TrustAnalyzer.detectedCapabilities(inSource: source)
        XCTAssertTrue(caps.contains(.network))
        XCTAssertTrue(caps.contains(.secrets))
    }

    func testWarnsOnUndeclaredNetwork() {
        let source = "curl https://api.example.com\n"
        let warnings = TrustAnalyzer.installWarnings(declaration: TrustDeclaration(), source: source)
        XCTAssertTrue(warnings.contains { $0.contains("network") })
    }

    func testNoWarningWhenDeclared() {
        let source = "curl https://api.example.com\n"
        let declared = TrustDeclaration(capabilities: [.network], networkDomains: ["api.example.com"])
        let warnings = TrustAnalyzer.installWarnings(declaration: declared, source: source)
        XCTAssertTrue(warnings.isEmpty)
    }
}
