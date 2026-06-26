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

// MARK: - SSRF host classifier (SEC-4 / SEC-3 / R2-MED-5)

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Literal-host SSRF guard shared by the fetch gate (SEC-4) and the redirect
/// re-check (SEC-3). Returns `true` for hosts that must never be fetched —
/// loopback, link-local (incl. the cloud metadata IP `169.254.169.254`), RFC-1918
/// private ranges, and IPv6 unique-local (`fc00::/7`).
///
/// This is **defense-in-depth on top of the per-plugin allowlist** (the allowlist
/// is the primary gate); it cannot defeat DNS rebinding (no resolution pinning),
/// but it closes the literal-IP bypasses an attacker reaches for.
///
/// ## R2-MED-5 fixes
/// The previous implementation was a naive `hasPrefix` string match. It (a) missed
/// the *obfuscated* IPv4 forms that `connect(2)`/`inet_aton` still resolve to a
/// blocked address, and (b) over-blocked legitimate hostnames. This version parses
/// the host as an actual IP literal and classifies the resolved bytes:
///
///   • **IPv6** via `inet_pton(AF_INET6)`: loopback `::1`, link-local `fe80::/10`,
///     unique-local `fc00::/7`; an **IPv4-mapped** address (`::ffff:a.b.c.d`,
///     e.g. `[::ffff:169.254.169.254]`) is unwrapped and its embedded IPv4
///     re-classified.
///   • **IPv4** via `inet_pton(AF_INET)` AND `inet_aton`. `inet_aton` is what
///     resolves the obfuscation an attacker uses and `inet_pton` rejects —
///     **decimal** (`2130706433` → `127.0.0.1`), **hex** (`0x7f.0.0.1`,
///     `0x7f000001`), **octal** (`0177.0.0.1`), and short forms (`127.1`). We
///     classify the union, the most-blocking (correct) stance for a blocklist.
///
///   • **Over-block fix:** the old `hasPrefix("fc")/("fd")` wrongly blocked real
///     hostnames like `fc-data.com`/`fd-cdn.net`. `fc00::/7` is now matched ONLY
///     when the host actually parses as an IPv6 literal — never for a hostname.
///     A non-IP host (a real DNS name) is NOT blocked here; the allowlist governs
///     it.
///
/// Comparison is case-insensitive and tolerates bracketed IPv6 (`[::1]`).
public func isBlockedNetworkHost(_ host: String) -> Bool {
    var h = host.lowercased()
    if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }   // [::1] → ::1
    guard !h.isEmpty else { return false }

    // Name-based loopback (a hostname, not an IP literal): `localhost`, and any
    // `*.localhost` per RFC 6761. (IP literals are handled below by parsing.)
    if h == "localhost" || h.hasSuffix(".localhost") { return true }

    // IPv6 literal? Strip a zone id (`fe80::1%en0`) before parsing.
    let v6Candidate = h.split(separator: "%", maxSplits: 1).first.map(String.init) ?? h
    if let v6 = parseIPv6(v6Candidate) {
        return isBlockedIPv6(v6)
    }

    // IPv4 literal, INCLUDING the obfuscated forms `connect()` would resolve
    // (decimal/hex/octal/short). An empty set ⇒ not an IP literal ⇒ a real
    // hostname, which this defense-in-depth layer does not block (the allowlist
    // does). If ANY plausible interpretation is a blocked range, block — see
    // `ipv4Interpretations` for why strict and permissive parses can disagree.
    let v4s = ipv4Interpretations(h)
    if !v4s.isEmpty {
        return v4s.contains(where: isBlockedIPv4)
    }
    return false
}

/// Parse an IPv6 literal to its 16 bytes via `inet_pton`, or nil if it isn't one.
private func parseIPv6(_ s: String) -> [UInt8]? {
    var addr = in6_addr()
    let ok = s.withCString { inet_pton(AF_INET6, $0, &addr) } == 1
    guard ok else { return nil }
    return withUnsafeBytes(of: &addr) { Array($0) }   // 16 bytes, network order
}

/// Every host-order `UInt32` an IPv4 literal could plausibly resolve to. We union
/// the STRICT (`inet_pton`) and PERMISSIVE (`inet_aton`) parses because they
/// **disagree** on some inputs, and the disagreement is exploitable: `inet_pton`
/// reads `0177.0.0.1` as decimal `177.0.0.1` (public), while `inet_aton` — and the
/// resolver/`connect(2)` path a real fetch actually takes — reads `0177` as OCTAL
/// `127`, i.e. loopback. Blocking the union (block if *any* interpretation is a
/// blocked range) is the conservative, correct stance for an SSRF blocklist: we
/// never want a host that *could* reach a private address to slip through because
/// one parser happened to read it as public.
///
/// `inet_aton` also covers the obfuscated forms `inet_pton` rejects outright —
/// decimal (`2130706433`), hex (`0x7f000001`, `0x7f.0.0.1`), and <4-part short
/// forms (`127.1`). An empty result means the host is not an IP literal at all (a
/// real DNS name), which the caller leaves to the allowlist.
private func ipv4Interpretations(_ s: String) -> [UInt32] {
    var results: [UInt32] = []
    var strict = in_addr()
    if s.withCString({ inet_pton(AF_INET, $0, &strict) }) == 1 {
        results.append(UInt32(bigEndian: strict.s_addr))
    }
    // Guard the permissive parse to genuinely numeric/dotted/hex input so we don't
    // accidentally accept a hostname (inet_aton already rejects names, but require
    // at least one digit and only IP-literal characters as a cheap belt).
    let allowed = Set("0123456789abcdefx.")
    if !s.isEmpty, s.allSatisfy({ allowed.contains($0) }), s.contains(where: { $0.isNumber }) {
        var legacy = in_addr()
        if s.withCString({ inet_aton($0, &legacy) }) != 0 {
            results.append(UInt32(bigEndian: legacy.s_addr))
        }
    }
    return results
}

/// Classify a host-order IPv4 address against the blocked ranges.
private func isBlockedIPv4(_ a: UInt32) -> Bool {
    let o1 = (a >> 24) & 0xff
    let o2 = (a >> 16) & 0xff
    // 0.0.0.0/8 — "this host"/unspecified (0.0.0.0 routes to localhost on many stacks).
    if o1 == 0 { return true }
    // 127.0.0.0/8 — loopback.
    if o1 == 127 { return true }
    // 10.0.0.0/8 — private.
    if o1 == 10 { return true }
    // 169.254.0.0/16 — link-local (incl. 169.254.169.254 cloud metadata).
    if o1 == 169 && o2 == 254 { return true }
    // 172.16.0.0/12 — private.
    if o1 == 172 && (16...31).contains(o2) { return true }
    // 192.168.0.0/16 — private.
    if o1 == 192 && o2 == 168 { return true }
    return false
}

/// Classify a 16-byte (network-order) IPv6 address against the blocked ranges,
/// unwrapping an IPv4-mapped address and re-classifying its embedded IPv4.
private func isBlockedIPv6(_ b: [UInt8]) -> Bool {
    guard b.count == 16 else { return false }
    // ::1 — loopback. (:: unspecified is also treated as blocked.)
    let isAllZeroExceptLast = b[0..<15].allSatisfy { $0 == 0 }
    if isAllZeroExceptLast && (b[15] == 1 || b[15] == 0) { return true }
    // fe80::/10 — link-local: first 10 bits are 1111 1110 10.
    if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }
    // fc00::/7 — unique-local (covers fc00::/8 and fd00::/8). First 7 bits 1111 110.
    if (b[0] & 0xfe) == 0xfc { return true }
    // IPv4-mapped ::ffff:a.b.c.d (::ffff:0:0/96) — unwrap + re-classify the v4.
    let mappedPrefix = b[0..<10].allSatisfy { $0 == 0 } && b[10] == 0xff && b[11] == 0xff
    if mappedPrefix {
        let v4 = (UInt32(b[12]) << 24) | (UInt32(b[13]) << 16) | (UInt32(b[14]) << 8) | UInt32(b[15])
        return isBlockedIPv4(v4)
    }
    // IPv4-compatible ::a.b.c.d (deprecated, but classify defensively).
    let compatPrefix = b[0..<12].allSatisfy { $0 == 0 }
    if compatPrefix {
        let v4 = (UInt32(b[12]) << 24) | (UInt32(b[13]) << 16) | (UInt32(b[14]) << 8) | UInt32(b[15])
        if v4 != 0 && v4 != 1 { return isBlockedIPv4(v4) }
    }
    return false
}

// MARK: - HTTPClient

/// Injectable HTTP backend for `vee.http.fetch`. Production uses URLSession; the
/// test double returns canned responses. The completion is always invoked on a
/// background thread; the bridge hops back to the instance's serial queue to
/// resolve the JS Promise (and drain microtasks) safely.
///
/// `allowedHosts` carries the calling plugin's `Capabilities.network` so the
/// real client can re-apply the allowlist to redirect targets (SEC-3). Test
/// doubles ignore it.
public protocol HTTPClient: AnyObject {
    func perform(_ request: FetchParams, allowedHosts: [String],
                 completion: @escaping (Result<FetchResult, Error>) -> Void)
}

public extension HTTPClient {
    /// Back-compat overload: no allowlist threaded (used where redirect
    /// re-checking is not required, e.g. existing tests/clients).
    func perform(_ request: FetchParams, completion: @escaping (Result<FetchResult, Error>) -> Void) {
        perform(request, allowedHosts: [], completion: completion)
    }
}

/// URLSession-backed client used by the real host.
///
/// SEC-3: cross-origin redirects are re-checked. Each request runs on a private
/// `URLSession` whose delegate (`RedirectGuard`) re-applies the per-request
/// network-host allowlist (and the SSRF classifier) to every 3xx `Location`
/// target, refusing the redirect (`completion(nil)`) when the new host is not
/// allowed — so a granted host's open-redirect can't bounce the request to
/// `169.254.169.254`, `localhost`, or an off-allowlist exfil host.
public final class URLSessionHTTPClient: HTTPClient {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    /// Back-compat initializer. A caller-supplied `URLSession` cannot carry our
    /// per-request redirect delegate, so we adopt its configuration instead and
    /// build guarded sessions from it (SEC-3 still applies).
    public convenience init(session: URLSession) {
        self.init(configuration: session.configuration)
    }

    public func perform(_ request: FetchParams, allowedHosts: [String],
                        completion: @escaping (Result<FetchResult, Error>) -> Void) {
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

        // One guarded session per request: the delegate owns the allowlist and
        // invalidates the session once the task completes (so it doesn't leak).
        let guardDelegate = RedirectGuard(allowedHosts: allowedHosts)
        let session = URLSession(configuration: configuration, delegate: guardDelegate, delegateQueue: nil)
        let task = session.dataTask(with: urlRequest) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
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

    /// `URLSessionTaskDelegate` that re-applies the network-host allowlist (and
    /// the literal SSRF guard) to each redirect target (SEC-3). Refusing returns
    /// `nil` to the completion handler, which cancels the redirect; URLSession
    /// then delivers the 3xx response itself rather than following it.
    ///
    /// `internal` (not private) so the SEC-3 decision can be unit-tested directly
    /// without standing up a live redirecting server.
    final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        private let allowedHosts: [String]
        init(allowedHosts: [String]) { self.allowedHosts = allowedHosts }

        /// Whether a redirect to `host` (with `scheme`) is permitted: http(s)
        /// only, not an SSRF target, and in the per-request allowlist.
        func allowsRedirect(scheme: String, host: String) -> Bool {
            let s = scheme.lowercased()
            guard s == "http" || s == "https" else { return false }
            if isBlockedNetworkHost(host) { return false }
            return Capabilities(network: allowedHosts).allowsNetworkHost(host)
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            let scheme = request.url?.scheme ?? ""
            let host = request.url?.host ?? ""
            guard allowsRedirect(scheme: scheme, host: host) else {
                completionHandler(nil)   // refuse: do not follow the redirect
                return
            }
            completionHandler(request)
        }
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
    /// The `allowedHosts` threaded into the most recent `perform` call (SEC-3),
    /// so a test can assert the bridge passed the plugin's `network` allowlist.
    public private(set) var lastAllowedHosts: [String] = []
    /// When true, invoke completion synchronously (default) so the deterministic
    /// `runUntilQuiescent` can settle the Promise without real async hops.
    public var synchronous = true

    public init() {}

    public func perform(_ request: FetchParams, allowedHosts: [String],
                        completion: @escaping (Result<FetchResult, Error>) -> Void) {
        requested.append(request.url)
        lastAllowedHosts = allowedHosts
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

/// A bundler that refuses to build. Used by the out-of-process child host, where
/// `PluginHost.reload` is never invoked locally — the parent re-sends the bundle
/// source over the pipe (`host.loadPlugin`) instead of the child rebuilding from
/// disk. If `build` is ever called it's a programming error, surfaced as a clear
/// `internalError` rather than a silent empty bundle.
public final class UnsupportedBundler: Bundler {
    public init() {}
    public func build(pluginId: String) throws -> String {
        throw JSONRPCError.internalError(
            "UnsupportedBundler: out-of-process host does not rebuild locally (reload is driven by the parent)")
    }
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
        // MAC-6: drain stdout AND stderr CONCURRENTLY. Reading one pipe fully
        // before the other deadlocks if the child fills the second pipe's buffer
        // while we're still blocked on the first. Read stdout on a background
        // queue while this thread drains stderr, then join before waitUntilExit.
        let stdoutGroup = DispatchGroup()
        stdoutGroup.enter()
        DispatchQueue.global().async {
            _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            stdoutGroup.leave()
        }
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        stdoutGroup.wait()
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

/// `NSPasteboard`-backed `ClipboardProviding` for the real out-of-process host.
///
/// The OS pasteboard exposes only its *current* contents, not a history (a
/// persistent clipboard-history store lives in the app layer). So `history`
/// returns at most the single current plain-text item (filtered by `query`), and
/// `copy` writes the item's text to the general pasteboard. This is a pragmatic
/// real implementation for the child process; the app can inject a
/// history-backed provider instead. Logic-light and not unit-tested (touches the
/// real pasteboard); the bridge that consumes a `ClipboardProviding` is covered
/// via `FakeClipboardProvider`.
public final class NSPasteboardClipboardProvider: ClipboardProviding {
    public init() {}

    public func history(query: String, limit: Int, completion: @escaping (Result<[ClipboardItem], Error>) -> Void) {
        guard limit > 0, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            completion(.success([])); return
        }
        if !query.isEmpty, !text.localizedCaseInsensitiveContains(query) {
            completion(.success([])); return
        }
        let item = ClipboardItem(id: "pasteboard.current", text: text, copiedAt: Date())
        completion(.success([item]))
    }

    public func copy(_ item: ClipboardItem, completion: @escaping (Result<Void, Error>) -> Void) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        completion(.success(()))
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
