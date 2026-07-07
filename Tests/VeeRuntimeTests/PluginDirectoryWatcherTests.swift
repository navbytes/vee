import XCTest
@testable import VeeRuntime

/// Thread-safe fire counter for a watcher's `onChange` callback, which fires on
/// the watcher's private background queue rather than the test's thread.
private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class PluginDirectoryWatcherTests: XCTestCase {
    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "vee-watch-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Regression: the vnode source only fires on directory-entry add/remove/
    /// rename, so an in-place edit (`nano`/append/`chmod` on an existing file)
    /// produces no event there. Only the periodic tick can notice it.
    func testInPlaceEditIsDetectedByPeriodicTick() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let filePath = dir + "/plugin.5s.sh"
        FileManager.default.createFile(atPath: filePath, contents: Data("original".utf8))

        let fired = expectation(description: "onChange fires after an in-place edit, via the periodic tick")
        fired.assertForOverFulfill = false
        let watcher = PluginDirectoryWatcher(directory: dir, debounce: 0.05, tickInterval: 0.3) {
            fired.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }

        // Let the watcher's initial open/tick-scheduling settle, then edit the
        // file in place — no entry add/remove/rename for the vnode source to see.
        Thread.sleep(forTimeInterval: 0.1)
        try Data("changed".utf8).write(to: URL(fileURLWithPath: filePath))

        wait(for: [fired], timeout: 5)
    }

    /// Regression: after the watched directory itself is deleted and recreated
    /// (e.g. switching plugins folders, or an editor's atomic-replace of a
    /// directory), the original fd points at a dead inode. Without a reopen
    /// mechanism the watcher goes silently inert forever; the periodic tick
    /// must notice and reopen against the new directory.
    func testDeleteAndRecreateDirectoryRecovers() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let counter = ChangeCounter()
        let watcher = PluginDirectoryWatcher(directory: dir, debounce: 0.05, tickInterval: 0.3) {
            counter.increment()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.1)
        try FileManager.default.removeItem(atPath: dir)

        // Let the delete itself (and/or the first tick) fire onChange, then
        // baseline the count — the assertion below must specifically catch a
        // fire *after* the directory comes back, not just the delete being
        // noticed (which the pre-fix watcher could already do once).
        let baselineDeadline = Date().addingTimeInterval(2)
        while counter.current == 0, Date() < baselineDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let baseline = counter.current

        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/new.sh", contents: Data("x".utf8))

        let deadline = Date().addingTimeInterval(5)
        while counter.current <= baseline, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertGreaterThan(counter.current, baseline, "onChange should fire again once the directory is recreated")
    }
}
