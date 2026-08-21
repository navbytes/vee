import XCTest
@testable import VeeRuntime

/// Thread-safe fire counter for a watcher's `onChange` callback, which fires on
/// the watcher's private background queue rather than the test's thread.
private final class FireCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class FileWatcherTests: XCTestCase {
    private func tempFile(contents: String = "original") throws -> (dir: String, path: String) {
        let dir = NSTemporaryDirectory() + "vee-filewatch-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/watched.5s.sh"
        FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
        return (dir, path)
    }

    /// The gap `PluginDirectoryWatcher` cannot cover: a write to an existing
    /// file produces no directory-entry event, so only a source on the file
    /// itself sees it.
    func testInPlaceWriteFires() throws {
        let (dir, path) = try tempFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let fired = expectation(description: "onChange fires after an in-place write")
        fired.assertForOverFulfill = false
        let watcher = FileWatcher(path: path, debounce: 0.05) { fired.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.1)  // let the source open
        try Data("changed".utf8).write(to: URL(fileURLWithPath: path))

        wait(for: [fired], timeout: 3)
    }

    /// The case that makes a naive file watcher wrong: most editors save by
    /// writing a temp file and renaming it over the target, which leaves the
    /// watched fd on a dead inode. The first save must fire *and* the watcher
    /// must re-bind so the second save fires too — a watcher that reports one
    /// save and then goes silent is worse than one that never worked.
    func testAtomicReplaceFiresAndKeepsFiring() throws {
        let (dir, path) = try tempFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let counter = FireCounter()
        let firstSave = expectation(description: "first atomic-replace save fires")
        firstSave.assertForOverFulfill = false
        let secondSave = expectation(description: "second atomic-replace save fires after re-binding")
        secondSave.assertForOverFulfill = false

        let watcher = FileWatcher(path: path, debounce: 0.05) {
            counter.increment()
            if counter.current >= 1 { firstSave.fulfill() }
            if counter.current >= 2 { secondSave.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.1)

        func atomicSave(_ contents: String, index: Int) throws {
            let tmp = dir + "/.watched.tmp\(index)"
            FileManager.default.createFile(atPath: tmp, contents: Data(contents.utf8))
            XCTAssertEqual(rename(tmp, path), 0, "test setup: rename() should succeed")
        }

        try atomicSave("first", index: 1)
        wait(for: [firstSave], timeout: 3)

        try atomicSave("second", index: 2)
        wait(for: [secondSave], timeout: 3)
    }

    /// A save that unlinks before recreating must not leave the watcher inert:
    /// the reopen retry re-binds once the path exists again.
    func testRecreatedAfterDeleteFires() throws {
        let (dir, path) = try tempFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let counter = FireCounter()
        let recreated = expectation(description: "onChange fires after the file is deleted and recreated")
        recreated.assertForOverFulfill = false
        let watcher = FileWatcher(path: path, debounce: 0.05, reopenRetry: 0.1) {
            counter.increment()
            recreated.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.1)

        try FileManager.default.removeItem(atPath: path)
        Thread.sleep(forTimeInterval: 0.15)
        FileManager.default.createFile(atPath: path, contents: Data("recreated".utf8))

        wait(for: [recreated], timeout: 3)

        // And it is still live afterwards.
        let again = expectation(description: "a later in-place write still fires")
        again.assertForOverFulfill = false
        let before = counter.current
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            try? Data("more".utf8).write(to: URL(fileURLWithPath: path))
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if counter.current > before { again.fulfill(); break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        wait(for: [again], timeout: 1)
    }

    /// A burst of writes (an editor saving repeatedly, or a generator appending)
    /// must not start one run per write.
    func testRapidWritesCoalesce() throws {
        let (dir, path) = try tempFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let counter = FireCounter()
        let watcher = FileWatcher(path: path, debounce: 0.25) { counter.increment() }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.1)

        for i in 0..<10 {
            try Data("write \(i)".utf8).write(to: URL(fileURLWithPath: path))
            Thread.sleep(forTimeInterval: 0.01)
        }
        Thread.sleep(forTimeInterval: 0.8)

        let fires = counter.current
        XCTAssertGreaterThan(fires, 0, "the burst should produce at least one notification")
        XCTAssertLessThan(fires, 10, "ten writes inside one debounce window must coalesce")
    }

    /// `stop()` is called from `defer` in every consumer, sometimes twice.
    func testStopIsIdempotentAndSilencesFurtherEvents() throws {
        let (dir, path) = try tempFile()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let counter = FireCounter()
        let watcher = FileWatcher(path: path, debounce: 0.05) { counter.increment() }
        watcher.start()
        Thread.sleep(forTimeInterval: 0.1)

        watcher.stop()
        watcher.stop()  // must not crash or double-close
        Thread.sleep(forTimeInterval: 0.1)

        let afterStop = counter.current
        try Data("changed after stop".utf8).write(to: URL(fileURLWithPath: path))
        Thread.sleep(forTimeInterval: 0.4)

        XCTAssertEqual(counter.current, afterStop, "no notifications may arrive after stop()")
    }
}
