import XCTest
@testable import VeeCatalog

final class PluginHashTests: XCTestCase {
    func testKnownSHA256Hex() {
        // The canonical SHA-256 test vector for "abc".
        XCTAssertEqual(
            PluginHash.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testEmptyStringHash() {
        XCTAssertEqual(
            PluginHash.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testDifferentSourcesHashDifferently() {
        XCTAssertNotEqual(PluginHash.sha256Hex("echo hi\n"), PluginHash.sha256Hex("echo bye\n"))
    }
}

final class ProvenanceStoreTests: XCTestCase {
    private func tempDir() -> String {
        NSTemporaryDirectory() + "vee-provenance-" + UUID().uuidString
    }

    func testRecordRoundTrips() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = ProvenanceStore(directory: dir)

        let record = PluginProvenance(
            filename: "cpu.5s.sh",
            sourceURL: URL(string: "https://raw.githubusercontent.com/matryer/xbar-plugins/main/System/CPU/cpu.5s.sh")!,
            source: "#!/bin/bash\necho hi\n"
        )
        try store.record(record)

        let loaded = try XCTUnwrap(store.record(for: "cpu.5s.sh"))
        XCTAssertEqual(loaded.filename, record.filename)
        XCTAssertEqual(loaded.sourceURL, record.sourceURL)
        XCTAssertEqual(loaded.sha256, record.sha256)
        XCTAssertEqual(loaded.installedAt.timeIntervalSince1970, record.installedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMissingRecordIsNil() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertNil(ProvenanceStore(directory: dir).record(for: "nope.sh"))
    }

    func testRecordOverwritesSameFilename() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = ProvenanceStore(directory: dir)
        let url = URL(string: "https://example.com/x.sh")!

        try store.record(PluginProvenance(filename: "x.sh", sourceURL: url, source: "v1"))
        try store.record(PluginProvenance(filename: "x.sh", sourceURL: url, source: "v2"))

        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.record(for: "x.sh")?.sha256, PluginHash.sha256Hex("v2"))
    }

    func testMultipleRecordsCoexist() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = ProvenanceStore(directory: dir)
        let url = URL(string: "https://example.com/x.sh")!

        try store.record(PluginProvenance(filename: "a.sh", sourceURL: url, source: "a"))
        try store.record(PluginProvenance(filename: "b.sh", sourceURL: url, source: "b"))

        XCTAssertEqual(Set(store.all().keys), ["a.sh", "b.sh"])
    }

    func testRemove() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = ProvenanceStore(directory: dir)
        let url = URL(string: "https://example.com/x.sh")!

        try store.record(PluginProvenance(filename: "x.sh", sourceURL: url, source: "x"))
        try store.remove(filename: "x.sh")
        XCTAssertNil(store.record(for: "x.sh"))
    }
}

final class ProvenanceStatusTests: XCTestCase {
    private let url = URL(string: "https://example.com/x.sh")!
    private let otherURL = URL(string: "https://example.org/mirror/x.sh")!

    func testVerifiedWhenHashMatches() {
        let source = "#!/bin/bash\necho hi\n"
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: source)
        XCTAssertEqual(ProvenanceStatus.evaluate(record: record, currentSource: source, entrySourceURL: url), .verified)
    }

    func testModifiedWhenSourceChanged() {
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: "original\n")
        XCTAssertEqual(ProvenanceStatus.evaluate(record: record, currentSource: "tampered\n", entrySourceURL: url), .modified)
    }

    func testModifiedWhenSourceMissingButRecordExists() {
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: "original\n")
        XCTAssertEqual(ProvenanceStatus.evaluate(record: record, currentSource: nil, entrySourceURL: url), .modified)
    }

    func testUnknownWhenNoRecord() {
        XCTAssertEqual(ProvenanceStatus.evaluate(record: nil, currentSource: "anything", entrySourceURL: url), .unknown)
    }

    func testUnknownWhenNoRecordAndNoSource() {
        XCTAssertEqual(ProvenanceStatus.evaluate(record: nil, currentSource: nil, entrySourceURL: url), .unknown)
    }

    // MARK: - IM4: multi-store disambiguation

    /// A same-filename entry from a DIFFERENT store (a different `rawURL`)
    /// than the one recorded at install must never borrow the installed
    /// plugin's Verified badge — regardless of whether the hash happens to
    /// match (it always will here, since the file on disk *is* what got
    /// installed from `url`; the point is entry Y must not claim it).
    func testInstalledFromAnotherSourceWhenRecordedURLDiffersFromEntryEvenIfHashMatches() {
        let source = "#!/bin/bash\necho hi\n"
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: source)
        XCTAssertEqual(
            ProvenanceStatus.evaluate(record: record, currentSource: source, entrySourceURL: otherURL),
            .installedFromAnotherSource
        )
    }

    /// Same disambiguation, independent of whether the on-disk source has
    /// since been edited — origin mismatch is checked first and wins either way.
    func testInstalledFromAnotherSourceTakesPriorityOverHashComparison() {
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: "original\n")
        XCTAssertEqual(
            ProvenanceStatus.evaluate(record: record, currentSource: "totally different\n", entrySourceURL: otherURL),
            .installedFromAnotherSource
        )
    }

    // MARK: - Origin normalization (review fix: http→https / trailing-slash false positives)

    /// A store migrating its raw base from http to https (same host, same
    /// path) recorded provenance under the old scheme — the entry it's
    /// compared against today carries the new one. That must still read as
    /// the SAME origin, not "installed from another source".
    func testSchemeDifferenceAloneIsNotAnotherSource() {
        let source = "#!/bin/bash\necho hi\n"
        let record = PluginProvenance(filename: "x.sh", sourceURL: URL(string: "http://example.com/x.sh")!, source: source)
        XCTAssertEqual(
            ProvenanceStatus.evaluate(record: record, currentSource: source, entrySourceURL: URL(string: "https://example.com/x.sh")!),
            .verified
        )
    }

    /// A trailing-slash difference alone must not read as another source either.
    func testTrailingSlashDifferenceAloneIsNotAnotherSource() {
        let source = "#!/bin/bash\necho hi\n"
        let record = PluginProvenance(filename: "x.sh", sourceURL: URL(string: "https://example.com/x.sh")!, source: source)
        XCTAssertEqual(
            ProvenanceStatus.evaluate(record: record, currentSource: source, entrySourceURL: URL(string: "https://example.com/x.sh/")!),
            .verified
        )
    }

    /// A genuinely different host, or a genuinely different path, must still
    /// count as another source — normalization must not swallow real differences.
    func testGenuinelyDifferentHostOrPathIsStillAnotherSource() {
        let source = "#!/bin/bash\necho hi\n"
        let record = PluginProvenance(filename: "x.sh", sourceURL: URL(string: "https://example.com/x.sh")!, source: source)
        XCTAssertEqual(
            ProvenanceStatus.evaluate(record: record, currentSource: source, entrySourceURL: URL(string: "https://mirror.example.com/x.sh")!),
            .installedFromAnotherSource, "a different host must still count as another source"
        )
        XCTAssertEqual(
            ProvenanceStatus.evaluate(record: record, currentSource: source, entrySourceURL: URL(string: "https://example.com/other/x.sh")!),
            .installedFromAnotherSource, "a different path must still count as another source"
        )
    }
}
