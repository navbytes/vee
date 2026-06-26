import XCTest
@testable import VeeEngine
import VeeProtocol

/// Wave R2 — §5 out-of-process host hardening for `StdioTransport`.
///
/// Covers the "max-frame bound" item from docs/AUDIT-2.md §5: a hostile or
/// garbled `Content-Length` must NOT let the child dictate the parent's memory
/// footprint (OOM-from-the-process-it-should-contain). On a violation the
/// transport tears itself down (fires `onClose`, stops the read source) instead
/// of growing `inboundBuffer` without bound — and never delivers a frame from the
/// bogus header.
///
/// These are deterministic: we drive the transport's READ fd by hand via the raw
/// write end of a `Pipe`, no child process involved. New file (per the build
/// rules) so the existing `OutOfProcessTests` is untouched.
final class StdioTransportHardeningTests: XCTestCase {

    /// An absurd `Content-Length` (far above the cap) must tear the transport
    /// down rather than waiting to buffer that many bytes — and must deliver no
    /// frame. We use a tiny cap so the test is fast and unambiguous.
    func testOversizedContentLengthHeaderTearsDownTransport() {
        let pipe = Pipe()
        let t = StdioTransport(read: pipe.fileHandleForReading,
                               write: FileHandle.nullDevice,
                               label: "oversize",
                               maxFrameBytes: 1024)   // 1 KiB cap
        let closed = expectation(description: "transport tears down on oversized frame")
        t.onClose = { closed.fulfill() }
        var delivered = false
        t.onReceive = { _ in delivered = true }
        t.resume()

        // Header declares a body of 10 MiB — far above the 1 KiB cap. We do NOT
        // send the body; the transport must reject on the LENGTH, not wait for it.
        let header = Data("Content-Length: \(10 * 1024 * 1024)\r\n\r\n".utf8)
        pipe.fileHandleForWriting.write(header)

        wait(for: [closed], timeout: 5)
        XCTAssertFalse(delivered, "no frame is delivered from the oversized header")
        t.stop()
    }

    /// A frame at or under the cap still round-trips normally (the cap doesn't
    /// reject legitimate traffic).
    func testFrameUnderCapStillDelivers() {
        let pipe = Pipe()
        let t = StdioTransport(read: pipe.fileHandleForReading,
                               write: FileHandle.nullDevice,
                               label: "undercap",
                               maxFrameBytes: 1024 * 1024)
        let received = expectation(description: "an under-cap frame is delivered")
        var method: String?
        t.onReceive = { message in
            if case .notification(let n) = message { method = n.method; received.fulfill() }
        }
        t.resume()

        let payload = try! RPCCodec.encode(.notification(JSONRPCNotification(
            method: "ok", params: .object(["v": .number(1)]))))
        var frame = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        frame.append(payload)
        pipe.fileHandleForWriting.write(frame)

        wait(for: [received], timeout: 5)
        XCTAssertEqual(method, "ok")
        t.stop()
    }

    /// A negative `Content-Length` (`Content-Length: -1`) is rejected — Int parses
    /// it, but it is below the `>= 0` floor, so the transport tears down rather
    /// than computing a wild body range.
    func testNegativeContentLengthTearsDownTransport() {
        let pipe = Pipe()
        let t = StdioTransport(read: pipe.fileHandleForReading,
                               write: FileHandle.nullDevice,
                               label: "negative",
                               maxFrameBytes: 1024)
        let closed = expectation(description: "transport tears down on negative length")
        t.onClose = { closed.fulfill() }
        t.resume()

        pipe.fileHandleForWriting.write(Data("Content-Length: -1\r\n\r\n".utf8))
        wait(for: [closed], timeout: 5)
        t.stop()
    }

    /// Headerless garbage with NO terminating `\r\n\r\n` must not grow the buffer
    /// without bound: once the unframed tail exceeds the cap, the transport tears
    /// down (the never-completing-header backstop).
    func testUnframedFloodTearsDownTransport() {
        let pipe = Pipe()
        let cap = 64 * 1024
        let t = StdioTransport(read: pipe.fileHandleForReading,
                               write: FileHandle.nullDevice,
                               label: "flood",
                               maxFrameBytes: cap)
        let closed = expectation(description: "transport tears down on unframed flood")
        t.onClose = { closed.fulfill() }
        t.resume()

        // Stream well past the cap with no header separator at all.
        let junk = Data(repeating: 0x41 /* 'A' */, count: cap + 4096)
        pipe.fileHandleForWriting.write(junk)

        wait(for: [closed], timeout: 5)
        t.stop()
    }
}
