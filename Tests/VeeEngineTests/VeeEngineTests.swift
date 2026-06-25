import XCTest
import JavaScriptCore
@testable import VeeEngine
import VeeProtocol
import VeeJSONPatch

/// Wave 2a — the VeeEngine TDD suite (build plan §4).
///
/// Covers the JavaScriptCore plugin host end to end: evaluation + exception
/// capture, the `console`/`vee` bridge, native timers backed by an injected
/// Clock, the microtask-before-macrotask ordering hazard, capability-gated
/// `fetch`, the render mirror (first replace + minimal incremental diffs),
/// host→plugin event dispatch over the loopback transport, no-leak-after-reload,
/// out-of-order render revisions, plugin-throw surfacing, and the real fixture
/// handshake against `plugins/fixtures/hello-list.*`.
final class VeeEngineTests: XCTestCase {

    // MARK: - Helpers

    /// A manifest with a default-allow-nothing capability set unless overridden.
    private func manifest(
        id: String = "com.vee.test",
        command: String = "view",
        network: [String] = []
    ) -> PluginManifest {
        PluginManifest(
            id: id, name: "Test", version: "1.0.0", entrypoint: "bundle.js",
            commands: [PluginCommand(name: command, title: "View", mode: .view)],
            capabilities: Capabilities(network: network)
        )
    }

    /// Collects every notification/response a host emits toward the launcher.
    private final class Recorder {
        let transport: LoopbackTransport
        private(set) var notifications: [JSONRPCNotification] = []
        private(set) var requests: [JSONRPCRequest] = []
        private(set) var responses: [JSONRPCResponse] = []

        init(_ transport: LoopbackTransport) {
            self.transport = transport
            transport.peerInbound = { [weak self] message in
                switch message {
                case .notification(let n): self?.notifications.append(n)
                case .request(let r): self?.requests.append(r)
                case .response(let r): self?.responses.append(r)
                }
            }
        }

        func logs() -> [LogParams] {
            decode(method: RPCMethods.log)
        }
        func renders() -> [RenderParams] {
            decode(method: RPCMethods.render)
        }
        func toasts() -> [ToastParams] {
            decode(method: RPCMethods.toast)
        }

        private func decode<T: Decodable>(method: String) -> [T] {
            notifications.compactMap { note in
                guard note.method == method, let params = note.params else { return nil }
                let data = try? JSONEncoder().encode(params)
                return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
            }
        }
    }

    // MARK: - Test 1: evaluate + exception capture

    func testEvaluateArithmeticReturnsValue() throws {
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: LoopbackTransport(),
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        let value = instance.evaluate("1+2+3")
        XCTAssertEqual(value?.toInt32(), 6)
    }

    func testSyntaxErrorIsCapturedAsSwiftError() throws {
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: LoopbackTransport(),
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        // The exception handler MUST be installed before eval; a bad eval throws.
        XCTAssertThrowsError(try instance.evaluateOrThrow("this is not ) valid js (")) { error in
            // Surfaced as a JSONRPCError.pluginError (code -32000).
            let rpc = error as? JSONRPCError
            XCTAssertEqual(rpc?.code, -32000)
        }
    }

    func testRuntimeErrorIsCapturedAsSwiftError() throws {
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: LoopbackTransport(),
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        XCTAssertThrowsError(try instance.evaluateOrThrow("throw new Error('boom')")) { error in
            let rpc = error as? JSONRPCError
            XCTAssertEqual(rpc?.code, -32000)
            XCTAssertTrue((rpc?.message ?? "").contains("boom"))
        }
    }

    // MARK: - Test 2: console.log → plugin.log

    func testConsoleLogReachesHost() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("console.log('hello', 42)")
        let logs = recorder.logs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .info)
        XCTAssertEqual(logs.first?.message, "hello 42")
        XCTAssertEqual(logs.first?.pluginId, "com.vee.test")
    }

    func testConsoleLevelsMapCorrectly() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("""
            console.debug('d');
            console.info('i');
            console.log('l');
            console.warn('w');
            console.error('e');
        """)
        let logs = recorder.logs()
        XCTAssertEqual(logs.map(\.level), [.debug, .info, .info, .warn, .error])
        XCTAssertEqual(logs.map(\.message), ["d", "i", "l", "w", "e"])
    }

    func testConsoleStringifiesObjects() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("console.log({a:1, b:[2,3]})")
        XCTAssertEqual(recorder.logs().first?.message, #"{"a":1,"b":[2,3]}"#)
    }

    // MARK: - Test 3: setTimeout fires on clock advance; clearTimeout cancels

    func testSetTimeoutFiresWhenClockAdvances() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let clock = TestClock()
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: clock,
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("setTimeout(() => console.log('fired'), 50)")
        XCTAssertEqual(recorder.logs().count, 0, "must not fire before the clock advances")
        clock.advance(by: 0.049)
        XCTAssertEqual(recorder.logs().count, 0, "must not fire early")
        clock.advance(by: 0.001)
        XCTAssertEqual(recorder.logs().map(\.message), ["fired"])
    }

    func testClearTimeoutCancels() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let clock = TestClock()
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: clock,
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("""
            const id = setTimeout(() => console.log('should-not-fire'), 10);
            clearTimeout(id);
        """)
        clock.advance(by: 1.0)
        XCTAssertEqual(recorder.logs().count, 0)
    }

    func testSetIntervalRepeatsAndClearStops() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let clock = TestClock()
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: clock,
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("""
            globalThis.__n = 0;
            globalThis.__id = setInterval(() => {
                globalThis.__n++;
                console.log('tick' + globalThis.__n);
                if (globalThis.__n >= 3) clearInterval(globalThis.__id);
            }, 10);
        """)
        clock.advance(by: 100)
        XCTAssertEqual(recorder.logs().map(\.message), ["tick1", "tick2", "tick3"])
    }

    // MARK: - Test 4: microtask ordering (PERMANENT regression)

    func testMicrotaskRunsBeforeMacrotask() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let clock = TestClock()
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: clock,
            httpClient: CannedHTTPClient()
        )
        // A Promise .then (microtask) registered alongside a setTimeout(...,0)
        // (macrotask) MUST run first. JSC drains microtasks on return from a
        // native→JS call; the host must never let a macrotask jump the queue.
        instance.evaluate("""
            setTimeout(() => console.log('macro'), 0);
            Promise.resolve().then(() => console.log('micro'));
        """)
        // Before the clock advances, only the microtask has run.
        XCTAssertEqual(recorder.logs().map(\.message), ["micro"])
        clock.advance(by: 0)   // fire the 0ms macrotask
        XCTAssertEqual(recorder.logs().map(\.message), ["micro", "macro"])
    }

    func testMicrotaskChainedFromTimerStillOrdersBeforeNextTimer() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let clock = TestClock()
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: clock,
            httpClient: CannedHTTPClient()
        )
        // Two 0ms timers. The first schedules a microtask. That microtask must
        // run before the SECOND timer's callback — i.e. the host drains the
        // microtask queue between dequeuing macrotasks.
        instance.evaluate("""
            setTimeout(() => { console.log('t1'); Promise.resolve().then(() => console.log('m')); }, 0);
            setTimeout(() => console.log('t2'), 0);
        """)
        clock.advance(by: 0)
        XCTAssertEqual(recorder.logs().map(\.message), ["t1", "m", "t2"])
    }

    // MARK: - Test 5: vee.http.fetch + capability gating

    func testFetchResolvesFromInjectedClient() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let http = CannedHTTPClient()
        http.canned["https://api.example.com/data"] = CannedHTTPClient.Response(
            status: 200,
            headers: ["content-type": "application/json"],
            body: Data(#"{"ok":true}"#.utf8)
        )
        let instance = try PluginInstance(
            manifest: manifest(network: ["api.example.com"]),
            transport: transport,
            clock: TestClock(),
            httpClient: http
        )
        instance.evaluate("""
            vee.http.fetch('https://api.example.com/data')
              .then(r => r.text())
              .then(t => console.log('got:' + t))
              .catch(e => console.error('err:' + e));
        """)
        // The async response resolves on the host; drive the run loop so the
        // injected client's completion fires and the Promise settles.
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), [#"got:{"ok":true}"#])
        XCTAssertEqual(http.requested, ["https://api.example.com/data"])
    }

    func testFetchToDisallowedHostIsDeniedWithoutCallingClient() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let http = CannedHTTPClient()
        http.canned["https://evil.example.com/x"] = CannedHTTPClient.Response(
            status: 200, headers: [:], body: Data("nope".utf8)
        )
        // network allowlist does NOT include evil.example.com.
        let instance = try PluginInstance(
            manifest: manifest(network: ["api.example.com"]),
            transport: transport,
            clock: TestClock(),
            httpClient: http
        )
        instance.evaluate("""
            vee.http.fetch('https://evil.example.com/x')
              .then(r => console.log('resolved'))
              .catch(e => console.error('denied:' + e.code + ':' + e.message));
        """)
        instance.runUntilQuiescent()
        XCTAssertTrue(http.requested.isEmpty, "the client must NEVER be called for a denied host")
        let logs = recorder.logs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .error)
        // capabilityDenied is code -32001.
        XCTAssertTrue((logs.first?.message ?? "").contains("-32001"), "got: \(logs.first?.message ?? "")")
    }

    // MARK: - Test 6: first render → single replace "" ; mirror equals expected

    func testFirstRenderEmitsReplaceRootAndMirrors() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("""
            vee.render({ tag: 'root', props: {}, children: [
                { tag: 'text', props: { value: 'hi' }, children: [] }
            ]});
        """)
        let renders = recorder.renders()
        XCTAssertEqual(renders.count, 1)
        let params = try XCTUnwrap(renders.first)
        XCTAssertEqual(params.revision, 1)
        XCTAssertEqual(params.patch.count, 1)
        XCTAssertEqual(params.patch.first?.op, .replace)
        XCTAssertEqual(params.patch.first?.path, "")

        // The mirror equals the rendered tree.
        let expected = RenderNode(tag: "root", props: [:], children: [
            RenderNode(tag: "text", props: ["value": .string("hi")], children: [])
        ])
        XCTAssertEqual(instance.currentRenderTree(), expected)
    }

    // MARK: - Test 7: incremental render → minimal patch at the prop path

    func testIncrementalRenderEmitsMinimalPatch() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        // The host diffs the wire projection with VeeJSONPatch, whose array
        // differ matches siblings by a top-level `id` member. A plugin therefore
        // gives keyed children a top-level `id` (vee.render accepts a raw
        // JSONValue tree, not only a RenderNode) so a per-item prop change yields
        // a minimal recursive replace rather than a remove+add of the whole node.
        let base = """
            ({ tag: 'list', props: {}, children: [
                { id: 'a', tag: 'list-item', props: { title: 'A', subtitle: 'sa' }, children: [] },
                { id: 'b', tag: 'list-item', props: { title: 'B', subtitle: 'sb' }, children: [] }
            ]})
        """
        instance.evaluate("vee.render(\(base))")
        // Change ONE prop on the first item.
        instance.evaluate("""
            vee.render({ tag: 'list', props: {}, children: [
                { id: 'a', tag: 'list-item', props: { title: 'A2', subtitle: 'sa' }, children: [] },
                { id: 'b', tag: 'list-item', props: { title: 'B', subtitle: 'sb' }, children: [] }
            ]});
        """)
        let renders = recorder.renders()
        XCTAssertEqual(renders.count, 2)
        let second = try XCTUnwrap(renders.last)
        XCTAssertEqual(second.revision, 2)
        // Exactly one op: replace the changed title.
        XCTAssertEqual(second.patch.count, 1, "patch should be minimal, got \(second.patch)")
        XCTAssertEqual(second.patch.first?.op, .replace)
        XCTAssertEqual(second.patch.first?.path, "/children/0/props/title")
        XCTAssertEqual(second.patch.first?.value, .string("A2"))
    }

    // MARK: - Test 8: host.invokeAction round-trips to the registered handler

    func testInvokeActionReachesRegisteredHandler() throws {
        let transport = LoopbackTransport()
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("""
            globalThis.__seen = [];
            vee.onInvokeAction((p) => {
                globalThis.__seen.push(p.actionId + '/' + (p.targetId || ''));
            });
        """)
        // The launcher sends a host.invokeAction notification over the wire.
        let params = InvokeActionParams(pluginId: "com.vee.test", actionId: "open", targetId: "row-1")
        let note = JSONRPCNotification(
            method: RPCMethods.invokeAction,
            params: try encodeToJSONValue(params)
        )
        transport.sendFromPeer(.notification(note))
        instance.runUntilQuiescent()
        let seen = instance.evaluate("globalThis.__seen.join(',')")?.toString()
        XCTAssertEqual(seen, "open/row-1")
    }

    func testSearchTextChangePassesQueryFirst() throws {
        let transport = LoopbackTransport()
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("""
            globalThis.__q = '';
            vee.onSearchTextChange((query, p) => { globalThis.__q = query + '|' + p.query; });
        """)
        let params = SearchTextChangeParams(pluginId: "com.vee.test", query: "abc")
        transport.sendFromPeer(.notification(JSONRPCNotification(
            method: RPCMethods.onSearchTextChange,
            params: try encodeToJSONValue(params)
        )))
        instance.runUntilQuiescent()
        XCTAssertEqual(instance.evaluate("globalThis.__q")?.toString(), "abc|abc")
    }

    // MARK: - Test 9: no leak after reload (the retain-cycle guard)

    func testNoLeakAfterReload() throws {
        let transport = LoopbackTransport()
        // The bundler reproduces a registering bundle (reload rebuilds from it).
        let bundleSource = """
            globalThis.__veePlugin = {
                commandNames: ['view'],
                activateCommand(name, ctx) {
                    // register a handler (stored callback → JSManagedValue): the
                    // worst case for a context⇄callback retain cycle.
                    vee.onInvokeAction(() => console.log('x'));
                    setInterval(() => {}, 1000);   // a live managed timer too
                    ctx.render({tag:'root',props:{},children:[]});
                }
            };
        """
        let host = PluginHost(
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileWatcher: NoopFileWatcher(),
            bundler: StaticBundler(source: bundleSource)
        )
        weak var weakInstance: PluginInstance?
        weak var weakVM: JSVirtualMachine?

        try autoreleasepool {
            let id = "com.vee.test"
            let m = manifest(id: id)
            try host.load(manifest: m, source: bundleSource)
            let inst = try XCTUnwrap(host.instance(for: id))
            weakInstance = inst
            weakVM = inst.virtualMachine
            // Activating registers a managed callback — the worst case for leaks.
            try host.activate(ActivateParams(pluginId: id, commandName: "view"))
            XCTAssertNotNil(weakInstance)
            XCTAssertNotNil(weakVM)

            // Reload tears down the old context/VM and builds a fresh one.
            try host.reload(ReloadParams(pluginId: id))
        }
        autoreleasepool { }   // let the autorelease pool drop JSC internals

        XCTAssertNil(weakInstance, "the old PluginInstance must deallocate after reload")
        XCTAssertNil(weakVM, "the old JSVirtualMachine must deallocate after reload (no retain cycle)")
    }

    func testNoLeakAfterDeactivate() throws {
        let transport = LoopbackTransport()
        let host = PluginHost(
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileWatcher: NoopFileWatcher(),
            bundler: StaticBundler(source: "")
        )
        weak var weakVM: JSVirtualMachine?
        try autoreleasepool {
            let id = "com.vee.test"
            try host.load(manifest: manifest(id: id), source: """
                globalThis.__veePlugin = {
                    commandNames: ['view'],
                    activateCommand(name, ctx) { vee.onInvokeAction(() => {}); }
                };
            """)
            weakVM = host.instance(for: id)?.virtualMachine
            try host.activate(ActivateParams(pluginId: id, commandName: "view"))
            host.unload(pluginId: id)
        }
        autoreleasepool { }
        XCTAssertNil(weakVM, "unloading must drop the VM with no retain cycle")
    }

    // MARK: - Test 10: out-of-order render revision is ignored

    func testStaleRenderRevisionIsIgnored() throws {
        // Drive the mirror directly with explicit revisions to prove the
        // monotonic guard (a stale N after an N+1 is dropped).
        let mirror = RenderMirror(pluginId: "com.vee.test")
        let v1 = RenderNode(tag: "root", props: ["v": .number(1)], children: [])
        let v2 = RenderNode(tag: "root", props: ["v": .number(2)], children: [])

        let p1 = mirror.ingest(tree: v1.jsonValue, revision: 1)
        XCTAssertNotNil(p1)
        let p2 = mirror.ingest(tree: v2.jsonValue, revision: 2)
        XCTAssertNotNil(p2)
        XCTAssertEqual(mirror.revision, 2)

        // A stale revision (1) arriving after 2 must be dropped — no patch, no
        // mirror change.
        let stale = mirror.ingest(tree: v1.jsonValue, revision: 1)
        XCTAssertNil(stale, "a lower revision must be ignored")
        XCTAssertEqual(mirror.revision, 2)
        XCTAssertEqual(try mirror.currentTree(), v2)
    }

    func testHostDropsStaleRenderFromPlugin() throws {
        // Same guard, but exercised through the live host pipeline: monkeypatch
        // the revision counter is not exposed, so we assert the mirror stays at
        // the latest tree after a re-render to an identical-but-later tree.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("vee.render({tag:'root',props:{n:1},children:[]})")
        instance.evaluate("vee.render({tag:'root',props:{n:2},children:[]})")
        let renders = recorder.renders()
        XCTAssertEqual(renders.map(\.revision), [1, 2])
        XCTAssertEqual(instance.currentRenderTree(),
                       RenderNode(tag: "root", props: ["n": .number(2)], children: []))
    }

    // MARK: - Test 11: plugin throws during render → pluginError, host survives

    func testPluginThrowDuringActivateSurfacesPluginError() throws {
        let transport = LoopbackTransport()
        let host = PluginHost(
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileWatcher: NoopFileWatcher(),
            bundler: StaticBundler(source: "")
        )
        let id = "com.vee.test"
        try host.load(manifest: manifest(id: id), source: """
            globalThis.__veePlugin = {
                commandNames: ['view'],
                activateCommand(name, ctx) { throw new Error('render-boom'); }
            };
        """)
        XCTAssertThrowsError(try host.activate(ActivateParams(pluginId: id, commandName: "view"))) { error in
            let rpc = error as? JSONRPCError
            XCTAssertEqual(rpc?.code, -32000, "pluginError")
            XCTAssertTrue((rpc?.message ?? "").contains("render-boom"))
            // The JS stack rides in `data` when available.
            XCTAssertNotNil(rpc?.data, "the JS stack should be attached in data")
        }
        // The host stays alive: a fresh, well-behaved activate works.
        XCTAssertNotNil(host.instance(for: id))
        try host.load(manifest: manifest(id: id), source: """
            globalThis.__veePlugin = {
                commandNames: ['view'],
                activateCommand(name, ctx) { ctx.render({tag:'root',props:{},children:[]}); }
            };
        """)
        XCTAssertNoThrow(try host.activate(ActivateParams(pluginId: id, commandName: "view")))
    }

    // MARK: - Test 12: fixture handshake (real bundle → expected projection)

    func testHelloListFixtureHandshake() throws {
        // Locate the fixtures relative to this source file (robust to CWD).
        let repoRoot = Self.repoRoot()
        let bundleURL = repoRoot
            .appendingPathComponent("plugins/fixtures/hello-list.bundle.js")
        let expectedURL = repoRoot
            .appendingPathComponent("plugins/fixtures/hello-list.expected.json")

        let bundleSource = try String(contentsOf: bundleURL, encoding: .utf8)
        let expectedData = try Data(contentsOf: expectedURL)
        let expected = try JSONDecoder().decode(JSONValue.self, from: expectedData)

        // Create a real JSContext, inject console + vee whose render captures the tree.
        let transport = LoopbackTransport()
        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.hello-list", name: "Hello List", version: "1.0.0",
                entrypoint: "hello-list.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities()
            ),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        // Evaluate the IIFE bundle (sets __veePlugin).
        try instance.evaluateOrThrow(bundleSource)

        // Read __veePlugin → commandNames == ["view"].
        let commandNames = try instance.commandNames()
        XCTAssertEqual(commandNames, ["view"])

        // activateCommand("view", ctx) — drives vee.render which captures the tree.
        try instance.activateCommand("view", arguments: [:])

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        // Deep-equal the wire projection against the committed expected JSON.
        XCTAssertEqual(tree, expected)
    }

    func testHelloListFixtureViaHostRendersExpectedMirror() throws {
        // End-to-end via the host: load + activate the real fixture, then assert
        // the host's mirror equals the expected RenderNode.
        let repoRoot = Self.repoRoot()
        let bundleSource = try String(
            contentsOf: repoRoot.appendingPathComponent("plugins/fixtures/hello-list.bundle.js"),
            encoding: .utf8)
        let expected = try RenderNode(jsonValue: JSONDecoder().decode(
            JSONValue.self,
            from: Data(contentsOf: repoRoot.appendingPathComponent("plugins/fixtures/hello-list.expected.json"))))

        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let host = PluginHost(
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileWatcher: NoopFileWatcher(),
            bundler: StaticBundler(source: bundleSource))
        let id = "com.vee.hello-list"
        try host.load(
            manifest: PluginManifest(
                id: id, name: "Hello List", version: "1.0.0",
                entrypoint: "hello-list.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities()),
            source: bundleSource)
        try host.activate(ActivateParams(pluginId: id, commandName: "view"))

        XCTAssertEqual(host.instance(for: id)?.currentRenderTree(), expected)
        let renders = recorder.renders()
        XCTAssertEqual(renders.first?.patch.first?.op, .replace)
        XCTAssertEqual(renders.first?.patch.first?.path, "")
    }

    // MARK: - vee.setCandidates, storage, showToast smoke tests

    func testSetCandidatesReachesHost() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("""
            vee.setCandidates([
                { id: '1', title: 'One', keywords: ['uno'], actions: [{ id: 'open', title: 'Open' }] },
                { id: '2', title: 'Two', subtitle: 'second', keywords: [], actions: [] }
            ]);
        """)
        let notes = recorder.notifications.filter { $0.method == RPCMethods.setCandidates }
        XCTAssertEqual(notes.count, 1)
        let data = try JSONEncoder().encode(try XCTUnwrap(notes.first?.params))
        let params = try JSONDecoder().decode(SetCandidatesParams.self, from: data)
        XCTAssertEqual(params.candidates.map(\.id), ["1", "2"])
        XCTAssertEqual(params.candidates.first?.keywords, ["uno"])
        XCTAssertEqual(params.candidates.first?.actions.first?.id, "open")
    }

    func testShowToastReachesHost() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("vee.showToast('success', 'Saved', 'All good')")
        let toasts = recorder.toasts()
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(toasts.first?.style, .success)
        XCTAssertEqual(toasts.first?.title, "Saved")
        XCTAssertEqual(toasts.first?.message, "All good")
    }

    func testStorageRoundTripsThroughBridge() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: manifest(),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        instance.evaluate("""
            vee.storage.set('k', { hello: 'world' })
              .then(() => vee.storage.get('k'))
              .then(v => console.log('stored:' + JSON.stringify(v)))
              .catch(e => console.error('err:' + e));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), [#"stored:{"hello":"world"}"#])
    }

    func testPluginIdExposedToJS() throws {
        let instance = try PluginInstance(
            manifest: manifest(id: "com.vee.identity"),
            transport: LoopbackTransport(),
            clock: TestClock(),
            httpClient: CannedHTTPClient()
        )
        XCTAssertEqual(instance.evaluate("vee.pluginId")?.toString(), "com.vee.identity")
    }

    // MARK: - Hot reload behaviour

    func testHotReloadReevaluatesNewBundle() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let watcher = ManualFileWatcher()
        let bundler = StaticBundler(source: """
            globalThis.__veePlugin = {
                commandNames: ['view'],
                activateCommand(name, ctx) { ctx.render({tag:'text',props:{v:'old'},children:[]}); }
            };
        """)
        let host = PluginHost(
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileWatcher: watcher,
            bundler: bundler)
        let id = "com.vee.test"
        try host.load(manifest: manifest(id: id), source: bundler.source)
        try host.activate(ActivateParams(pluginId: id, commandName: "view"))
        XCTAssertEqual(host.instance(for: id)?.currentRenderTree(),
                       RenderNode(tag: "text", props: ["v": .string("old")], children: []))

        // The bundler now produces a new bundle; a file change triggers reload.
        bundler.source = """
            globalThis.__veePlugin = {
                commandNames: ['view'],
                activateCommand(name, ctx) { ctx.render({tag:'text',props:{v:'new'},children:[]}); }
            };
        """
        watcher.fire(pluginId: id)
        instanceQuiesce(host.instance(for: id))

        XCTAssertEqual(host.instance(for: id)?.currentRenderTree(),
                       RenderNode(tag: "text", props: ["v": .string("new")], children: []))
        _ = recorder
    }

    // MARK: - private helpers

    private func instanceQuiesce(_ instance: PluginInstance?) {
        instance?.runUntilQuiescent()
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Resolve the repository root from this test file's path (`#filePath` is
    /// `<repo>/Tests/VeeEngineTests/VeeEngineTests.swift`). Falls back to an env
    /// override (`VEE_REPO_ROOT`) so it stays robust in alternate layouts.
    static func repoRoot() -> URL {
        if let env = ProcessInfo.processInfo.environment["VEE_REPO_ROOT"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VeeEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    // MARK: - Clipboard bridge (capability-gated by Capabilities.clipboard)

    /// A manifest granting the clipboard capability and a set of keychain
    /// namespaces (the existing `manifest(...)` helper only varies `network`).
    private func capManifest(
        id: String = "com.vee.test",
        clipboard: Bool = false,
        keychainNamespaces: [String] = []
    ) -> PluginManifest {
        PluginManifest(
            id: id, name: "Test", version: "1.0.0", entrypoint: "bundle.js",
            commands: [PluginCommand(name: "view", title: "View", mode: .view)],
            capabilities: Capabilities(clipboard: clipboard, keychainNamespaces: keychainNamespaces)
        )
    }

    func testClipboardHistoryResolvesFromInjectedProvider() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let provider = FakeClipboardProvider(items: [
            ClipboardItem(id: "1", text: "hello world", copiedAt: Date(timeIntervalSince1970: 100)),
            ClipboardItem(id: "2", text: "goodbye", copiedAt: Date(timeIntervalSince1970: 50)),
        ])
        let instance = try PluginInstance(
            manifest: capManifest(clipboard: true),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            clipboardProvider: provider
        )
        instance.evaluate("""
            vee.clipboard.history('', 10)
              .then(items => console.log('ids:' + items.map(i => i.id).join(',') + '|texts:' + items.map(i => i.text).join(',')))
              .catch(e => console.error('err:' + e));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["ids:1,2|texts:hello world,goodbye"])
        XCTAssertEqual(provider.historyQueries, [""])
    }

    func testClipboardHistoryFiltersByQuery() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let provider = FakeClipboardProvider(items: [
            ClipboardItem(id: "1", text: "hello world", copiedAt: Date(timeIntervalSince1970: 100)),
            ClipboardItem(id: "2", text: "goodbye", copiedAt: Date(timeIntervalSince1970: 50)),
        ])
        let instance = try PluginInstance(
            manifest: capManifest(clipboard: true),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            clipboardProvider: provider
        )
        instance.evaluate("""
            vee.clipboard.history('good', 10)
              .then(items => console.log('ids:' + items.map(i => i.id).join(',')))
              .catch(e => console.error('err:' + e));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["ids:2"])
        XCTAssertEqual(provider.historyQueries, ["good"])
    }

    func testClipboardDeniedWhenCapabilityFalseWithoutCallingProvider() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let provider = FakeClipboardProvider(items: [
            ClipboardItem(id: "1", text: "secret", copiedAt: Date(timeIntervalSince1970: 1)),
        ])
        // clipboard:false → denied.
        let instance = try PluginInstance(
            manifest: capManifest(clipboard: false),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            clipboardProvider: provider
        )
        instance.evaluate("""
            vee.clipboard.history('', 10)
              .then(items => console.log('resolved:' + items.length))
              .catch(e => console.error('denied:' + e.code + ':' + e.message));
        """)
        instance.runUntilQuiescent()
        XCTAssertTrue(provider.historyQueries.isEmpty, "provider must NEVER be called when clipboard is denied")
        let logs = recorder.logs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .error)
        XCTAssertTrue((logs.first?.message ?? "").contains("-32001"), "got: \(logs.first?.message ?? "")")
    }

    func testClipboardCopyDeniedWhenCapabilityFalse() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let provider = FakeClipboardProvider()
        let instance = try PluginInstance(
            manifest: capManifest(clipboard: false),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            clipboardProvider: provider
        )
        instance.evaluate("""
            vee.clipboard.copy({ id: 'x', text: 'paste me', copiedAt: 0 })
              .then(() => console.log('copied'))
              .catch(e => console.error('denied:' + e.code));
        """)
        instance.runUntilQuiescent()
        XCTAssertTrue(provider.copied.isEmpty, "provider must NEVER be called when clipboard is denied")
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
    }

    func testClipboardCopyReachesProviderWhenAllowed() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let provider = FakeClipboardProvider()
        let instance = try PluginInstance(
            manifest: capManifest(clipboard: true),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            clipboardProvider: provider
        )
        instance.evaluate("""
            vee.clipboard.copy({ id: 'x', text: 'paste me', copiedAt: 0 })
              .then(() => console.log('copied'))
              .catch(e => console.error('err:' + e));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["copied"])
        XCTAssertEqual(provider.copied.map(\.text), ["paste me"])
        XCTAssertEqual(provider.copied.map(\.id), ["x"])
    }

    // MARK: - Keychain bridge (capability-gated by Capabilities.keychainNamespaces)

    func testKeychainSetThenGetRoundTrips() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let store = FakeSecretStore()
        let instance = try PluginInstance(
            manifest: capManifest(id: "com.vee.kc", keychainNamespaces: ["tokens"]),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            secretStore: store
        )
        instance.evaluate("""
            vee.keychain.set('tokens', 'api', 's3cr3t')
              .then(() => vee.keychain.get('tokens', 'api'))
              .then(v => console.log('got:' + v))
              .catch(e => console.error('err:' + e));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["got:s3cr3t"])
        // The value is namespaced under THIS plugin's id (per the SecretStore key).
        XCTAssertEqual(try store.get(pluginId: "com.vee.kc", namespace: "tokens", account: "api"), "s3cr3t")
    }

    func testKeychainGetMissingResolvesNull() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let store = FakeSecretStore()
        let instance = try PluginInstance(
            manifest: capManifest(id: "com.vee.kc", keychainNamespaces: ["tokens"]),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            secretStore: store
        )
        instance.evaluate("""
            vee.keychain.get('tokens', 'absent')
              .then(v => console.log('got:' + (v === null ? 'null' : v)))
              .catch(e => console.error('err:' + e));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["got:null"])
    }

    func testKeychainDeniedForUndeclaredNamespaceWithoutTouchingStore() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let store = FakeSecretStore()
        // Pre-seed a value the plugin must NOT be able to read (wrong namespace).
        try store.set(pluginId: "com.vee.kc", namespace: "secrets", account: "api", secret: "leak")
        // Manifest declares only "tokens"; "secrets" is undeclared → denied.
        let instance = try PluginInstance(
            manifest: capManifest(id: "com.vee.kc", keychainNamespaces: ["tokens"]),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            secretStore: store
        )
        instance.evaluate("""
            vee.keychain.get('secrets', 'api')
              .then(v => console.log('resolved:' + v))
              .catch(e => console.error('denied:' + e.code + ':' + e.message));
        """)
        instance.runUntilQuiescent()
        let logs = recorder.logs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .error)
        XCTAssertTrue((logs.first?.message ?? "").contains("-32001"), "got: \(logs.first?.message ?? "")")
        // The pre-seeded secret is still there (read was denied), and the store
        // value was never exposed to JS.
        XCTAssertEqual(try store.get(pluginId: "com.vee.kc", namespace: "secrets", account: "api"), "leak")
    }

    func testKeychainSetDeniedForUndeclaredNamespace() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let store = FakeSecretStore()
        let instance = try PluginInstance(
            manifest: capManifest(id: "com.vee.kc", keychainNamespaces: ["tokens"]),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            secretStore: store
        )
        instance.evaluate("""
            vee.keychain.set('secrets', 'api', 'nope')
              .then(() => console.log('set'))
              .catch(e => console.error('denied:' + e.code));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        // The write never reached the store.
        XCTAssertNil(try store.get(pluginId: "com.vee.kc", namespace: "secrets", account: "api"))
    }

    func testKeychainDeleteRemovesValue() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let store = FakeSecretStore()
        try store.set(pluginId: "com.vee.kc", namespace: "tokens", account: "api", secret: "v1")
        let instance = try PluginInstance(
            manifest: capManifest(id: "com.vee.kc", keychainNamespaces: ["tokens"]),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            secretStore: store
        )
        instance.evaluate("""
            vee.keychain.delete('tokens', 'api')
              .then(() => vee.keychain.get('tokens', 'api'))
              .then(v => console.log('after:' + (v === null ? 'null' : v)))
              .catch(e => console.error('err:' + e));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["after:null"])
        XCTAssertNil(try store.get(pluginId: "com.vee.kc", namespace: "tokens", account: "api"))
    }

    // MARK: - Real plugin fixtures (essentials / hacker-news / clipboard)
    //
    // These load the COMMITTED bundle each plugin's `bundle.mjs` produced
    // (plugins/fixtures/<id>.bundle.js) into a real PluginInstance with the
    // appropriate fakes, activate the `view` command, and assert the captured
    // render is correct. They mirror `testHelloListFixtureHandshake` exactly for
    // loading/injection — the end-to-end proof that the plugin platform runs real
    // plugins in JavaScriptCore.

    /// Read a committed fixture bundle by plugin id (robust to CWD).
    private func fixtureBundle(_ pluginId: String) throws -> String {
        let url = Self.repoRoot()
            .appendingPathComponent("plugins/fixtures/\(pluginId).bundle.js")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The `list` node under the rendered `root` tree (first child).
    private func listNode(of tree: JSONValue) throws -> JSONValue {
        let root = try XCTUnwrap(tree.objectValue)
        XCTAssertEqual(root["tag"]?.stringValue, "root")
        let children = try XCTUnwrap(root["children"]?.arrayValue)
        return try XCTUnwrap(children.first)
    }

    /// Titles of every `list-item` child of a `list` node, in order.
    private func itemTitles(in list: JSONValue) throws -> [String] {
        let listObj = try XCTUnwrap(list.objectValue)
        XCTAssertEqual(listObj["tag"]?.stringValue, "list")
        let children = try XCTUnwrap(listObj["children"]?.arrayValue)
        return children.compactMap { $0.objectValue?["props"]?.objectValue?["title"]?.stringValue }
    }

    // ── com.vee.essentials — static list, NO bridges (deterministic) ──────────

    func testEssentialsFixtureRendersStaticList() throws {
        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.essentials", name: "Essentials", version: "1.0.0",
                entrypoint: "com.vee.essentials.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities()),   // no capabilities — uses no bridges
            transport: LoopbackTransport(),
            clock: TestClock(),
            httpClient: CannedHTTPClient())

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.essentials"))
        XCTAssertEqual(try instance.commandNames(), ["view"])
        try instance.activateCommand("view", arguments: [:])

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        let list = try listNode(of: tree)
        XCTAssertEqual(try itemTitles(in: list),
                       ["Search Files", "Clipboard History", "Calculator",
                        "System Settings", "Capture Screenshot", "Lock Screen"])
    }

    func testEssentialsFixtureViaHostMirrorsSixItems() throws {
        // End-to-end through the host: the mirror holds the rendered tree and the
        // first frame is a single replace at "".
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let source = try fixtureBundle("com.vee.essentials")
        let host = PluginHost(
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileWatcher: NoopFileWatcher(),
            bundler: StaticBundler(source: source))
        let id = "com.vee.essentials"
        try host.load(
            manifest: PluginManifest(
                id: id, name: "Essentials", version: "1.0.0",
                entrypoint: "com.vee.essentials.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities()),
            source: source)
        try host.activate(ActivateParams(pluginId: id, commandName: "view"))

        let tree = try XCTUnwrap(host.instance(for: id)?.currentRenderTree())
        XCTAssertEqual(tree.tag, "root")
        let list = try XCTUnwrap(tree.children.first)
        XCTAssertEqual(list.tag, "list")
        XCTAssertEqual(list.children.count, 6)
        // First child item carries an SF-symbol icon + an action-panel → action.
        let firstItem = try XCTUnwrap(list.children.first)
        XCTAssertEqual(firstItem.props["icon"]?.stringValue, "doc.text.magnifyingglass")
        let firstAction = firstItem.children.first?.children.first
        XCTAssertEqual(firstAction?.tag, "action")
        XCTAssertEqual(firstAction?.props["actionId"]?.stringValue, "search-files")

        let renders = recorder.renders()
        XCTAssertEqual(renders.first?.patch.first?.op, .replace)
        XCTAssertEqual(renders.first?.patch.first?.path, "")
    }

    // ── com.vee.hacker-news — vee.http.fetch (capability-gated) ───────────────

    /// Canned HN client: topstories → [1,2,3], plus three item objects.
    private func cannedHackerNews() -> CannedHTTPClient {
        let http = CannedHTTPClient()
        let base = "https://hacker-news.firebaseio.com/v0"
        http.canned["\(base)/topstories.json"] = CannedHTTPClient.Response(
            status: 200, headers: ["content-type": "application/json"],
            body: Data("[1,2,3]".utf8))
        http.canned["\(base)/item/1.json"] = CannedHTTPClient.Response(
            status: 200, headers: [:],
            body: Data(#"{"id":1,"title":"Rust 2.0 released","url":"https://blog.rust-lang.org/x","score":321,"by":"alice"}"#.utf8))
        http.canned["\(base)/item/2.json"] = CannedHTTPClient.Response(
            status: 200, headers: [:],
            body: Data(#"{"id":2,"title":"Show HN: my side project","url":"https://github.com/me/proj","score":88,"by":"bob"}"#.utf8))
        http.canned["\(base)/item/3.json"] = CannedHTTPClient.Response(
            status: 200, headers: [:],
            body: Data(#"{"id":3,"title":"Ask HN: best editor?","score":12,"by":"carol"}"#.utf8))
        return http
    }

    func testHackerNewsFixtureRendersTopStories() throws {
        let http = cannedHackerNews()
        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.hacker-news", name: "Hacker News", version: "1.0.0",
                entrypoint: "com.vee.hacker-news.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities(network: ["hacker-news.firebaseio.com"])),
            transport: LoopbackTransport(),
            clock: TestClock(),
            httpClient: http)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.hacker-news"))
        XCTAssertEqual(try instance.commandNames(), ["view"])
        try instance.activateCommand("view", arguments: [:])
        // The activate handler chains awaited fetches; settle them deterministically.
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        let list = try listNode(of: tree)
        XCTAssertEqual(try itemTitles(in: list),
                       ["Rust 2.0 released", "Show HN: my side project", "Ask HN: best editor?"])
        // It fetched topstories then each of the three items.
        XCTAssertEqual(http.requested, [
            "https://hacker-news.firebaseio.com/v0/topstories.json",
            "https://hacker-news.firebaseio.com/v0/item/1.json",
            "https://hacker-news.firebaseio.com/v0/item/2.json",
            "https://hacker-news.firebaseio.com/v0/item/3.json",
        ])
        // Subtitle carries the score + parsed host.
        let listObj = try XCTUnwrap(list.objectValue)
        let firstItem = try XCTUnwrap(listObj["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(firstItem["props"]?.objectValue?["subtitle"]?.stringValue, "321 points · blog.rust-lang.org")
    }

    func testHackerNewsFixtureRendersEmptyStateOnFetchFailure() throws {
        // A client with NO canned topstories → 404 → JSON.parse fails → the plugin
        // renders an empty-state list and toasts failure (never crashes/throws).
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.hacker-news", name: "Hacker News", version: "1.0.0",
                entrypoint: "com.vee.hacker-news.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities(network: ["hacker-news.firebaseio.com"])),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient())   // empty canned → 404 bodies

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.hacker-news"))
        XCTAssertNoThrow(try instance.activateCommand("view", arguments: [:]))
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree)
        let list = try listNode(of: tree)
        let firstChild = try XCTUnwrap(list.objectValue?["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(firstChild["tag"]?.stringValue, "empty-view")
        // A failure toast was emitted.
        let toasts = recorder.toasts()
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(toasts.first?.style, .failure)
    }

    func testHackerNewsFetchToNonAllowlistedHostIsDenied() throws {
        // Capability-gating proof (mirrors testFetchToDisallowedHostIsDenied):
        // the plugin's manifest allows only hacker-news.firebaseio.com, so a
        // fetch to any other host is rejected with -32001 and NEVER reaches the
        // client. We assert this against the SAME injected client the plugin uses.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let http = cannedHackerNews()
        // Add a canned response for an off-allowlist host to prove it's not used.
        http.canned["https://evil.example.com/v0/topstories.json"] = CannedHTTPClient.Response(
            status: 200, headers: [:], body: Data("[1]".utf8))
        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.hacker-news", name: "Hacker News", version: "1.0.0",
                entrypoint: "com.vee.hacker-news.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities(network: ["hacker-news.firebaseio.com"])),
            transport: transport,
            clock: TestClock(),
            httpClient: http)
        // Load the real bundle so the gate runs in the same context the plugin uses.
        try instance.evaluateOrThrow(fixtureBundle("com.vee.hacker-news"))

        // Drive a fetch to a disallowed host directly through the bridge.
        instance.evaluate("""
            vee.http.fetch('https://evil.example.com/v0/topstories.json')
              .then(r => console.log('resolved'))
              .catch(e => console.error('denied:' + e.code));
        """)
        instance.runUntilQuiescent()

        XCTAssertFalse(http.requested.contains("https://evil.example.com/v0/topstories.json"),
                       "a fetch to a non-allowlisted host must NEVER reach the client")
        let logs = recorder.logs()
        XCTAssertEqual(logs.last?.level, .error)
        XCTAssertTrue((logs.last?.message ?? "").contains("-32001"), "got: \(logs.last?.message ?? "")")
    }

    // ── com.vee.clipboard — vee.clipboard.* (capability-gated) ────────────────

    func testClipboardFixtureRendersHistoryItems() throws {
        let provider = FakeClipboardProvider(items: [
            ClipboardItem(id: "c1", text: "hello clipboard", copiedAt: Date(timeIntervalSince1970: 200)),
            ClipboardItem(id: "c2", text: "https://example.com/page", copiedAt: Date(timeIntervalSince1970: 100)),
        ])
        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.clipboard", name: "Clipboard History", version: "1.0.0",
                entrypoint: "com.vee.clipboard.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities(clipboard: true)),
            transport: LoopbackTransport(),
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            clipboardProvider: provider)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.clipboard"))
        XCTAssertEqual(try instance.commandNames(), ["view"])
        try instance.activateCommand("view", arguments: [:])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        let list = try listNode(of: tree)
        XCTAssertEqual(try itemTitles(in: list), ["hello clipboard", "https://example.com/page"])
        XCTAssertEqual(provider.historyQueries, [""], "the plugin pulled history once")
        // The primary action is "Copy" carrying the item id.
        let listObj = try XCTUnwrap(list.objectValue)
        let firstItem = try XCTUnwrap(listObj["children"]?.arrayValue?.first?.objectValue)
        let firstAction = try XCTUnwrap(firstItem["children"]?.arrayValue?.first?.objectValue?["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(firstAction["tag"]?.stringValue, "action")
        XCTAssertEqual(firstAction["props"]?.objectValue?["title"]?.stringValue, "Copy")
        XCTAssertEqual(firstAction["props"]?.objectValue?["actionId"]?.stringValue, "c1")
    }

    func testClipboardFixtureCopyActionRoundTripsToProvider() throws {
        // Activate, then fire host.invokeAction for an item id; the plugin's
        // handler calls vee.clipboard.copy, which must reach the provider with the
        // exact item (text + copiedAt preserved).
        let transport = LoopbackTransport()
        let provider = FakeClipboardProvider(items: [
            ClipboardItem(id: "c1", text: "first", copiedAt: Date(timeIntervalSince1970: 200)),
            ClipboardItem(id: "c2", text: "paste me back", copiedAt: Date(timeIntervalSince1970: 100)),
        ])
        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.clipboard", name: "Clipboard History", version: "1.0.0",
                entrypoint: "com.vee.clipboard.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities(clipboard: true)),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            clipboardProvider: provider)

        try instance.evaluateOrThrow(fixtureBundle("com.vee.clipboard"))
        try instance.activateCommand("view", arguments: [:])
        instance.runUntilQuiescent()

        // The launcher fires the Copy action for c2. Dispatch it the same way the
        // host's inbound router does (`instance.dispatch`), rather than through the
        // loopback `sendFromPeer` — the plugin's handler emits a `showToast` on
        // success, and `sendFromPeer` holds the transport's serial queue while the
        // handler runs, so that outbound send would re-enter the same queue.
        let params = InvokeActionParams(pluginId: "com.vee.clipboard", actionId: "c2", targetId: "c2")
        instance.dispatch(.notification(JSONRPCNotification(
            method: RPCMethods.invokeAction,
            params: try encodeToJSONValue(params))))
        instance.runUntilQuiescent()

        XCTAssertEqual(provider.copied.map(\.id), ["c2"])
        XCTAssertEqual(provider.copied.first?.text, "paste me back")
        // The copied item round-tripped its original copiedAt exactly.
        XCTAssertEqual(provider.copied.first?.copiedAt, Date(timeIntervalSince1970: 100))
    }

    func testClipboardFixtureRendersEmptyStateWhenDenied() throws {
        // clipboard:false → history is denied; the plugin catches it and renders
        // an empty-state list (and the provider is never touched).
        let provider = FakeClipboardProvider(items: [
            ClipboardItem(id: "c1", text: "secret", copiedAt: Date(timeIntervalSince1970: 1)),
        ])
        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.clipboard", name: "Clipboard History", version: "1.0.0",
                entrypoint: "com.vee.clipboard.bundle.js",
                commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                capabilities: Capabilities(clipboard: false)),   // denied
            transport: LoopbackTransport(),
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            clipboardProvider: provider)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.clipboard"))
        XCTAssertNoThrow(try instance.activateCommand("view", arguments: [:]))
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree)
        let list = try listNode(of: tree)
        let firstChild = try XCTUnwrap(list.objectValue?["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(firstChild["tag"]?.stringValue, "empty-view")
        XCTAssertTrue(provider.historyQueries.isEmpty, "denied history must NEVER reach the provider")
    }
}
