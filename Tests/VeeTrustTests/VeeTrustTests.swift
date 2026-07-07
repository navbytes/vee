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

final class TrustDiffTests: XCTestCase {
    func testIdenticalSourcesHaveNoChanges() {
        let src = """
        # <vee.network>api.github.com</vee.network>
        # <vee.exec>git</vee.exec>
        """
        let diff = TrustDiff.between(old: src, new: src)
        XCTAssertFalse(diff.hasChanges)
        XCTAssertTrue(diff.isEmpty)
        XCTAssertTrue(diff.summaryLines.isEmpty)
    }

    func testAddedOnlyDomain() {
        let old = "# <vee.network>api.github.com</vee.network>"
        let new = """
        # <vee.network>api.github.com, evil.tld</vee.network>
        """
        let diff = TrustDiff.between(old: old, new: new)
        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.networkDomains.added, ["evil.tld"])
        XCTAssertTrue(diff.networkDomains.removed.isEmpty)
        XCTAssertTrue(diff.summaryLines.contains("adds domain: evil.tld"))
    }

    func testRemovedOnlyExec() {
        let old = "# <vee.exec>git, curl</vee.exec>"
        let new = "# <vee.exec>git</vee.exec>"
        let diff = TrustDiff.between(old: old, new: new)
        XCTAssertEqual(diff.externalBinaries.removed, ["curl"])
        XCTAssertTrue(diff.externalBinaries.added.isEmpty)
        XCTAssertTrue(diff.summaryLines.contains("removes exec: curl"))
    }

    func testMixedFilesystemAndCapabilityChanges() {
        let old = """
        # <vee.filesystem.read>~/Documents</vee.filesystem.read>
        # <vee.filesystem.write>~/Library/Application Support/Vee</vee.filesystem.write>
        # <vee.secrets>GITHUB_TOKEN</vee.secrets>
        """
        let new = """
        # <vee.filesystem.read>~/Documents</vee.filesystem.read>
        # <vee.filesystem.write>~</vee.filesystem.write>
        # <vee.network>evil.tld</vee.network>
        """
        let diff = TrustDiff.between(old: old, new: new)
        // filesystem.write path swapped, read unchanged.
        XCTAssertEqual(diff.fsWritePaths.added, ["~"])
        XCTAssertEqual(diff.fsWritePaths.removed, ["~/Library/Application Support/Vee"])
        XCTAssertTrue(diff.fsReadPaths.added.isEmpty)
        XCTAssertTrue(diff.fsReadPaths.removed.isEmpty)
        // secrets removed, network added.
        XCTAssertEqual(diff.secretsUsed.removed, ["GITHUB_TOKEN"])
        XCTAssertEqual(diff.networkDomains.added, ["evil.tld"])
        // capability dimension reflects network added and secrets removed.
        XCTAssertTrue(diff.capabilities.added.contains(.network))
        XCTAssertTrue(diff.capabilities.removed.contains(.secrets))
    }

    func testDetectedCapabilitiesFoldIntoDiff() {
        // Neither source declares network, but the new one uses curl — the
        // static scan should surface network as an added capability.
        let old = "#!/bin/bash\necho hi\n"
        let new = "#!/bin/bash\ncurl https://evil.tld\n"
        let diff = TrustDiff.between(old: old, new: new)
        XCTAssertTrue(diff.capabilities.added.contains(.network))
        XCTAssertTrue(diff.hasChanges)
        XCTAssertTrue(diff.summaryLines.contains("adds capability: network"))
    }

    func testDeclarationBasedDiff() {
        let old = TrustDeclaration(capabilities: [.exec], externalBinaries: ["git"])
        let new = TrustDeclaration(capabilities: [.exec, .network], networkDomains: ["evil.tld"], externalBinaries: ["git"])
        let diff = TrustDiff.between(old: old, new: new)
        XCTAssertEqual(diff.capabilities.added, [.network])
        XCTAssertTrue(diff.capabilities.removed.isEmpty)
        XCTAssertEqual(diff.networkDomains.added, ["evil.tld"])
        XCTAssertTrue(diff.externalBinaries.hasChanges == false)
    }

    func testSummaryLinesAreSortedAndDeterministic() {
        let old = "# <vee.network>b.tld</vee.network>"
        let new = "# <vee.network>a.tld, c.tld</vee.network>"
        let diff = TrustDiff.between(old: old, new: new)
        // Additions sorted, then removals.
        XCTAssertEqual(diff.networkDomains.added, ["a.tld", "c.tld"])
        XCTAssertEqual(diff.networkDomains.removed, ["b.tld"])
    }

    func testSetDiffNormalisesOrderAndDuplicates() {
        let d = TrustSetDiff<String>.between(old: ["a", "a", "b"], new: ["b", "c", "c"])
        XCTAssertEqual(d.added, ["c"])
        XCTAssertEqual(d.removed, ["a"])
    }

    func testStructuredChangesCarryDirectionAndRisk() {
        let old = TrustDeclaration(capabilities: [.exec], externalBinaries: ["git"])
        let new = TrustDeclaration(
            capabilities: [.exec, .network],
            networkDomains: ["evil.tld"],
            externalBinaries: []
        )
        let changes = TrustDiff.between(old: old, new: new).changes

        // An added capability materially widens reach → elevated.
        let addedCap = changes.first { $0.noun == "capability" && $0.direction == .added }
        XCTAssertEqual(addedCap?.item, "network")
        XCTAssertEqual(addedCap?.isElevated, true)

        // A new domain on an already-networked plugin is not elevated.
        let addedDomain = changes.first { $0.noun == "domain" }
        XCTAssertEqual(addedDomain?.direction, .added)
        XCTAssertEqual(addedDomain?.isElevated, false)

        // A removal is never elevated.
        let removedExec = changes.first { $0.noun == "exec" }
        XCTAssertEqual(removedExec?.direction, .removed)
        XCTAssertEqual(removedExec?.isElevated, false)
    }

    func testStructuredChangesStayInSyncWithSummaryLines() {
        let old = "# <vee.filesystem.write>~/x</vee.filesystem.write>"
        let new = "# <vee.filesystem.write>~</vee.filesystem.write>\n# <vee.secrets>TOKEN</vee.secrets>"
        let diff = TrustDiff.between(old: old, new: new)
        // summaryLines is now derived from changes, so they must match 1:1.
        let rebuilt = diff.changes.map {
            "\($0.direction == .added ? "adds" : "removes") \($0.noun): \($0.item)"
        }
        XCTAssertEqual(rebuilt, diff.summaryLines)
        // An added filesystem-write path is elevated.
        XCTAssertEqual(diff.changes.first { $0.noun == "filesystem write" && $0.direction == .added }?.isElevated, true)
    }
}
