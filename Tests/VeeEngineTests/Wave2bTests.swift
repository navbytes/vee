import XCTest
import JavaScriptCore
@testable import VeeEngine
import VeeProtocol

/// Wave 2b — disk-backed `vee.storage` persistence + engine tests for the five
/// committed plugin fixtures (github, jira, meetings, api, snippets).
///
/// These mirror the existing fixture tests in `VeeEngineTests` exactly for
/// loading/injection: build a real `PluginInstance` (or `PluginHost`) with the
/// appropriate FAKE bridges, evaluate the committed bundle, activate `view`,
/// settle the deterministic run loop, and assert the captured render tree /
/// behaviour.
final class Wave2bTests: XCTestCase {

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

        func toasts() -> [ToastParams] { decode(method: RPCMethods.toast) }
        func logs() -> [LogParams] { decode(method: RPCMethods.log) }

        private func decode<T: Decodable>(method: String) -> [T] {
            notifications.compactMap { note in
                guard note.method == method, let params = note.params else { return nil }
                let data = try? JSONEncoder().encode(params)
                return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
            }
        }
    }

    /// Resolve the repo root from this file's path (`<repo>/Tests/VeeEngineTests/…`).
    private static func repoRoot() -> URL {
        if let env = ProcessInfo.processInfo.environment["VEE_REPO_ROOT"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VeeEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    /// Read a committed fixture bundle by plugin id (robust to CWD).
    private func fixtureBundle(_ pluginId: String) throws -> String {
        try String(
            contentsOf: Self.repoRoot().appendingPathComponent("plugins/fixtures/\(pluginId).bundle.js"),
            encoding: .utf8)
    }

    /// A `view`-only command list.
    private func viewCommand() -> [PluginCommand] {
        [PluginCommand(name: "view", title: "View", mode: .view)]
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    // MARK: Render-tree navigation helpers

    /// The `list` node under the rendered `root` tree (first child).
    private func listNode(of tree: JSONValue) throws -> JSONValue {
        let root = try XCTUnwrap(tree.objectValue)
        XCTAssertEqual(root["tag"]?.stringValue, "root")
        let children = try XCTUnwrap(root["children"]?.arrayValue)
        return try XCTUnwrap(children.first)
    }

    /// Titles of every `list-item` child of a `list` node, in order. Filters to
    /// `list-item` tags so non-item children (e.g. a `form` or `empty-view`) are
    /// excluded.
    private func itemTitles(in list: JSONValue) throws -> [String] {
        let listObj = try XCTUnwrap(list.objectValue)
        XCTAssertEqual(listObj["tag"]?.stringValue, "list")
        let children = try XCTUnwrap(listObj["children"]?.arrayValue)
        return children.compactMap { child in
            guard child.objectValue?["tag"]?.stringValue == "list-item" else { return nil }
            return child.objectValue?["props"]?.objectValue?["title"]?.stringValue
        }
    }

    /// The `tag` of the first child of a `list` node (e.g. "empty-view").
    private func firstChildTag(in list: JSONValue) throws -> String? {
        try XCTUnwrap(list.objectValue)["children"]?.arrayValue?.first?.objectValue?["tag"]?.stringValue
    }

    // MARK: - Job 1: DiskStorageBackend persistence

    func testDiskStorageBackendPersistsAcrossInstances() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vee-disk-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Write through one backend instance…
        let writer = try DiskStorageBackend(directory: tempRoot, pluginId: "com.vee.snippets")
        writer.set("snippets", value: .array([
            .object(["id": .string("s1"), "text": .string("hello"), "title": .string("Greeting")])
        ]), ttlSeconds: nil)
        writer.set("count", value: .number(3), ttlSeconds: nil)

        // …and read it back through a FRESH backend over the SAME directory
        // (the across-launch guarantee).
        let reader = try DiskStorageBackend(directory: tempRoot, pluginId: "com.vee.snippets")
        XCTAssertEqual(reader.get("count"), .number(3))
        let snippets = try XCTUnwrap(reader.get("snippets")?.arrayValue)
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets.first?.objectValue?["id"]?.stringValue, "s1")
        XCTAssertEqual(snippets.first?.objectValue?["text"]?.stringValue, "hello")
    }

    func testDiskStorageBackendNamespacesByPluginId() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vee-disk-ns-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Two plugins sharing the SAME root directory must not collide on a key.
        let a = try DiskStorageBackend(directory: tempRoot, pluginId: "com.vee.alpha")
        let b = try DiskStorageBackend(directory: tempRoot, pluginId: "com.vee.beta")
        a.set("k", value: .string("from-a"), ttlSeconds: nil)
        b.set("k", value: .string("from-b"), ttlSeconds: nil)

        XCTAssertEqual(a.get("k"), .string("from-a"))
        XCTAssertEqual(b.get("k"), .string("from-b"))
        // A fresh backend for plugin a over the same root still sees only a's value.
        let a2 = try DiskStorageBackend(directory: tempRoot, pluginId: "com.vee.alpha")
        XCTAssertEqual(a2.get("k"), .string("from-a"))
    }

    func testDiskStorageBackendHonorsTTLOnRead() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vee-disk-ttl-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Drive a virtual clock so expiry is deterministic (no sleeping).
        var nowValue = Date(timeIntervalSince1970: 1000)
        let backend = try DiskStorageBackend(
            directory: tempRoot, pluginId: "com.vee.ttl", now: { nowValue })
        backend.set("ephemeral", value: .string("v"), ttlSeconds: 60)
        // Before expiry: present.
        XCTAssertEqual(backend.get("ephemeral"), .string("v"))
        // After expiry: gone (and a fresh backend over the same dir agrees).
        nowValue = Date(timeIntervalSince1970: 1000 + 61)
        XCTAssertNil(backend.get("ephemeral"))
        let fresh = try DiskStorageBackend(
            directory: tempRoot, pluginId: "com.vee.ttl", now: { nowValue })
        XCTAssertNil(fresh.get("ephemeral"), "an expired value must not survive into a fresh backend")
    }

    func testDiskStorageBackendBacksStorageBridgeWithPersistence() throws {
        // End-to-end through the bridge: a plugin's vee.storage.set then a FRESH
        // instance's vee.storage.get over the same disk dir reads it back.
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vee-disk-bridge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manifest = PluginManifest(
            id: "com.vee.disk", name: "Disk", version: "1.0.0",
            entrypoint: "bundle.js", commands: viewCommand(), capabilities: Capabilities())

        let writerTransport = LoopbackTransport()
        let writer = try PluginInstance(
            manifest: manifest, transport: writerTransport, clock: TestClock(),
            httpClient: CannedHTTPClient(),
            storage: try DiskStorageBackend(directory: tempRoot, pluginId: manifest.id))
        writer.evaluate("""
            vee.storage.set('greeting', { hello: 'world' })
              .then(() => console.log('saved'))
              .catch(e => console.error('err:' + e));
        """)
        writer.runUntilQuiescent()

        let readerTransport = LoopbackTransport()
        let readerRecorder = Recorder(readerTransport)
        let reader = try PluginInstance(
            manifest: manifest, transport: readerTransport, clock: TestClock(),
            httpClient: CannedHTTPClient(),
            storage: try DiskStorageBackend(directory: tempRoot, pluginId: manifest.id))
        reader.evaluate("""
            vee.storage.get('greeting')
              .then(v => console.log('read:' + JSON.stringify(v)))
              .catch(e => console.error('err:' + e));
        """)
        reader.runUntilQuiescent()
        XCTAssertEqual(readerRecorder.logs().map(\.message), [#"read:{"hello":"world"}"#])
    }

    // MARK: - Job 2: github fixture (preferences + http)

    /// Canned GitHub search/issues response: two PRs.
    private func cannedGitHub() -> CannedHTTPClient {
        let http = CannedHTTPClient()
        http.canned["https://api.github.com/search/issues?q=is:open+is:pr+author:@me"] =
            CannedHTTPClient.Response(
                status: 200, headers: ["content-type": "application/json"],
                body: Data(#"""
                {"items":[
                  {"id":101,"number":7,"title":"Fix the flaky test","draft":false,"html_url":"https://github.com/acme/app/pull/7","repository_url":"https://api.github.com/repos/acme/app"},
                  {"id":102,"number":9,"title":"Add dark mode","draft":true,"html_url":"https://github.com/acme/app/pull/9","repository_url":"https://api.github.com/repos/acme/app"}
                ]}
                """#.utf8))
        return http
    }

    private func githubManifest() -> PluginManifest {
        PluginManifest(
            id: "com.vee.github", name: "GitHub", version: "1.0.0",
            entrypoint: "com.vee.github.bundle.js", commands: viewCommand(),
            capabilities: Capabilities(network: ["api.github.com"]))
    }

    func testGitHubFixtureRendersPullRequestsWithToken() throws {
        let http = cannedGitHub()
        let store = FakeSecretStore()

        let instance = try PluginInstance(
            manifest: githubManifest(),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: http,
            secretStore: store)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.github"))
        XCTAssertEqual(try instance.commandNames(), ["view"])
        // The token now arrives as a resolved PREFERENCE (the Raycast model) — the
        // host injects it and the plugin reads `getPreferenceValues()`; it is no
        // longer fetched from the keychain by the plugin.
        try instance.activateCommand("view", arguments: [:], preferences: ["token": .string("ghp_x")])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        let list = try listNode(of: tree)
        XCTAssertEqual(try itemTitles(in: list), ["Fix the flaky test", "Add dark mode"])
        // It actually hit the GitHub search endpoint (token path taken).
        XCTAssertEqual(http.requested, ["https://api.github.com/search/issues?q=is:open+is:pr+author:@me"])
    }

    func testGitHubFixtureRendersAddTokenEmptyStateWithoutToken() throws {
        let http = cannedGitHub()
        let store = FakeSecretStore()   // NO token seeded.

        let instance = try PluginInstance(
            manifest: githubManifest(),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: http,
            secretStore: store)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.github"))
        try instance.activateCommand("view", arguments: [:])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree)
        let list = try listNode(of: tree)
        XCTAssertEqual(try firstChildTag(in: list), "empty-view")
        let empty = try XCTUnwrap(list.objectValue?["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(empty["props"]?.objectValue?["title"]?.stringValue, "Add a GitHub token")
        // No token → NO HTTP call must have been made.
        XCTAssertTrue(http.requested.isEmpty, "the no-token path must never reach the network")
    }

    // MARK: - jira fixture (preferences + http)

    /// Canned Jira /search/jql response: two issues.
    private func cannedJira() -> CannedHTTPClient {
        let http = CannedHTTPClient()
        http.canned["https://acme.atlassian.net/rest/api/3/search/jql"] =
            CannedHTTPClient.Response(
                status: 200, headers: ["content-type": "application/json"],
                body: Data(#"""
                {"issues":[
                  {"id":"10001","key":"ENG-1","fields":{"summary":"Investigate latency","status":{"name":"In Progress"}}},
                  {"id":"10002","key":"ENG-2","fields":{"summary":"Write the migration","status":{"name":"To Do"}}}
                ]}
                """#.utf8))
        return http
    }

    private func jiraManifest() -> PluginManifest {
        PluginManifest(
            id: "com.vee.jira", name: "Jira", version: "1.0.0",
            entrypoint: "com.vee.jira.bundle.js", commands: viewCommand(),
            capabilities: Capabilities(network: ["acme.atlassian.net"]))
    }

    func testJiraFixtureRendersIssuesWithCredentials() throws {
        let http = cannedJira()
        let store = FakeSecretStore()

        let instance = try PluginInstance(
            manifest: jiraManifest(),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: http,
            secretStore: store)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.jira"))
        XCTAssertEqual(try instance.commandNames(), ["view"])
        // Site/email/token now arrive as resolved PREFERENCES (the Raycast model),
        // injected by the host rather than read from the keychain by the plugin.
        try instance.activateCommand("view", arguments: [:], preferences: [
            "site": .string("acme.atlassian.net"),
            "email": .string("me@acme.com"),
            "token": .string("jira_tok"),
        ])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        let list = try listNode(of: tree)
        XCTAssertEqual(try itemTitles(in: list), ["Investigate latency", "Write the migration"])
        XCTAssertEqual(http.requested, ["https://acme.atlassian.net/rest/api/3/search/jql"])
    }

    func testJiraFixtureRendersAddCredsEmptyStateWithoutCredentials() throws {
        let http = cannedJira()
        let store = FakeSecretStore()   // missing all creds.

        let instance = try PluginInstance(
            manifest: jiraManifest(),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: http,
            secretStore: store)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.jira"))
        try instance.activateCommand("view", arguments: [:])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree)
        let list = try listNode(of: tree)
        XCTAssertEqual(try firstChildTag(in: list), "empty-view")
        let empty = try XCTUnwrap(list.objectValue?["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(empty["props"]?.objectValue?["title"]?.stringValue, "Add your Jira credentials")
        XCTAssertTrue(http.requested.isEmpty, "missing creds → no network call")
    }

    // MARK: - meetings fixture (calendar)

    private func meetingsManifest(calendar: Bool) -> PluginManifest {
        PluginManifest(
            id: "com.vee.meetings", name: "Meetings", version: "1.0.0",
            entrypoint: "com.vee.meetings.bundle.js", commands: viewCommand(),
            capabilities: Capabilities(calendar: calendar))
    }

    func testMeetingsFixtureRendersEventsFromCalendar() throws {
        let provider = FakeCalendarProvider(events: [
            CalendarEvent(id: "e1", title: "Standup",
                          start: Date(timeIntervalSince1970: 1000),
                          end: Date(timeIntervalSince1970: 2000),
                          meetingURL: "https://meet.google.com/abc"),
            CalendarEvent(id: "e2", title: "Design review",
                          start: Date(timeIntervalSince1970: 5000),
                          end: Date(timeIntervalSince1970: 6000),
                          meetingURL: nil),
        ])
        let instance = try PluginInstance(
            manifest: meetingsManifest(calendar: true),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: CannedHTTPClient(),
            calendarProvider: provider)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.meetings"))
        XCTAssertEqual(try instance.commandNames(), ["view"])
        try instance.activateCommand("view", arguments: [:])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        let list = try listNode(of: tree)
        XCTAssertEqual(try itemTitles(in: list), ["Standup", "Design review"])
        XCTAssertEqual(provider.calls, 1)
        // The first event has a meeting URL → "video" icon + a Join action.
        let firstItem = try XCTUnwrap(list.objectValue?["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(firstItem["props"]?.objectValue?["icon"]?.stringValue, "video")
    }

    func testMeetingsFixtureRendersEmptyStateWhenCalendarDenied() throws {
        // calendar:false → upcoming() rejects (capabilityDenied); the plugin
        // catches it, renders the empty meetings list, and the provider is
        // NEVER touched.
        let provider = FakeCalendarProvider(events: [
            CalendarEvent(id: "secret", title: "Private 1:1",
                          start: Date(timeIntervalSince1970: 1000),
                          end: Date(timeIntervalSince1970: 2000)),
        ])
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let instance = try PluginInstance(
            manifest: meetingsManifest(calendar: false),
            transport: transport, clock: TestClock(), httpClient: CannedHTTPClient(),
            calendarProvider: provider)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.meetings"))
        XCTAssertNoThrow(try instance.activateCommand("view", arguments: [:]))
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree)
        let list = try listNode(of: tree)
        XCTAssertEqual(try firstChildTag(in: list), "empty-view")
        XCTAssertEqual(provider.calls, 0, "denied calendar must NEVER reach the provider")
        // The plugin surfaced the failure as a toast.
        XCTAssertEqual(recorder.toasts().first?.style, .failure)
    }

    // MARK: - api fixture (http, arguments-driven URL)

    func testAPIFixtureRendersFetchedContent() throws {
        let http = CannedHTTPClient()
        http.canned["https://api.example.com/data"] = CannedHTTPClient.Response(
            status: 200, headers: ["content-type": "application/json"],
            body: Data(#"{"name":"vee","stars":42,"private":false}"#.utf8))

        let instance = try PluginInstance(
            manifest: PluginManifest(
                id: "com.vee.api", name: "API Monitor", version: "1.0.0",
                entrypoint: "com.vee.api.bundle.js", commands: viewCommand(),
                capabilities: Capabilities(network: ["api.example.com"])),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: http)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.api"))
        XCTAssertEqual(try instance.commandNames(), ["view"])
        // The endpoint URL comes from ctx.arguments.url.
        try instance.activateCommand("view", arguments: ["url": .string("https://api.example.com/data")])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        let list = try listNode(of: tree)
        // The object's keys become row titles, in insertion order.
        XCTAssertEqual(try itemTitles(in: list), ["name", "stars", "private"])
        XCTAssertEqual(http.requested, ["https://api.example.com/data"])
        // The first row previews the value.
        let firstItem = try XCTUnwrap(list.objectValue?["children"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(firstItem["props"]?.objectValue?["subtitle"]?.stringValue, "vee")
    }

    // MARK: - snippets fixture (storage; save + recall)

    private func snippetsManifest() -> PluginManifest {
        PluginManifest(
            id: "com.vee.snippets", name: "Snippets", version: "1.0.0",
            entrypoint: "com.vee.snippets.bundle.js", commands: viewCommand(),
            capabilities: Capabilities())
    }

    func testSnippetsFixtureRendersSeededSnippets() throws {
        // Seed the in-memory storage under the plugin's STORAGE_KEY ("snippets").
        let storage = InMemoryStorage()
        storage.set("snippets", value: .array([
            .object(["id": .string("s1"), "title": .string("Email signature"), "text": .string("Best,\nNav")]),
            .object(["id": .string("s2"), "title": .string("Address"), "text": .string("1 Infinite Loop")]),
        ]), ttlSeconds: nil)

        let instance = try PluginInstance(
            manifest: snippetsManifest(),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: CannedHTTPClient(),
            storage: storage)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.snippets"))
        XCTAssertEqual(try instance.commandNames(), ["view"])
        try instance.activateCommand("view", arguments: [:])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree, "vee.render was never called")
        let list = try listNode(of: tree)
        // The list holds an "add" form plus a row per snippet; itemTitles filters
        // to list-item rows only.
        XCTAssertEqual(try itemTitles(in: list), ["Email signature", "Address"])
        // The first list child is the New Snippet form (not a row).
        XCTAssertEqual(try firstChildTag(in: list), "form")
    }

    func testSnippetsFixtureRendersEmptyStateWhenNoneSaved() throws {
        let instance = try PluginInstance(
            manifest: snippetsManifest(),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: CannedHTTPClient(),
            storage: InMemoryStorage())   // nothing seeded

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.snippets"))
        try instance.activateCommand("view", arguments: [:])
        instance.runUntilQuiescent()

        let tree = try XCTUnwrap(capturedTree)
        let list = try listNode(of: tree)
        XCTAssertTrue(try itemTitles(in: list).isEmpty, "no snippets → no rows")
        // The list children are [form, empty-view].
        let children = try XCTUnwrap(list.objectValue?["children"]?.arrayValue)
        XCTAssertEqual(children.first?.objectValue?["tag"]?.stringValue, "form")
        XCTAssertTrue(children.contains { $0.objectValue?["tag"]?.stringValue == "empty-view" })
    }

    func testSnippetsFixtureSavesViaSubmitFormAndRecallsFromStorage() throws {
        // Save + recall: submit the "add" form, then assert (a) the snippet is
        // persisted into the injected storage and (b) the plugin re-rendered with
        // the new row.
        let storage = InMemoryStorage()   // start empty
        let instance = try PluginInstance(
            manifest: snippetsManifest(),
            transport: LoopbackTransport(), clock: TestClock(), httpClient: CannedHTTPClient(),
            storage: storage)

        var capturedTree: JSONValue?
        instance.onRenderTree = { capturedTree = $0 }

        try instance.evaluateOrThrow(fixtureBundle("com.vee.snippets"))
        try instance.activateCommand("view", arguments: [:])
        instance.runUntilQuiescent()

        // Submit the add form (the same path the host's inbound router uses).
        let submit = SubmitFormParams(
            pluginId: "com.vee.snippets", actionId: "add",
            values: ["title": .string("TODO"), "text": .string("Refactor the bridge")])
        instance.dispatch(.notification(JSONRPCNotification(
            method: RPCMethods.submitForm, params: try encodeToJSONValue(submit))))
        instance.runUntilQuiescent()

        // (a) Persisted into storage under the "snippets" key.
        let persisted = try XCTUnwrap(storage.get("snippets")?.arrayValue)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.objectValue?["title"]?.stringValue, "TODO")
        XCTAssertEqual(persisted.first?.objectValue?["text"]?.stringValue, "Refactor the bridge")

        // (b) The latest render shows the new snippet row.
        let tree = try XCTUnwrap(capturedTree)
        let list = try listNode(of: tree)
        XCTAssertEqual(try itemTitles(in: list), ["TODO"])
    }
}
