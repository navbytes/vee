import XCTest
@testable import VeeEngine
import VeeProtocol
import VeeJSONPatch

/// Wave R2 — the out-of-process plugin host suite.
///
/// Two layers:
///   1. **Framing** — `StdioTransport` round-trips JSON-RPC frames over real
///      `Pipe`s with NO child process. Proves LSP-style `Content-Length` framing,
///      ordering, large payloads, back-to-back frames, partial/split-read
///      reassembly, and re-entrancy-safe delivery (a handler that sends while
///      receiving).
///   2. **Real child integration** — spawns the built `vee-plugin-host` via
///      `ChildProcessHost`, loads + activates the committed `essentials` fixture,
///      asserts the resulting `plugin.render`, then proves crash isolation: the
///      child is terminated, `onTermination` fires, the test process is unharmed,
///      and `restart()` brings it back so a second activate works. Skipped (not
///      failed) when the product binary can't be found.
final class OutOfProcessTests: XCTestCase {

    // MARK: - StdioTransport framing (deterministic, no process)

    /// Wire two transports back-to-back via two `Pipe`s: A writes → pipe → B reads
    /// (and vice-versa). Returns both plus the pipes (kept alive by the caller).
    private func connectedPair(label: String = "test")
        -> (a: StdioTransport, b: StdioTransport, pipes: [Pipe]) {
        let aToB = Pipe()
        let bToA = Pipe()
        let a = StdioTransport(read: bToA.fileHandleForReading,
                               write: aToB.fileHandleForWriting,
                               label: "\(label).a")
        let b = StdioTransport(read: aToB.fileHandleForReading,
                               write: bToA.fileHandleForWriting,
                               label: "\(label).b")
        return (a, b, [aToB, bToA])
    }

    func testFramingDeliversNotificationAToB() {
        let (a, b, pipes) = connectedPair()
        withExtendedLifetime(pipes) {
            let received = expectation(description: "B receives the notification")
            var got: JSONRPCNotification?
            b.onReceive = { message in
                if case .notification(let n) = message { got = n; received.fulfill() }
            }
            b.resume(); a.resume()

            a.send(.notification(JSONRPCNotification(
                method: RPCMethods.log,
                params: try! JSONValueCoder.encode(
                    LogParams(pluginId: "com.vee.x", level: .info, message: "hello over the wire")))))

            wait(for: [received], timeout: 5)
            XCTAssertEqual(got?.method, RPCMethods.log)
            let decoded = try! JSONValueCoder.decode(LogParams.self, from: got!.params!)
            XCTAssertEqual(decoded.message, "hello over the wire")
            a.stop(); b.stop()
        }
    }

    func testFramingRoundTripsRequestAndResponseBothWays() {
        let (a, b, pipes) = connectedPair()
        withExtendedLifetime(pipes) {
            let gotRequest = expectation(description: "B receives request")
            let gotResponse = expectation(description: "A receives response")

            b.onReceive = { message in
                if case .request(let req) = message {
                    XCTAssertEqual(req.method, ChildHostMethods.loadPlugin)
                    gotRequest.fulfill()
                    // B answers back over its own write end.
                    b.send(.response(JSONRPCResponse(id: req.id, result: .object(["ok": .bool(true)]))))
                }
            }
            a.onReceive = { message in
                if case .response(let r) = message {
                    XCTAssertEqual(r.result?.objectValue?["ok"]?.boolValue, true)
                    gotResponse.fulfill()
                }
            }
            b.resume(); a.resume()

            a.send(.request(JSONRPCRequest(id: .string("1"), method: ChildHostMethods.loadPlugin,
                                           params: .object([:]))))
            wait(for: [gotRequest, gotResponse], timeout: 5)
            a.stop(); b.stop()
        }
    }

    func testFramingPreservesOrderingOfBackToBackFrames() {
        let (a, b, pipes) = connectedPair()
        withExtendedLifetime(pipes) {
            let count = 50
            let allReceived = expectation(description: "B receives all \(count) in order")
            var order: [Int] = []
            b.onReceive = { message in
                if case .notification(let n) = message,
                   let i = n.params?["i"]?.intValue {
                    order.append(i)
                    if order.count == count { allReceived.fulfill() }
                }
            }
            b.resume(); a.resume()

            // Fire all frames back-to-back from the same caller; they may coalesce
            // into a single kernel read on B's side — framing must still split them.
            for i in 0..<count {
                a.send(.notification(JSONRPCNotification(method: "n", params: .object(["i": .number(Double(i))]))))
            }
            wait(for: [allReceived], timeout: 5)
            XCTAssertEqual(order, Array(0..<count), "frames decode in send order")
            a.stop(); b.stop()
        }
    }

    func testFramingReassemblesLargePayload() {
        let (a, b, pipes) = connectedPair()
        withExtendedLifetime(pipes) {
            // A payload far larger than one pipe buffer / one read chunk, forcing
            // the reader to reassemble across many partial reads.
            let big = String(repeating: "x", count: 512 * 1024)
            let received = expectation(description: "B receives the large frame intact")
            var gotLen = 0
            b.onReceive = { message in
                if case .notification(let n) = message,
                   let s = n.params?["blob"]?.stringValue {
                    gotLen = s.count; received.fulfill()
                }
            }
            b.resume(); a.resume()

            a.send(.notification(JSONRPCNotification(method: "big", params: .object(["blob": .string(big)]))))
            wait(for: [received], timeout: 10)
            XCTAssertEqual(gotLen, big.count, "the whole large payload reassembled")
            a.stop(); b.stop()
        }
    }

    /// Feed a single transport's READ fd by hand, one byte at a time across the
    /// header/body boundary, to prove the buffer reassembles split reads. We don't
    /// use a peer transport here — just the raw write end of a pipe.
    func testFramingReassemblesByteByByteSplitReads() {
        let pipe = Pipe()
        let t = StdioTransport(read: pipe.fileHandleForReading,
                               write: FileHandle.nullDevice,
                               label: "split")
        let received = expectation(description: "frame reassembles from 1-byte reads")
        var got: JSONRPCNotification?
        t.onReceive = { message in
            if case .notification(let n) = message { got = n; received.fulfill() }
        }
        t.resume()

        // Build a real frame, then dribble it one byte at a time.
        let payload = try! RPCCodec.encode(.notification(JSONRPCNotification(
            method: "drip", params: .object(["v": .number(7)]))))
        var frame = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        frame.append(payload)

        DispatchQueue.global().async {
            for byte in frame {
                pipe.fileHandleForWriting.write(Data([byte]))
                usleep(200)   // give the read source a chance to wake mid-frame
            }
        }
        wait(for: [received], timeout: 10)
        XCTAssertEqual(got?.method, "drip")
        XCTAssertEqual(got?.params?["v"]?.intValue, 7)
        t.stop()
    }

    /// Re-entrancy: a receive handler that itself calls `send` (the exact shape of
    /// a plugin emitting `showToast` from inside an inbound `host.invokeAction`).
    /// Must not deadlock or crash, and the reply must arrive back at the peer.
    func testFramingReentrantSendFromReceiveHandlerNoDeadlock() {
        let (a, b, pipes) = connectedPair()
        withExtendedLifetime(pipes) {
            let replyBack = expectation(description: "A receives the reply B sent from inside its handler")
            b.onReceive = { message in
                guard case .notification(let n) = message, n.method == RPCMethods.invokeAction else { return }
                // Sending from WITHIN delivery — the re-entrant case.
                b.send(.notification(JSONRPCNotification(method: RPCMethods.toast)))
                b.send(.notification(JSONRPCNotification(method: RPCMethods.log)))
            }
            var backMethods: [String] = []
            a.onReceive = { message in
                if case .notification(let n) = message {
                    backMethods.append(n.method)
                    if backMethods.count == 2 { replyBack.fulfill() }
                }
            }
            b.resume(); a.resume()

            a.send(.notification(JSONRPCNotification(method: RPCMethods.invokeAction)))
            wait(for: [replyBack], timeout: 5)
            XCTAssertEqual(backMethods, [RPCMethods.toast, RPCMethods.log],
                           "re-entrant frames sent from a handler arrive in order")
            a.stop(); b.stop()
        }
    }

    func testStdioTransportFiresOnCloseAtEOF() {
        let pipe = Pipe()
        let t = StdioTransport(read: pipe.fileHandleForReading,
                               write: FileHandle.nullDevice,
                               label: "eof")
        let closed = expectation(description: "onClose fires when the write end closes")
        t.onClose = { closed.fulfill() }
        t.resume()
        // Close the write end → reader sees EOF.
        try? pipe.fileHandleForWriting.close()
        wait(for: [closed], timeout: 5)
        t.stop()
    }

    // MARK: - Real child integration (guarded; skipped without the product)

    /// Locate the built `vee-plugin-host`: explicit env override first, then walk
    /// out from this test bundle to find a sibling `vee-plugin-host`, then a few
    /// known scratch build dirs. `throw XCTSkip` if not found so CI without the
    /// product is skipped rather than failed.
    private func locatePluginHost() throws -> URL {
        let fm = FileManager.default
        if let explicit = ProcessInfo.processInfo.environment["VEE_PLUGIN_HOST"],
           fm.isExecutableFile(atPath: explicit) {
            return URL(fileURLWithPath: explicit)
        }

        var candidates: [URL] = []
        // The test bundle lives under the build dir; its containing dir usually
        // holds sibling executables (or is one/two levels from them).
        let bundleDir = Bundle(for: type(of: self)).bundleURL.deletingLastPathComponent()
        for dir in [bundleDir, bundleDir.deletingLastPathComponent()] {
            candidates.append(dir.appendingPathComponent("vee-plugin-host"))
        }
        // Known scratch paths used by this wave's build commands.
        for base in ["/tmp/vee-build/r2-oop/debug",
                     "/tmp/vee-build/r2-oop/arm64-apple-macosx/debug",
                     "/tmp/vee-build/r2-oop/x86_64-apple-macosx/debug"] {
            candidates.append(URL(fileURLWithPath: base).appendingPathComponent("vee-plugin-host"))
        }

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }
        throw XCTSkip("""
            vee-plugin-host binary not found. Build it and/or set VEE_PLUGIN_HOST, e.g.:
              swift build --scratch-path /tmp/vee-build/r2-oop
              VEE_PLUGIN_HOST=/tmp/vee-build/r2-oop/debug/vee-plugin-host \\
                swift test --filter VeeEngineTests --scratch-path /tmp/vee-build/r2-oop
            Searched: \(candidates.map(\.path).joined(separator: ", "))
            """)
    }

    private func essentialsManifest() -> PluginManifest {
        PluginManifest(
            id: "com.vee.essentials", name: "Essentials", version: "1.0.0",
            entrypoint: "com.vee.essentials.bundle.js",
            commands: [PluginCommand(name: "view", title: "View", mode: .view)],
            capabilities: Capabilities())   // no bridges — fully deterministic
    }

    private func essentialsSource() throws -> String {
        let url = VeeEngineTests.repoRoot()
            .appendingPathComponent("plugins/fixtures/com.vee.essentials.bundle.js")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Collects `plugin.*` frames the child emits, thread-safely, and lets a test
    /// await the first `plugin.render`.
    private final class PluginFrameSink {
        private let lock = NSLock()
        private(set) var renders: [RenderParams] = []
        private(set) var allMethods: [String] = []
        var onRender: ((RenderParams) -> Void)?

        func ingest(_ message: JSONRPCMessage) {
            guard case .notification(let n) = message, let params = n.params else { return }
            lock.lock()
            allMethods.append(n.method)
            lock.unlock()
            if n.method == RPCMethods.render,
               let data = try? JSONEncoder().encode(params),
               let rp = try? JSONDecoder().decode(RenderParams.self, from: data) {
                lock.lock(); renders.append(rp); lock.unlock()
                onRender?(rp)
            }
        }
    }

    func testRealChildLoadActivateRendersEssentials() throws {
        let exe = try locatePluginHost()
        let host = ChildProcessHost(executableURL: exe)
        let sink = PluginFrameSink()

        let firstRender = expectation(description: "child emits plugin.render for essentials")
        firstRender.assertForOverFulfill = false
        sink.onRender = { _ in firstRender.fulfill() }
        host.onPluginMessage = { sink.ingest($0) }

        try host.start()
        defer { host.terminate() }

        try host.loadAndActivate(manifest: essentialsManifest(),
                                 source: try essentialsSource(),
                                 command: "view")

        wait(for: [firstRender], timeout: 15)

        // The first render is a single replace at "" carrying the whole tree.
        let render = try XCTUnwrap(sink.renders.first)
        XCTAssertEqual(render.pluginId, "com.vee.essentials")
        XCTAssertEqual(render.patch.first?.op, .replace)
        XCTAssertEqual(render.patch.first?.path, "")

        // Reconstruct the tree from that whole-tree replace and assert essentials'
        // expected output: a root → list with the six known items, first item's
        // icon + action.
        let tree = try XCTUnwrap(render.patch.first?.value)
        let root = try XCTUnwrap(tree.objectValue)
        XCTAssertEqual(root["tag"]?.stringValue, "root")
        let list = try XCTUnwrap(root["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(list["tag"]?.stringValue, "list")
        let items = try XCTUnwrap(list["children"]?.arrayValue)
        let titles = items.compactMap { $0.objectValue?["props"]?.objectValue?["title"]?.stringValue }
        XCTAssertEqual(titles,
                       ["Search Files", "Clipboard History", "Calculator",
                        "System Settings", "Capture Screenshot", "Lock Screen"])
        let firstItem = try XCTUnwrap(items.first?.objectValue)
        XCTAssertEqual(firstItem["props"]?.objectValue?["icon"]?.stringValue, "doc.text.magnifyingglass")
        let firstAction = firstItem["children"]?.arrayValue?.first?
            .objectValue?["children"]?.arrayValue?.first?.objectValue
        XCTAssertEqual(firstAction?["tag"]?.stringValue, "action")
        XCTAssertEqual(firstAction?["props"]?.objectValue?["actionId"]?.stringValue, "search-files")
    }

    func testRealChildCrashIsolationAndRestart() throws {
        let exe = try locatePluginHost()
        let host = ChildProcessHost(executableURL: exe)

        // ── Phase 1: a live child rendering essentials ──────────────────────────
        let sink1 = PluginFrameSink()
        let render1 = expectation(description: "first child renders")
        render1.assertForOverFulfill = false
        sink1.onRender = { _ in render1.fulfill() }
        host.onPluginMessage = { sink1.ingest($0) }

        let terminated = expectation(description: "onTermination fires when child dies")
        var termInfo: ChildProcessHost.TerminationInfo?
        host.onTermination = { info in termInfo = info; terminated.fulfill() }

        try host.start()
        defer { host.terminate() }
        try host.loadAndActivate(manifest: essentialsManifest(),
                                 source: try essentialsSource(), command: "view")
        wait(for: [render1], timeout: 15)
        XCTAssertTrue(host.isRunning)

        // ── Phase 2: kill the child (simulates a plugin crash) ─────────────────
        // SIGKILL the process directly so this looks like an uncaught crash, not a
        // clean exit. The PARENT (this test process) must be unharmed.
        host.terminate()
        wait(for: [terminated], timeout: 10)
        XCTAssertNotNil(termInfo, "termination info delivered")
        XCTAssertFalse(host.isRunning, "host reports the child is gone")
        // The test process is obviously still alive to run this very assertion —
        // crash isolation holds: the child dying did not take us down.

        // ── Phase 3: restart brings it back; a second activate works ───────────
        let sink2 = PluginFrameSink()
        let render2 = expectation(description: "restarted child renders again")
        render2.assertForOverFulfill = false
        sink2.onRender = { _ in render2.fulfill() }
        host.onPluginMessage = { sink2.ingest($0) }

        try host.restart()
        XCTAssertTrue(host.isRunning, "restart spawned a fresh child")
        // The child is stateless across restarts, so re-load + activate.
        try host.loadAndActivate(manifest: essentialsManifest(),
                                 source: try essentialsSource(), command: "view")
        wait(for: [render2], timeout: 15)

        let render = try XCTUnwrap(sink2.renders.first)
        XCTAssertEqual(render.pluginId, "com.vee.essentials")
        let tree = try XCTUnwrap(render.patch.first?.value)
        let titles = tree.objectValue?["children"]?.arrayValue?.first?
            .objectValue?["children"]?.arrayValue?
            .compactMap { $0.objectValue?["props"]?.objectValue?["title"]?.stringValue }
        XCTAssertEqual(titles?.count, 6, "the restarted child renders the full essentials list")
    }
}
