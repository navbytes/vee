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

    /// Regression: an atomic-rename save (write a temp file alongside the
    /// original, then `rename()` it over the target — how most GUI editors
    /// save) changes the *directory entry* itself, so the vnode source must
    /// catch it directly rather than needing the periodic tick's fallback. A
    /// `tickInterval` far longer than the wait below means any fire here can
    /// only be the vnode source.
    func testAtomicRenameOverwriteIsDetectedByVnodeSource() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let filePath = dir + "/plugin.5s.sh"
        let tmpPath = dir + "/.plugin.5s.sh.tmp"
        FileManager.default.createFile(atPath: filePath, contents: Data("original".utf8))

        let fired = expectation(description: "onChange fires promptly after an atomic-rename save")
        fired.assertForOverFulfill = false
        let watcher = PluginDirectoryWatcher(directory: dir, debounce: 0.05, tickInterval: 30) {
            fired.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.1)
        FileManager.default.createFile(atPath: tmpPath, contents: Data("changed".utf8))
        XCTAssertEqual(rename(tmpPath, filePath), 0, "test setup: rename() should succeed")

        wait(for: [fired], timeout: 3)
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

    /// Editors often save multiple times in a rapid burst (auto-save plus an
    /// explicit save, or a multi-step atomic write). Each new event must
    /// cancel and reschedule the pending debounced notify rather than queuing
    /// one of its own, so the burst collapses into a single `onChange`.
    func testBurstOfWritesCoalescesIntoOneOnChange() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let counter = ChangeCounter()
        let watcher = PluginDirectoryWatcher(directory: dir, debounce: 0.2, tickInterval: 30) {
            counter.increment()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.1)
        for i in 0..<5 {
            FileManager.default.createFile(atPath: dir + "/burst\(i).sh", contents: Data("x".utf8))
            Thread.sleep(forTimeInterval: 0.02) // well inside the 0.2s debounce window
        }

        // Wait past the debounce window from the last event, then let any
        // (incorrect) extra fires land before asserting the final count.
        let deadline = Date().addingTimeInterval(2)
        while counter.current == 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(counter.current, 1, "a burst of saves within the debounce window should coalesce into a single reload")
    }
}
