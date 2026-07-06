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

    func testVerifiedWhenHashMatches() {
        let source = "#!/bin/bash\necho hi\n"
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: source)
        XCTAssertEqual(ProvenanceStatus.evaluate(record: record, currentSource: source), .verified)
    }

    func testModifiedWhenSourceChanged() {
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: "original\n")
        XCTAssertEqual(ProvenanceStatus.evaluate(record: record, currentSource: "tampered\n"), .modified)
    }

    func testModifiedWhenSourceMissingButRecordExists() {
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: "original\n")
        XCTAssertEqual(ProvenanceStatus.evaluate(record: record, currentSource: nil), .modified)
    }

    func testUnknownWhenNoRecord() {
        XCTAssertEqual(ProvenanceStatus.evaluate(record: nil, currentSource: "anything"), .unknown)
    }

    func testUnknownWhenNoRecordAndNoSource() {
        XCTAssertEqual(ProvenanceStatus.evaluate(record: nil, currentSource: nil), .unknown)
    }
}
