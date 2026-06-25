import Foundation
import VeeProtocol
import VeeKeychain

// MARK: - Clock

/// Injectable time source backing `setTimeout`/`setInterval`. In production a
/// `DispatchSourceTimer`-backed clock drives real wall-clock timers; in tests a
/// `TestClock` advances virtual time deterministically so timer ordering and the
/// microtask-drain discipline can be asserted without sleeping.
public protocol Clock: AnyObject {
    /// Schedule `fire` after `delay` seconds. `repeats` re-arms it at the same
    /// interval until cancelled. Returns a token for `cancel`. The callback runs
    /// on the host's serial execution context (never re-entrantly inside this
    /// call), so JSC microtask draining stays correct.
    func schedule(after delay: TimeInterval, repeats: Bool, _ fire: @escaping () -> Void) -> Int

    /// Cancel a scheduled (and not-yet-fired, or repeating) timer.
    func cancel(_ token: Int)
}

/// Deterministic virtual clock for tests. `advance(by:)` fires every timer whose
/// deadline falls within the elapsed span, in deadline order, re-arming repeats.
/// Crucially it fires them one at a time so the host can drain microtasks
/// between macrotasks (the ordering hazard the suite locks down).
public final class TestClock: Clock {
    private struct Timer {
        var token: Int
        var deadline: TimeInterval
        var interval: TimeInterval
        var repeats: Bool
        var fire: () -> Void
    }

    private var now: TimeInterval = 0
    private var nextToken = 1
    private var timers: [Timer] = []
    /// Invoked after each individual timer callback fires, so the owning
    /// instance can drain the JS microtask queue between macrotasks.
    public var afterEachFire: (() -> Void)?

    public init() {}

    public func schedule(after delay: TimeInterval, repeats: Bool, _ fire: @escaping () -> Void) -> Int {
        let token = nextToken; nextToken += 1
        timers.append(Timer(token: token,
                            deadline: now + max(0, delay),
                            interval: max(0, delay),
                            repeats: repeats,
                            fire: fire))
        return token
    }

    public func cancel(_ token: Int) {
        timers.removeAll { $0.token == token }
    }

    /// Advance virtual time by `seconds`, firing due timers in deadline order.
    /// A repeating timer re-arms; we cap iterations to avoid an infinite loop if
    /// a 0ms interval keeps re-arming (it would otherwise spin forever).
    public func advance(by seconds: TimeInterval) {
        let target = now + seconds
        var guardCounter = 0
        while true {
            guardCounter += 1
            if guardCounter > 100_000 { break }   // safety valve
            // Find the earliest due timer at or before `target`.
            guard let idx = timers.enumerated()
                .filter({ $0.element.deadline <= target })
                .min(by: { $0.element.deadline < $1.element.deadline })?.offset
            else { break }

            var timer = timers[idx]
            now = max(now, timer.deadline)
            if timer.repeats {
                timer.deadline = now + timer.interval
                timers[idx] = timer
            } else {
                timers.remove(at: idx)
            }
            timer.fire()
            afterEachFire?()   // drain microtasks between macrotasks
        }
        now = target
    }

    /// Are any timers still pending? Used by `runUntilQuiescent`.
    var hasPending: Bool { !timers.isEmpty }
}

// MARK: - HTTPClient

/// Injectable HTTP backend for `vee.http.fetch`. Production uses URLSession; the
/// test double returns canned responses. The completion is always invoked on a
/// background thread; the bridge hops back to the instance's serial queue to
/// resolve the JS Promise (and drain microtasks) safely.
public protocol HTTPClient: AnyObject {
    func perform(_ request: FetchParams, completion: @escaping (Result<FetchResult, Error>) -> Void)
}

/// URLSession-backed client used by the real host.
public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func perform(_ request: FetchParams, completion: @escaping (Result<FetchResult, Error>) -> Void) {
        guard let url = URL(string: request.url) else {
            completion(.failure(JSONRPCError.invalidParams("bad url: \(request.url)")))
            return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (k, v) in request.headers { urlRequest.setValue(v, forHTTPHeaderField: k) }
        if let b64 = request.bodyBase64, let body = Data(base64Encoded: b64) {
            urlRequest.httpBody = body
        }
        let task = session.dataTask(with: urlRequest) { data, response, error in
            if let error {
                completion(.failure(error)); return
            }
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (k, v) in (http?.allHeaderFields ?? [:]) {
                if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
            }
            let result = FetchResult(
                status: http?.statusCode ?? 0,
                headers: headers,
                bodyBase64: (data ?? Data()).base64EncodedString())
            completion(.success(result))
        }
        task.resume()
    }
}

/// Canned HTTP client for tests. Records every requested URL (so a denied fetch
/// can be proven to have NEVER reached the client) and returns the matching
/// canned response, or a 404 fallback.
public final class CannedHTTPClient: HTTPClient {
    public struct Response {
        public var status: Int
        public var headers: [String: String]
        public var body: Data
        public init(status: Int, headers: [String: String], body: Data) {
            self.status = status; self.headers = headers; self.body = body
        }
    }

    public var canned: [String: Response] = [:]
    public private(set) var requested: [String] = []
    /// When true, invoke completion synchronously (default) so the deterministic
    /// `runUntilQuiescent` can settle the Promise without real async hops.
    public var synchronous = true

    public init() {}

    public func perform(_ request: FetchParams, completion: @escaping (Result<FetchResult, Error>) -> Void) {
        requested.append(request.url)
        let response = canned[request.url] ?? Response(status: 404, headers: [:], body: Data())
        let result = FetchResult(
            status: response.status,
            headers: response.headers,
            bodyBase64: response.body.base64EncodedString())
        if synchronous {
            completion(.success(result))
        } else {
            DispatchQueue.global().async { completion(.success(result)) }
        }
    }
}

// MARK: - Storage

/// Injectable key/value store backing `vee.storage`. Production wires this to
/// VeeCache; the default in-memory store is sufficient for the engine tests and
/// for plugins that only need session-scoped storage.
public protocol StorageBackend: AnyObject {
    func get(_ key: String) -> JSONValue?
    func set(_ key: String, value: JSONValue, ttlSeconds: Double?)
}

public final class InMemoryStorage: StorageBackend {
    private var store: [String: JSONValue] = [:]
    public init() {}
    public func get(_ key: String) -> JSONValue? { store[key] }
    public func set(_ key: String, value: JSONValue, ttlSeconds: Double?) { store[key] = value }
}

// MARK: - FileWatcher

/// Injectable directory/file watcher driving hot reload. Production wires this
/// to FSEvents / a DispatchSource fd source; tests use a manual fake that fires
/// on demand. The host registers a per-plugin callback; on change it rebuilds
/// the bundle and reloads that plugin's context.
public protocol FileWatcher: AnyObject {
    /// Register `onChange` to run when the watched bundle for `pluginId` changes.
    func watch(pluginId: String, _ onChange: @escaping (String) -> Void)
    /// Stop watching a plugin (on unload).
    func unwatch(pluginId: String)
}

/// A watcher that never fires — for hosts/tests that don't exercise hot reload.
public final class NoopFileWatcher: FileWatcher {
    public init() {}
    public func watch(pluginId: String, _ onChange: @escaping (String) -> Void) {}
    public func unwatch(pluginId: String) {}
}

/// Test watcher you fire manually to simulate a file change.
public final class ManualFileWatcher: FileWatcher {
    private var handlers: [String: (String) -> Void] = [:]
    public init() {}
    public func watch(pluginId: String, _ onChange: @escaping (String) -> Void) {
        handlers[pluginId] = onChange
    }
    public func unwatch(pluginId: String) { handlers[pluginId] = nil }
    public func fire(pluginId: String) { handlers[pluginId]?(pluginId) }
}

/// Production file watcher backed by `DispatchSource.makeFileSystemObjectSource`.
///
/// For each watched plugin it opens a file descriptor on the plugin's bundle
/// file (or directory) — resolved via the injected `pathForPlugin` closure — and
/// arms a vnode dispatch source for write/extend/delete/rename/link/revoke
/// events. On any such event it invokes the registered reload callback on its
/// own serial queue.
///
/// Atomic-save handling: many editors and `bundle.mjs` write a new file and
/// rename it over the old one, which fires `.delete`/`.rename` and invalidates
/// the original fd. On those events we fire the callback AND re-arm by reopening
/// the path, so subsequent edits keep being observed. This impl is logic-light
/// and not unit-tested (it touches the real filesystem + GCD); the hot-reload
/// pipeline itself is covered via `ManualFileWatcher`.
public final class FSEventsFileWatcher: FileWatcher {
    /// Resolve a plugin id to the absolute path to watch (its built bundle file
    /// or containing directory).
    private let pathForPlugin: (String) -> String
    private let queue = DispatchQueue(label: "vee.engine.filewatcher")

    private struct Watch {
        var source: DispatchSourceFileSystemObject
        var fileDescriptor: Int32
        var onChange: (String) -> Void
        var path: String
    }
    private var watches: [String: Watch] = [:]

    public init(pathForPlugin: @escaping (String) -> String) {
        self.pathForPlugin = pathForPlugin
    }

    public func watch(pluginId: String, _ onChange: @escaping (String) -> Void) {
        queue.async { [weak self] in
            self?.arm(pluginId: pluginId, path: self?.pathForPlugin(pluginId) ?? "", onChange: onChange)
        }
    }

    public func unwatch(pluginId: String) {
        queue.async { [weak self] in
            self?.disarm(pluginId: pluginId)
        }
    }

    // MUST run on `queue`.
    private func arm(pluginId: String, path: String, onChange: @escaping (String) -> Void) {
        disarm(pluginId: pluginId)   // idempotent re-arm
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }   // path not present yet; caller may retry on next watch()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .link, .revoke],
            queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            onChange(pluginId)
            // On delete/rename/revoke the fd is stale — reopen so future edits
            // (atomic saves) keep firing.
            if !flags.intersection([.delete, .rename, .revoke]).isEmpty {
                self.arm(pluginId: pluginId, path: path, onChange: onChange)
            }
        }
        source.setCancelHandler { close(fd) }
        watches[pluginId] = Watch(source: source, fileDescriptor: fd, onChange: onChange, path: path)
        source.resume()
    }

    // MUST run on `queue`.
    private func disarm(pluginId: String) {
        if let existing = watches.removeValue(forKey: pluginId) {
            existing.source.cancel()   // cancel handler closes the fd
        }
    }

    deinit {
        // Cancel any live sources so their fds close.
        for (_, w) in watches { w.source.cancel() }
    }
}

// MARK: - Bundler

/// Injectable bundler that (re)produces a plugin's single-file IIFE JS bundle.
/// Production wraps esbuild; tests return a static (mutable) string. The host
/// asks for fresh source on (re)load.
public protocol Bundler: AnyObject {
    /// Produce the current bundle source for a plugin id. Throws on a build error.
    func build(pluginId: String) throws -> String
}

/// Test bundler returning whatever `source` currently is (mutate it between a
/// load and a reload to simulate an edited plugin).
public final class StaticBundler: Bundler {
    public var source: String
    public init(source: String) { self.source = source }
    public func build(pluginId: String) throws -> String { source }
}

/// Production bundler that shells out to esbuild via the repo's `bundle.mjs`.
///
/// Runs `node <workingDir>/bundle.mjs --once` from `workingDir` (the repo's
/// `plugins/` directory by default), which performs one incremental build of
/// every sample plugin and writes `dist/<pluginId>.js`. On success it reads and
/// returns that file's contents (the single-file IIFE the host evaluates).
///
/// This is logic-light and not unit-tested (it spawns `node` and touches the
/// filesystem); the reload pipeline that consumes a `Bundler` is covered via
/// `StaticBundler`. Build failures throw a `JSONRPCError.internalError` carrying
/// `bundle.mjs`'s captured stderr so the host can surface a clear message.
public final class EsbuildBundler: Bundler {
    /// Directory containing `bundle.mjs` and the `dist/` output (the repo's
    /// `plugins/` dir).
    private let workingDirectory: URL
    /// `node` (or a custom path/interpreter).
    private let nodeExecutable: String
    /// Bundler script name, relative to `workingDirectory`.
    private let scriptName: String

    public init(workingDirectory: URL,
                nodeExecutable: String = "/usr/bin/env",
                scriptName: String = "bundle.mjs") {
        self.workingDirectory = workingDirectory
        self.nodeExecutable = nodeExecutable
        self.scriptName = scriptName
    }

    public func build(pluginId: String) throws -> String {
        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = URL(fileURLWithPath: nodeExecutable)
        // `/usr/bin/env node bundle.mjs --once` — `env` resolves node on PATH.
        if nodeExecutable.hasSuffix("/env") {
            process.arguments = ["node", scriptName, "--once"]
        } else {
            process.arguments = [scriptName, "--once"]
        }

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        do {
            try process.run()
        } catch {
            throw JSONRPCError.internalError("EsbuildBundler: failed to launch node: \(error)")
        }
        // Drain stdout/stderr to avoid deadlocking on a full pipe buffer.
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw JSONRPCError.internalError(
                "EsbuildBundler: build failed for \(pluginId) (exit \(process.terminationStatus)): \(stderr)")
        }

        let outfile = workingDirectory
            .appendingPathComponent("dist")
            .appendingPathComponent("\(pluginId).js")
        do {
            return try String(contentsOf: outfile, encoding: .utf8)
        } catch {
            throw JSONRPCError.internalError(
                "EsbuildBundler: build succeeded but no bundle at \(outfile.path): \(error)")
        }
    }
}

// MARK: - ClipboardProviding

/// Injectable host-native clipboard service backing `vee.clipboard.*`. Production
/// wires this to the app's clipboard-history store (NSPasteboard-backed); tests
/// use a fake returning canned items. The completion is invoked synchronously by
/// the in-memory/test impls; the bridge always hops back to the instance's serial
/// queue to settle the JS Promise (and drain microtasks) regardless.
///
/// `AnyObject`/class-bound to match the other engine providers (`HTTPClient`,
/// `StorageBackend`) — the bridge holds it via the instance and never copies it.
public protocol ClipboardProviding: AnyObject {
    /// Return up to `limit` clipboard-history items matching `query` (most-recent
    /// first). An empty `query` returns the most recent items.
    func history(query: String, limit: Int, completion: @escaping (Result<[ClipboardItem], Error>) -> Void)
    /// Copy `item` onto the pasteboard (and record it at the head of history).
    func copy(_ item: ClipboardItem, completion: @escaping (Result<Void, Error>) -> Void)
}

/// Default-deny clipboard provider: every call fails with `capabilityDenied`.
/// This is the safe default injected when a host wires no real provider, so a
/// plugin holding `clipboard:true` against a host that hasn't implemented the
/// service gets a clear rejection rather than silent success. (The capability
/// gate in the bridge runs FIRST, so a plugin WITHOUT the capability never even
/// reaches this.)
public final class DenyingClipboardProvider: ClipboardProviding {
    public init() {}
    public func history(query: String, limit: Int, completion: @escaping (Result<[ClipboardItem], Error>) -> Void) {
        completion(.failure(JSONRPCError.capabilityDenied("clipboard provider not available")))
    }
    public func copy(_ item: ClipboardItem, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(JSONRPCError.capabilityDenied("clipboard provider not available")))
    }
}

/// In-memory clipboard provider for tests. `items` is the canned history (most
/// recent first); `history` filters by substring and truncates to `limit`.
/// `copied` records every item handed to `copy`, and a copy prepends to `items`
/// so a subsequent `history` reflects it. Records `historyQueries` so a denied
/// call can be proven to have NEVER reached the provider (mirrors
/// `CannedHTTPClient.requested`).
public final class FakeClipboardProvider: ClipboardProviding {
    public var items: [ClipboardItem]
    public private(set) var copied: [ClipboardItem] = []
    public private(set) var historyQueries: [String] = []

    public init(items: [ClipboardItem] = []) { self.items = items }

    public func history(query: String, limit: Int, completion: @escaping (Result<[ClipboardItem], Error>) -> Void) {
        historyQueries.append(query)
        let filtered = query.isEmpty ? items : items.filter { $0.text.localizedCaseInsensitiveContains(query) }
        completion(.success(Array(filtered.prefix(max(0, limit)))))
    }

    public func copy(_ item: ClipboardItem, completion: @escaping (Result<Void, Error>) -> Void) {
        copied.append(item)
        items.insert(item, at: 0)
        completion(.success(()))
    }
}

// MARK: - OpenProviding (vee.open / vee.openApp)

/// Injectable host-native launcher backing `vee.open(url)` and
/// `vee.openApp(bundleId)`. Production wires this to `NSWorkspace`
/// (`open(_:)` / `openApplication(at:configuration:)`), supplied by the app;
/// tests use a recording fake.
///
/// NOT capability-gated: opening a URL or launching an app is a core launcher
/// action (the launcher's entire job is to open things), and the frozen
/// `Capabilities` has no flag to gate it against. The bridge therefore forwards
/// straight to this provider — see the note on `JSBridge.handleOpen`. The
/// completion is invoked synchronously by the in-memory/test impls; the bridge
/// always hops back to the instance's serial queue to settle the JS Promise.
///
/// `AnyObject`/class-bound to match the other engine providers — the bridge
/// holds it via the instance and never copies it.
public protocol OpenProviding: AnyObject {
    /// Open `url` (a web URL or `file://`/path) in the default handler.
    func open(url: String, completion: @escaping (Result<Void, Error>) -> Void)
    /// Launch the application with bundle id `bundleId`.
    func openApp(bundleId: String, completion: @escaping (Result<Void, Error>) -> Void)
}

/// Recording fake `OpenProviding` for tests. Records every requested url /
/// bundle id (so a bridge call can be proven to have reached the provider with
/// the right argument). Succeeds by default; set `failure` to make every call
/// reject. This is ALSO the safe default injected when a host wires no real
/// provider — opening is non-destructive and not capability-gated, so a no-op
/// recording default is preferable to a hard denial.
public final class RecordingOpenProvider: OpenProviding {
    public private(set) var openedURLs: [String] = []
    public private(set) var openedApps: [String] = []
    /// When set, every call rejects with this error instead of succeeding.
    public var failure: Error?

    public init() {}

    public func open(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        openedURLs.append(url)
        if let failure { completion(.failure(failure)) } else { completion(.success(())) }
    }

    public func openApp(bundleId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        openedApps.append(bundleId)
        if let failure { completion(.failure(failure)) } else { completion(.success(())) }
    }
}

#if canImport(AppKit)
import AppKit

/// Thin `NSWorkspace`-backed `OpenProviding` for the real host. Logic-light and
/// not unit-tested (it touches the real workspace); the bridge that consumes an
/// `OpenProviding` is covered via `RecordingOpenProvider`.
public final class NSWorkspaceOpenProvider: OpenProviding {
    public init() {}

    public func open(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // A `file://` URL or absolute path both resolve; prefer a real URL, fall
        // back to a file URL for bare paths.
        let resolved = URL(string: url) ?? URL(fileURLWithPath: url)
        let ok = NSWorkspace.shared.open(resolved)
        if ok { completion(.success(())) }
        else { completion(.failure(JSONRPCError.internalError("failed to open: \(url)"))) }
    }

    public func openApp(bundleId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            completion(.failure(JSONRPCError.invalidParams("no application for bundle id: \(bundleId)")))
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }
}
#endif

// MARK: - FileProviding (vee.fs.read / vee.fs.write — capability-gated)

/// Injectable file backend behind `vee.fs.read` / `vee.fs.write`. Reads and
/// writes UTF-8 text by ABSOLUTE, already-canonicalized path. The bridge runs
/// the capability gate FIRST (`Capabilities.filesystem`: the path must resolve,
/// after symlink canonicalization, under one of the declared roots; traversal is
/// rejected with `capabilityDenied`), so a provider call only ever happens for a
/// path the manifest permits — a provider WITHOUT a confined path never sees it.
///
/// Production wires this to a thin `FileManager` adapter (`FileManagerFileProvider`);
/// tests use a sandboxed temp-backed fake (`TempDirFileProvider`).
///
/// `AnyObject`/class-bound to match the other engine providers.
public protocol FileProviding: AnyObject {
    /// Read the file at absolute `path` as UTF-8 text.
    func read(path: String, completion: @escaping (Result<String, Error>) -> Void)
    /// Write `contents` (UTF-8) to absolute `path`, creating/overwriting it.
    func write(path: String, contents: String, completion: @escaping (Result<Void, Error>) -> Void)
}

/// Default-deny file provider: every call fails with `capabilityDenied`. Injected
/// when a host wires no real provider so a plugin holding `filesystem` roots
/// against a host that hasn't implemented the service gets a clear rejection
/// rather than silent success. (The bridge's path-confinement gate runs FIRST,
/// so a plugin whose path is outside its roots never reaches this.)
public final class DenyingFileProvider: FileProviding {
    public init() {}
    public func read(path: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.failure(JSONRPCError.capabilityDenied("file provider not available")))
    }
    public func write(path: String, contents: String, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(JSONRPCError.capabilityDenied("file provider not available")))
    }
}

/// Sandboxed in-memory file provider for tests. Backed by a real temp directory
/// it owns and cleans up; `read`/`write` operate on absolute paths and are
/// confined to `root` as defence-in-depth (the bridge already gates, but the
/// provider refuses anything outside its own root too). Records `reads`/`writes`
/// so a denied call can be proven to have NEVER reached the provider (mirrors
/// `CannedHTTPClient.requested`).
public final class TempDirFileProvider: FileProviding {
    /// The canonicalized absolute root this provider is confined to.
    public let root: String
    public private(set) var reads: [String] = []
    public private(set) var writes: [(path: String, contents: String)] = []

    private let fileManager = FileManager.default

    /// Create a provider rooted at a fresh unique temp directory (default), or at
    /// an explicit (already-existing) directory.
    public init(root: String? = nil) {
        if let root {
            self.root = (root as NSString).standardizingPath
        } else {
            let dir = NSTemporaryDirectory() + "vee-fs-" + UUID().uuidString
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // Resolve symlinks so confinement checks compare like for like
            // (`/var` → `/private/var` on macOS).
            self.root = (dir as NSString).resolvingSymlinksInPath
        }
    }

    private func isConfined(_ path: String) -> Bool {
        let resolved = (path as NSString).resolvingSymlinksInPath
        let standardized = (path as NSString).standardizingPath
        let rootSlash = root.hasSuffix("/") ? root : root + "/"
        for candidate in [resolved, standardized] {
            if candidate == root || candidate.hasPrefix(rootSlash) { return true }
        }
        return false
    }

    public func read(path: String, completion: @escaping (Result<String, Error>) -> Void) {
        reads.append(path)
        guard isConfined(path) else {
            completion(.failure(JSONRPCError.capabilityDenied("path escapes provider root"))); return
        }
        do {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            completion(.success(text))
        } catch {
            completion(.failure(JSONRPCError.internalError("fs.read failed: \(error)")))
        }
    }

    public func write(path: String, contents: String, completion: @escaping (Result<Void, Error>) -> Void) {
        writes.append((path, contents))
        guard isConfined(path) else {
            completion(.failure(JSONRPCError.capabilityDenied("path escapes provider root"))); return
        }
        do {
            // Ensure the parent directory exists, then write atomically.
            let parent = (path as NSString).deletingLastPathComponent
            try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            completion(.success(()))
        } catch {
            completion(.failure(JSONRPCError.internalError("fs.write failed: \(error)")))
        }
    }
}

/// Thin `FileManager`-backed `FileProviding` for the real host. Logic-light and
/// not unit-tested (touches the real filesystem); confinement is enforced by the
/// bridge's capability gate before any call lands here. Provided so the app can
/// wire a working `vee.fs`.
public final class FileManagerFileProvider: FileProviding {
    public init() {}
    public func read(path: String, completion: @escaping (Result<String, Error>) -> Void) {
        do { completion(.success(try String(contentsOfFile: path, encoding: .utf8))) }
        catch { completion(.failure(JSONRPCError.internalError("fs.read failed: \(error)"))) }
    }
    public func write(path: String, contents: String, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            completion(.success(()))
        } catch { completion(.failure(JSONRPCError.internalError("fs.write failed: \(error)"))) }
    }
}

// MARK: - CalendarProviding (vee.calendar.upcoming — capability-gated)

/// Injectable host-native calendar service behind `vee.calendar.upcoming()`,
/// gated by `Capabilities.calendar`. DISTINCT from `VeeServices.CalendarProvider`
/// (which yields raw EventKit-shaped values below the service seam): this returns
/// already-resolved wire `CalendarEvent`s (with `meetingURL` detected), because
/// VeeEngine must not depend on VeeServices. Production adapts the VeeServices
/// `CalendarService` to this protocol in the app layer; tests use a fake.
///
/// The bridge runs the capability gate FIRST, so a plugin WITHOUT `calendar`
/// never reaches this provider. The completion is invoked synchronously by the
/// fake; the bridge always hops back to the instance's serial queue to settle.
public protocol CalendarProviding: AnyObject {
    /// Upcoming events (host decides the window + sorting). Wire `CalendarEvent`s.
    func upcoming(completion: @escaping (Result<[CalendarEvent], Error>) -> Void)
}

/// Default calendar provider returning an empty list. This is the safe default
/// injected when a host wires no real provider: a plugin holding `calendar:true`
/// against a host without the service simply sees no events (rather than an
/// error), matching "no upcoming meetings". (The capability gate runs FIRST, so
/// a plugin WITHOUT the capability never reaches this.)
public final class EmptyCalendarProvider: CalendarProviding {
    public init() {}
    public func upcoming(completion: @escaping (Result<[CalendarEvent], Error>) -> Void) {
        completion(.success([]))
    }
}

/// Fake calendar provider for tests. Returns the canned `events` and records the
/// number of `calls` so a denied request can be proven to have NEVER reached the
/// provider (mirrors `CannedHTTPClient.requested`).
public final class FakeCalendarProvider: CalendarProviding {
    public var events: [CalendarEvent]
    public private(set) var calls = 0

    public init(events: [CalendarEvent] = []) { self.events = events }

    public func upcoming(completion: @escaping (Result<[CalendarEvent], Error>) -> Void) {
        calls += 1
        completion(.success(events))
    }
}

// MARK: - SecretStore test double (visible from `import VeeEngine`)

/// An in-memory `SecretStore` re-exposed by VeeEngine so the engine's bridge
/// tests can inject one without depending on the `VeeKeychain` module directly
/// (the `VeeEngineTests` target links `VeeEngine` but not `VeeKeychain`). Mirrors
/// `VeeKeychain.InMemorySecretStore`: composite key is the pure service string
/// (`com.vee.<pluginId>.<namespace>`) + account, so per-plugin/per-namespace
/// isolation falls out for free.
///
/// `@unchecked Sendable`: the dictionary is only touched under the lock.
public final class FakeSecretStore: SecretStore, @unchecked Sendable {
    private struct Key: Hashable { let service: String; let account: String }
    private let lock = NSLock()
    private var items: [Key: String] = [:]

    public init() {}

    private func key(_ pluginId: String, _ namespace: String, _ account: String) -> Key {
        Key(service: keychainServiceString(pluginId: pluginId, namespace: namespace), account: account)
    }

    public func get(pluginId: String, namespace: String, account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return items[key(pluginId, namespace, account)]
    }
    public func set(pluginId: String, namespace: String, account: String, secret: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[key(pluginId, namespace, account)] = secret
    }
    public func delete(pluginId: String, namespace: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[key(pluginId, namespace, account)] = nil
    }
}
