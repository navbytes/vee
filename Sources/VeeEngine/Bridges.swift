import Foundation
import VeeProtocol

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
