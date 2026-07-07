import XCTest
import VeeCore
@testable import VeeRuntime

final class StreamAccumulatorTests: XCTestCase {
    func testEmitsBlockOnSeparator() {
        var acc = StreamAccumulator()
        XCTAssertNil(acc.consume("Line 1"))
        XCTAssertNil(acc.consume("Line 2"))
        XCTAssertEqual(acc.consume("~~~"), "Line 1\nLine 2")
        // Buffer resets after a separator.
        XCTAssertNil(acc.consume("Next"))
        XCTAssertEqual(acc.consume("~~~"), "Next")
    }

    func testFlushEmitsRemainder() {
        var acc = StreamAccumulator()
        _ = acc.consume("A")
        _ = acc.consume("B")
        XCTAssertEqual(acc.flush(), "A\nB")
        XCTAssertNil(acc.flush()) // nothing left
    }

    /// Regression: a streaming plugin that never emits `~~~` must not grow the
    /// buffer without bound (the bounded-memory guarantee).
    func testBufferIsCappedWithoutSeparator() {
        var acc = StreamAccumulator()
        let line = String(repeating: "x", count: 1024) // ~1 KB
        // Feed well past the 4 MB cap.
        for _ in 0..<(6 * 1024) { XCTAssertNil(acc.consume(line)) }
        let block = acc.flush() ?? ""
        XCTAssertLessThanOrEqual(block.utf8.count, StreamAccumulator.maxBufferedBytes + line.utf8.count + 1)
        // A separator after the cap still resets cleanly.
        XCTAssertNil(acc.consume("fresh"))
        XCTAssertEqual(acc.consume("~~~"), "fresh")
    }
}

final class BackoffPolicyTests: XCTestCase {
    func testExponentialAndCapped() {
        XCTAssertEqual(BackoffPolicy.delay(attempt: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(BackoffPolicy.delay(attempt: 2), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BackoffPolicy.delay(attempt: 3), 2.0, accuracy: 0.0001)
        XCTAssertEqual(BackoffPolicy.delay(attempt: 10), 30, accuracy: 0.0001) // capped
    }
}

final class CrashLoopDetectorTests: XCTestCase {
    func testTripsAfterTooManyRestartsInWindow() {
        var detector = CrashLoopDetector(maxRestarts: 3, window: 60)
        let base = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(detector.record(now: base))
        XCTAssertFalse(detector.record(now: base.addingTimeInterval(1)))
        XCTAssertFalse(detector.record(now: base.addingTimeInterval(2)))
        XCTAssertTrue(detector.record(now: base.addingTimeInterval(3))) // 4th within window
    }

    func testOldRestartsAgeOut() {
        var detector = CrashLoopDetector(maxRestarts: 2, window: 10)
        let base = Date(timeIntervalSince1970: 1_000_000)
        _ = detector.record(now: base)
        _ = detector.record(now: base.addingTimeInterval(1))
        // 30s later the earlier restarts have aged out of the window.
        XCTAssertFalse(detector.record(now: base.addingTimeInterval(30)))
    }
}

final class StreamingRunnerIntegrationTests: XCTestCase {
    func testStreamsLinesThenFinishes() async throws {
        let runner = SystemStreamingRunner()
        // Delays force the output to arrive in multiple reads — the condition
        // that exposed a termination/read race (only the first chunk survived).
        let invocation = ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "printf 'a\\n'; sleep 0.1; printf 'b\\n~~~\\n'; sleep 0.1; printf 'c\\n'"]
        )
        var lines: [String] = []
        for try await line in runner.lines(invocation) {
            lines.append(line)
        }
        XCTAssertEqual(lines, ["a", "b", "~~~", "c"])
    }

    /// Regression: a Windows-line-ending streaming plugin emits `~~~\r\n`. The
    /// trailing "\r" must be stripped at the line-split boundary so the
    /// separator still matches — and so StreamAccumulator, fed these lines the
    /// same way StreamingSession does, still resets the menu on each block.
    func testCRLFStreamSeparatorIsRecognized() async throws {
        let runner = SystemStreamingRunner()
        let invocation = ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "printf 'a\\r\\n~~~\\r\\nb\\r\\n'"]
        )
        var lines: [String] = []
        for try await line in runner.lines(invocation) {
            lines.append(line)
        }
        XCTAssertEqual(lines, ["a", "~~~", "b"], "the trailing \\r must not remain on any line")

        var accumulator = StreamAccumulator()
        var blocks: [String] = []
        for line in lines {
            if let block = accumulator.consume(line) { blocks.append(block) }
        }
        if let tail = accumulator.flush() { blocks.append(tail) }
        XCTAssertEqual(blocks, ["a", "b"], "the CRLF separator must still reset the accumulator")
    }
}
