import XCTest
@testable import VeeApp
import VeeCatalog

/// `swiftbar://addplugin` used to write the plugin file and reload, but
/// record no provenance at all (IM5/IM12) — so a same-filename reinstall (or
/// a different store's same-named catalog entry) could show a misattributed
/// trust badge. `AppController.installFromAddPlugin` is the extracted,
/// pure-ish slice of `installPlugin(from:)` that fixes this (provenance is
/// written before the file, so there's never a present-but-untracked
/// window) — pulled out specifically so it's testable without the real
/// network fetch or the trust-confirmation `NSAlert` that surround it in
/// production.
final class AddPluginProvenanceTests: XCTestCase {
    private func tempDir() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-addplugin-\(UUID().uuidString)", isDirectory: true).path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testInstallFromAddPluginRecordsProvenanceWithTheRightSourceURL() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let filename = "web-install.sh"
        let sourceURL = URL(string: "https://example.com/plugins/\(filename)")!
        let source = "#!/bin/bash\necho hi\n"

        try AppController.installFromAddPlugin(filename: filename, source: source, sourceURL: sourceURL, into: dir)

        let record = try XCTUnwrap(ProvenanceStore(directory: dir).record(for: filename))
        XCTAssertEqual(record.sourceURL, sourceURL)
        XCTAssertEqual(record.sha256, PluginHash.sha256Hex(source))
        XCTAssertEqual(
            try String(contentsOfFile: (dir as NSString).appendingPathComponent(filename), encoding: .utf8),
            source,
            "the file itself must still be written, not just the record"
        )
    }

    /// Provenance is advisory: a directory that can't be written to must
    /// still surface the real install failure (from `PluginInstaller`), not
    /// something swallowed by the best-effort provenance write.
    func testInstallFromAddPluginStillThrowsWhenTheFileWriteFails() {
        // A path that can't exist as a directory (its parent is a file, not
        // a folder) — `PluginInstaller.install`'s `createDirectory` throws.
        let dir = tempDir()
        let blocking = (dir as NSString).appendingPathComponent("blocking-file")
        FileManager.default.createFile(atPath: blocking, contents: Data())
        let unusableDir = (blocking as NSString).appendingPathComponent("plugins")
        defer { try? FileManager.default.removeItem(atPath: dir) }

        XCTAssertThrowsError(
            try AppController.installFromAddPlugin(filename: "x.sh", source: "echo hi", sourceURL: URL(string: "https://example.com/x.sh")!, into: unusableDir)
        )
    }
}
