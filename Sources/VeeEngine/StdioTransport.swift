import Foundation
import VeeProtocol

/// A process-boundary-safe `RPCTransport` that frames JSON-RPC 2.0 messages over
/// a pair of `FileHandle`s (a child's `stdin`/`stdout`, or the two ends of a
/// `Pipe`).
///
/// ## Framing
///
/// We use **LSP-style length-prefixed framing**: each frame is a header block,
/// the literal separator `\r\n\r\n`, then exactly `Content-Length` bytes of UTF-8
/// JSON:
///
/// ```
/// Content-Length: 58\r\n
/// \r\n
/// {"jsonrpc":"2.0","method":"plugin.render","params":{...}}
/// ```
///
/// Length-prefixing (rather than newline-delimiting) is chosen deliberately: a
/// JSON-RPC payload can legally contain raw bytes that resemble a delimiter, and
/// `JSONEncoder` does not guarantee newline-free output across platforms/versions.
/// A byte count is unambiguous and lets the reader reassemble across partial /
/// split / coalesced reads from the kernel pipe buffer — the read side never
/// assumes a `read()` returns exactly one frame.
///
/// ## Threading & ordering
///
/// Inbound bytes are pumped by a background read source (a `DispatchSource` over
/// the read fd) onto a private serial `readQueue`; complete frames are decoded
/// there and delivered on a serial `deliveryQueue`. Outbound `send` serializes
/// the framed write on a private `writeQueue` so concurrent senders can't
/// interleave half-frames on the wire. Delivery reuses the re-entrancy-safe
/// `onQueue` pattern (a `DispatchSpecificKey` so a handler that calls `send`
/// while *receiving* — e.g. a plugin emits `showToast` from inside an inbound
/// `host.invokeAction` — runs inline instead of dead-locking on `queue.sync`).
///
/// There are **no shared-memory assumptions**: the only channel is the fd pair,
/// so the same class drives both the parent (talking to a child `Process`) and
/// the child (talking over its own `stdin`/`stdout`).
public final class StdioTransport: RPCTransport {
    public var onReceive: ((JSONRPCMessage) -> Void)?

    /// Invoked when the read side reaches EOF (peer closed its write end). The
    /// parent uses this together with `Process.terminationHandler`; the child
    /// uses it to exit its run loop when the parent goes away.
    public var onClose: (() -> Void)?

    private let readHandle: FileHandle
    private let writeHandle: FileHandle

    private let writeQueue: DispatchQueue
    private let deliveryQueue: DispatchQueue
    private let deliveryKey = DispatchSpecificKey<UInt8>()

    /// Accumulates raw inbound bytes until at least one full frame is available.
    /// Touched only from the read source's handler (serial), so no lock needed.
    private var inboundBuffer = Data()

    private var readSource: DispatchSourceRead?
    private let readQueue: DispatchQueue
    private var closed = false

    /// - Parameters:
    ///   - readHandle:  fd to read framed inbound messages from (default stdin).
    ///   - writeHandle: fd to write framed outbound messages to (default stdout).
    ///   - label:       queue label prefix for diagnostics.
    public init(read readHandle: FileHandle = .standardInput,
                write writeHandle: FileHandle = .standardOutput,
                label: String = "vee.engine.stdio") {
        self.readHandle = readHandle
        self.writeHandle = writeHandle
        self.writeQueue = DispatchQueue(label: "\(label).write")
        self.deliveryQueue = DispatchQueue(label: "\(label).delivery")
        self.readQueue = DispatchQueue(label: "\(label).read")
        self.deliveryQueue.setSpecific(key: deliveryKey, value: 1)
    }

    /// Begin pumping the read side. Idempotent. Call once after `onReceive` is
    /// installed. (Construction does not auto-start so the owner can wire
    /// callbacks first without racing an early frame.)
    public func resume() {
        readQueue.async { [weak self] in
            guard let self, self.readSource == nil, !self.closed else { return }
            let source = DispatchSource.makeReadSource(
                fileDescriptor: self.readHandle.fileDescriptor, queue: self.readQueue)
            source.setEventHandler { [weak self] in self?.pumpReadable() }
            source.setCancelHandler { /* fd lifetime owned by the FileHandle */ }
            self.readSource = source
            source.resume()
        }
    }

    /// Stop the read source and release it. Safe to call repeatedly.
    public func stop() {
        readQueue.async { [weak self] in
            guard let self else { return }
            self.readSource?.cancel()
            self.readSource = nil
        }
    }

    // MARK: - Outbound (RPCTransport.send)

    /// Encode `message` through `RPCCodec` and write a single length-prefixed
    /// frame. Serialized on `writeQueue` so frames never interleave on the wire.
    /// A `write(2)` is retried on partial completion / `EINTR` so a large frame
    /// is delivered whole.
    public func send(_ message: JSONRPCMessage) {
        let payload: Data
        do {
            payload = try RPCCodec.encode(message)
        } catch {
            assertionFailure("StdioTransport: failed to encode outbound frame: \(error)")
            return
        }
        var frame = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        frame.append(payload)
        writeQueue.async { [weak self] in
            self?.writeAll(frame)
        }
    }

    /// MUST run on `writeQueue`. Writes every byte, looping on partial writes and
    /// retrying `EINTR`. A broken pipe (peer gone) is swallowed — the parent's
    /// supervision detects termination separately; the transport must not crash.
    private func writeAll(_ data: Data) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let total = raw.count
            let fd = writeHandle.fileDescriptor
            while offset < total {
                let n = write(fd, base + offset, total - offset)
                if n > 0 {
                    offset += n
                } else if n == -1 && errno == EINTR {
                    continue
                } else {
                    // EPIPE / EBADF: the peer's read end is gone. Stop quietly.
                    return
                }
            }
        }
    }

    // MARK: - Inbound (read source → frame reassembly → delivery)

    /// MUST run on `readQueue`. Drains everything currently readable into the
    /// inbound buffer, then extracts as many complete frames as it holds. A zero
    /// read means EOF (peer closed write end) → fire `onClose` once and cancel.
    private func pumpReadable() {
        let fd = readHandle.fileDescriptor
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }

        if n > 0 {
            inboundBuffer.append(contentsOf: chunk[0..<n])
            drainFrames()
        } else if n == 0 {
            handleEOF()
        } else {
            // n == -1
            if errno == EINTR || errno == EAGAIN { return }   // try again on next event
            handleEOF()
        }
    }

    private func handleEOF() {
        guard !closed else { return }
        closed = true
        readSource?.cancel()
        readSource = nil
        let cb = onClose
        deliver { cb?() }
    }

    /// Pull every complete `Content-Length`-framed message out of `inboundBuffer`,
    /// leaving any trailing partial frame in place for the next read. Robust to:
    /// split headers, a header without its full body yet, and several frames
    /// coalesced into one read.
    ///
    /// IMPORTANT: this works in a flat `[UInt8]` with integer offsets, never with
    /// `Data` slice indices. `Data` preserves a slice's original index range across
    /// `removeSubrange`/`subdata`, so mixing `range(of:)` results with
    /// `startIndex`-relative slicing after a mutation silently reads the wrong
    /// bytes (the bug that dropped every frame after the first). Offsets into a
    /// rebased byte array sidestep that entirely.
    private func drainFrames() {
        var bytes = [UInt8](inboundBuffer)
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]   // \r\n\r\n
        var consumed = 0   // offset up to which `bytes` has been processed

        while true {
            guard let sepStart = Self.firstIndex(of: separator, in: bytes, from: consumed) else {
                break   // header incomplete; wait for more bytes
            }
            let headerBytes = Array(bytes[consumed..<sepStart])
            guard let contentLength = Self.parseContentLength(Data(headerBytes)) else {
                // Garbage header — skip past the separator and resync so one bad
                // frame can't wedge the stream forever.
                consumed = sepStart + separator.count
                continue
            }
            let bodyStart = sepStart + separator.count
            let bodyEnd = bodyStart + contentLength
            guard bodyEnd <= bytes.count else {
                break   // body not fully arrived yet; wait for more bytes
            }
            let body = Data(bytes[bodyStart..<bodyEnd])
            consumed = bodyEnd

            if let message = try? RPCCodec.decode(body) {
                let handler = onReceive
                deliver { handler?(message) }
            }
            // A frame that fails to decode is skipped; ordering of the remaining
            // frames is unaffected because `consumed` already advanced past it.
        }

        // Keep only the unconsumed tail for the next read.
        if consumed > 0 {
            inboundBuffer = Data(bytes[consumed...])
        }
    }

    /// Index of the first occurrence of `needle` in `haystack` at or after `from`,
    /// or nil. Plain byte scan — no `Data` index semantics involved.
    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, haystack.count - from >= needle.count else { return nil }
        let last = haystack.count - needle.count
        var i = from
        while i <= last {
            if haystack[i] == needle[0] {
                var matched = true
                var j = 1
                while j < needle.count {
                    if haystack[i + j] != needle[j] { matched = false; break }
                    j += 1
                }
                if matched { return i }
            }
            i += 1
        }
        return nil
    }

    /// Parse a `Content-Length` header value out of an LSP header block. Headers
    /// are case-insensitive and `\r\n`-separated; we ignore any others.
    private static func parseContentLength(_ headerData: Data) -> Int? {
        guard let text = String(data: headerData, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    /// Re-entrancy-safe delivery: if we're already on `deliveryQueue` (a handler
    /// sent a frame whose write completion or a nested decode hopped back), run
    /// inline; otherwise dispatch synchronously to preserve frame ordering. This
    /// mirrors `LoopbackTransport.onQueue`.
    private func deliver(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: deliveryKey) != nil {
            work()
        } else {
            deliveryQueue.sync(execute: work)
        }
    }
}
