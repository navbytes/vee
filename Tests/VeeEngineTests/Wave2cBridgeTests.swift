import XCTest
import JavaScriptCore
@testable import VeeEngine
import VeeProtocol

/// Wave 2c — two new capability-appropriate bridges added alongside the existing
/// JSC plugin-host surface:
///
///   • `vee.fs.list(dir)` — capability-gated directory listing. Same
///     `Capabilities.filesystem` root-confinement gate as `fs.read`/`fs.write`:
///     a dir outside a declared root (or `filesystem: []`) rejects with
///     `capabilityDenied` (-32001) WITHOUT touching the provider.
///   • `vee.notify(title, body?, subtitle?)` — fire-and-forget system
///     notification, UNGATED (like `vee.showToast`), delivered to the injected
///     `NotificationProviding`.
///
/// Mirrors the existing fs deny tests in `VeeEngineTests` and the
/// `PluginHost`/`PluginInstance` harness in `MultiPluginRoutingTests` /
/// `Wave2bTests`.
final class Wave2cBridgeTests: XCTestCase {

    // MARK: - Shared helpers (local copies of the patterns in VeeEngineTests)

    /// Collects every notification a host emits toward the launcher.
    private final class Recorder {
        let transport: LoopbackTransport
        private(set) var notifications: [JSONRPCNotification] = []

        init(_ transport: LoopbackTransport) {
            self.transport = transport
            transport.peerInbound = { [weak self] message in
                if case .notification(let n) = message { self?.notifications.append(n) }
            }
        }

        func logs() -> [LogParams] { decode(method: RPCMethods.log) }

        private func decode<T: Decodable>(method: String) -> [T] {
            notifications.compactMap { note in
                guard note.method == method, let params = note.params else { return nil }
                let data = try? JSONEncoder().encode(params)
                return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
            }
        }
    }

    /// A manifest granting `filesystem` roots (mirrors `VeeEngineTests.fsManifest`).
    private func fsManifest(id: String = "com.vee.fs", roots: [String]) -> PluginManifest {
        PluginManifest(
            id: id, name: "Test", version: "1.0.0", entrypoint: "bundle.js",
            commands: [PluginCommand(name: "view", title: "View", mode: .view)],
            capabilities: Capabilities(filesystem: roots)
        )
    }

    // MARK: - vee.fs.list (capability-gated by Capabilities.filesystem)

    func testFileListReturnsEntriesWithinRoot() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let provider = TempDirFileProvider()
        // Populate the provider's own temp root: one file + one subdirectory.
        let fm = FileManager.default
        try "x".write(toFile: (provider.root as NSString).appendingPathComponent("a.txt"),
                      atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: (provider.root as NSString).appendingPathComponent("sub"),
                               withIntermediateDirectories: true)

        let instance = try PluginInstance(
            manifest: fsManifest(roots: [provider.root]),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileProvider: provider
        )
        // List the root and report each entry as "name:isDirectory", sorted so the
        // assertion is order-independent.
        instance.evaluate("""
            vee.fs.list('\(provider.root)')
              .then(entries => {
                var rows = entries.map(e => e.name + ':' + e.isDirectory).sort();
                console.log('list:' + rows.join(','));
              })
              .catch(e => console.error('err:' + e));
        """)
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["list:a.txt:false,sub:true"])
        XCTAssertEqual(provider.lists.count, 1)
    }

    func testFileListOutsideDeclaredRootsIsDeniedWithoutTouchingProvider() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let provider = TempDirFileProvider()
        // Root is the provider's temp dir; the plugin tries to list OUTSIDE it.
        let instance = try PluginInstance(
            manifest: fsManifest(roots: [provider.root]),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileProvider: provider
        )
        instance.evaluate("""
            vee.fs.list('/etc')
              .then(es => console.log('list:' + es.length))
              .catch(e => console.error('denied:' + e.code));
        """)
        instance.runUntilQuiescent()
        XCTAssertTrue(provider.lists.isEmpty, "a dir outside the roots must NEVER reach the provider")
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
    }

    func testFileListDeniedWhenFilesystemRootsEmpty() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let provider = TempDirFileProvider()
        // filesystem: [] denies ALL paths, even the provider's own (existing) root.
        let instance = try PluginInstance(
            manifest: fsManifest(roots: []),
            transport: transport,
            clock: TestClock(),
            httpClient: CannedHTTPClient(),
            fileProvider: provider
        )
        instance.evaluate("""
            vee.fs.list('\(provider.root)')
              .then(es => console.log('list:' + es.length))
              .catch(e => console.error('denied:' + e.code));
        """)
        instance.runUntilQuiescent()
        XCTAssertTrue(provider.lists.isEmpty, "filesystem:[] must deny all listings")
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
    }

    // MARK: - vee.notify (UNGATED system notification)

    /// A minimal bundle whose `view` command posts a notification on activate.
    private func notifyBundle() -> String {
        """
        globalThis.__veePlugin = {
          commandNames: ["view"],
          activateCommand: function(name, ctx) {
            vee.notify("Hi", "body");
            ctx.render({ tag: "root", props: {}, children: [] });
          }
        };
        """
    }

    private func notifyManifest(_ id: String = "com.vee.notify") -> PluginManifest {
        PluginManifest(id: id, name: "Notify", version: "1.0.0", entrypoint: "bundle.js",
                       commands: [PluginCommand(name: "view", title: "View", mode: .view)],
                       capabilities: Capabilities())
    }

    func testNotifyDeliversToInjectedProviderOnActivate() throws {
        // Drive through the PluginHost harness with a RecordingNotificationProvider
        // injected; assert it recorded the (title, body, subtitle) call.
        let recorder = RecordingNotificationProvider()
        let host = PluginHost(
            transport: LoopbackTransport(), clock: DispatchClock(),
            httpClient: CannedHTTPClient(), bundler: StaticBundler(source: ""),
            notificationProvider: recorder)

        _ = try host.load(manifest: notifyManifest(), source: notifyBundle())
        try host.activate(ActivateParams(pluginId: "com.vee.notify", commandName: "view"))
        host.instance(for: "com.vee.notify")?.runUntilQuiescent()

        XCTAssertEqual(recorder.posted.count, 1)
        XCTAssertEqual(recorder.posted.first?.title, "Hi")
        XCTAssertEqual(recorder.posted.first?.body, "body")
        XCTAssertNil(recorder.posted.first?.subtitle, "no subtitle was passed")
    }

    func testNotifyIsUngatedUnderEmptyCapabilities() throws {
        // notify must work even with a default-deny manifest (parallels showToast):
        // it is user-facing, not a data/exfil risk. Drive a standalone instance.
        let recorder = RecordingNotificationProvider()
        let instance = try PluginInstance(
            manifest: notifyManifest(),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: CannedHTTPClient(),
            notificationProvider: recorder)
        instance.evaluate("vee.notify('T', 'B', 'S');")
        instance.runUntilQuiescent()
        XCTAssertEqual(recorder.posted.count, 1)
        XCTAssertEqual(recorder.posted.first?.title, "T")
        XCTAssertEqual(recorder.posted.first?.body, "B")
        XCTAssertEqual(recorder.posted.first?.subtitle, "S")
    }
}
