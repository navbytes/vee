import XCTest
import VeeCore
@testable import VeeRuntime

final class PluginChangeSnapshotTests: XCTestCase {
    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "vee-snapshot-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func plugin(at path: String) -> DiscoveredPlugin {
        DiscoveredPlugin(path: path, id: PluginID(path: path), filename: PluginFilename((path as NSString).lastPathComponent), isExecutable: false)
    }

    /// Regression: `AppController.reload()` skips its rebuild when the fresh
    /// snapshot equals the loaded one. Two snapshots of the same, untouched
    /// files must compare equal — the crux of "unchanged files don't cause a
    /// spurious reload".
    func testUnchangedFilesProduceEqualSnapshots() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/cpu.5s.sh"
        FileManager.default.createFile(atPath: path, contents: Data("echo hi".utf8))

        let first = PluginChangeSnapshot.snapshot([plugin(at: path)])
        let second = PluginChangeSnapshot.snapshot([plugin(at: path)])
        XCTAssertEqual(first, second)
    }

    /// The gap the roadmap named: an in-place edit (same filename, e.g.
    /// `echo >> plugin.sh`) must change the snapshot even though the path set
    /// is identical, so `reload()` no longer early-returns on it.
    func testInPlaceAppendChangesSnapshot() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/cpu.5s.sh"
        FileManager.default.createFile(atPath: path, contents: Data("original".utf8))

        let before = PluginChangeSnapshot.snapshot([plugin(at: path)])

        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        handle.seekToEndOfFile()
        handle.write(Data("\nappended".utf8))
        try handle.close()

        let after = PluginChangeSnapshot.snapshot([plugin(at: path)])
        XCTAssertNotEqual(before[path], after[path])
    }

    /// A change in size alone (even a contrived same-mtime write, the coarse-
    /// filesystem-clock edge case the identity tuple is hedging against) must
    /// still be visible — belt-and-suspenders alongside the mtime check.
    func testSizeChangeAloneIsDetected() {
        let a = PluginChangeSnapshot.FileIdentity(modified: 1000, size: 10)
        let b = PluginChangeSnapshot.FileIdentity(modified: 1000, size: 11)
        XCTAssertNotEqual(a, b)
    }

    func testAddedAndRemovedPluginsChangeTheKeySet() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/cpu.5s.sh"
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))

        let before = PluginChangeSnapshot.snapshot([plugin(at: path)])
        XCTAssertNotEqual(before, PluginChangeSnapshot.snapshot([]))
    }
}
