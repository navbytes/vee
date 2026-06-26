import Foundation
import VeeProtocol

/// Inbound method the parent sends to the child to load a plugin bundle. This is
/// NOT part of the frozen `RPCMethods` catalog (which is the host↔plugin
/// contract); it is a private parent↔child control method, so it lives here as a
/// local constant rather than editing `VeeProtocol`. The matching constant in the
/// child (`vee-plugin-host/main.swift`) MUST stay in sync.
public enum ChildHostMethods {
    /// Parent → child request: create + evaluate a plugin.
    /// Params: `LoadPluginParams` (`{ manifest, source }`).
    public static let loadPlugin = "host.loadPlugin"
}

/// Parameters for `host.loadPlugin`. The parent ships the manifest and the
/// already-bundled JS source; the child creates a `PluginInstance` for it inside
/// its own address space.
public struct LoadPluginParams: Codable, Hashable, Sendable {
    public var manifest: PluginManifest
    public var source: String
    public init(manifest: PluginManifest, source: String) {
        self.manifest = manifest
        self.source = source
    }
}

/// Parent-side supervisor for the out-of-process plugin host.
///
/// This is the launcher's handle on a `vee-plugin-host` child process — the
/// mechanism behind the architecture's headline guarantee (§2, "run plugins
/// out-of-process") that a crashing plugin cannot take down the launcher.
///
/// It:
///   • spawns the `vee-plugin-host` executable via `Process` (the caller passes
///     the executable URL — this type makes no assumption about where the build
///     put it);
///   • wires the child's `stdin`/`stdout` to a `StdioTransport`, so all framed
///     JSON-RPC flows over the pipe;
///   • drives the parent→child control flow: `loadAndActivate` sends
///     `host.loadPlugin` then `plugin.activate`; `invokeAction` /
///     `onSearchTextChange` / `submitForm` forward host→plugin events;
///   • surfaces the child's outbound `plugin.*` frames (render / setCandidates /
///     log / showToast) to an installed `onPluginMessage` callback so the app's
///     coordinator can consume them;
///   • **supervises** the child: `Process.terminationHandler` fires `onTermination`
///     (so the UI can show "plugin crashed"), and `restart()` brings up a fresh
///     child with a fresh transport. The parent NEVER crashes because the child
///     did — a dead pipe only ends in a termination callback.
///
/// Threading: callbacks (`onPluginMessage`, `onTermination`) are invoked off the
/// transport's / Process's queues; the app is expected to hop to the main actor.
public final class ChildProcessHost {
    /// The executable to spawn (e.g. the built `vee-plugin-host` binary).
    public let executableURL: URL
    /// Extra arguments / environment for the child (usually empty).
    public let arguments: [String]
    public let environment: [String: String]?

    /// Installed by the owner to receive the child's outbound `plugin.*` frames.
    /// Delivered as decoded `JSONRPCMessage` values (always `.notification` in
    /// practice) so the coordinator can switch on `method`.
    public var onPluginMessage: ((JSONRPCMessage) -> Void)?

    /// Installed by the owner; fires when the child process terminates (crash,
    /// signal, or clean exit) with the termination status and reason. This is the
    /// crash-isolation signal: the parent stays alive, and the UI reacts here.
    public var onTermination: ((TerminationInfo) -> Void)?

    /// Installed by the owner; fires when a correlated parent→child request
    /// (`host.loadPlugin` / `plugin.activate`) does not get its response within
    /// ``requestTimeout``. The typical cause is a plugin that hangs inside
    /// `activate` (e.g. `while(true){}`), which blocks the child's reply forever:
    /// crash isolation does NOT cover *hang* isolation, so without this watchdog
    /// the launcher would wait indefinitely with no render and no error. The owner
    /// should surface an error/log and decide whether to ``restart()``. Delivered
    /// off the timer queue; hop to the main actor as needed.
    public var onRequestTimeout: ((RequestTimeout) -> Void)?

    public struct TerminationInfo: Sendable {
        public var status: Int32
        /// True when the process ended via an uncaught signal (the typical
        /// "plugin crashed" shape) rather than a normal exit.
        public var byUncaughtSignal: Bool
    }

    /// Describes a parent→child request that timed out (no response within
    /// ``requestTimeout``).
    public struct RequestTimeout: Sendable {
        /// The JSON-RPC method that was sent (e.g. `host.loadPlugin`, `plugin.activate`).
        public var method: String
        /// The correlation id the request carried.
        public var id: String
        /// How long we waited before giving up.
        public var timeout: TimeInterval
    }

    /// Per-request response deadline. A parent→child *request* that gets no
    /// response within this window fires ``onRequestTimeout``. Notifications
    /// (`host.invokeAction` etc.) are fire-and-forget and are NOT timed. Default
    /// 10s; set to `0` (or negative) to disable the watchdog entirely.
    public let requestTimeout: TimeInterval

    private let lock = NSLock()
    private var process: Process?
    private var transport: StdioTransport?

    /// Monotonic epoch bumped on every (re)start. The async `Process`
    /// `terminationHandler` captures the epoch that was current when its child was
    /// spawned; on fire it only tears down state if that epoch is still current.
    /// Without this, an OLD child's late-arriving terminationHandler can stop the
    /// NEW child's transport after a `restart()` (the §5 race).
    private var generation = 0

    /// In-flight parent→child requests awaiting a response, keyed by correlation
    /// id, each with a one-shot deadline timer. Guarded by `lock`.
    private var pendingRequests: [String: PendingRequest] = [:]
    private let timerQueue = DispatchQueue(label: "vee.child.requesttimeout")

    private struct PendingRequest {
        var method: String
        var generation: Int
        var timer: DispatchSourceTimer
    }

    public init(executableURL: URL,
                arguments: [String] = [],
                environment: [String: String]? = nil,
                requestTimeout: TimeInterval = 10) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.requestTimeout = requestTimeout
        // SIGPIPE defense (audit §5), belt-and-suspenders with the per-fd
        // `F_SETNOSIGPIPE` each `StdioTransport` already sets: a write to a dead
        // child's pipe must return EPIPE, never terminate the parent launcher.
        signal(SIGPIPE, SIG_IGN)
    }

    /// True while a child process is running.
    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    // MARK: - Lifecycle

    /// Spawn the child and wire up the transport. Throws if the process can't be
    /// launched (e.g. the executable doesn't exist). Idempotent-ish: a prior live
    /// child is terminated first.
    public func start() throws {
        lock.lock()
        if let existing = process, existing.isRunning {
            lock.unlock()
            terminate()
            lock.lock()
        }

        // New epoch for this child. Captured by the terminationHandler below so a
        // late fire from a PRIOR child can't tear down THIS one (§5 race).
        generation += 1
        let myGeneration = generation

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        if let environment { proc.environment = environment }

        // Parent writes to the child's stdin; reads from the child's stdout.
        let stdinPipe = Pipe()    // parent → child
        let stdoutPipe = Pipe()   // child → parent
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        // Leave the child's stderr attached to ours so its diagnostics surface in
        // the parent's logs (it is NOT part of the RPC channel).

        let transport = StdioTransport(
            read: stdoutPipe.fileHandleForReading,
            write: stdinPipe.fileHandleForWriting,
            label: "vee.child.\(executableURL.lastPathComponent)")
        transport.onReceive = { [weak self] message in
            guard let self else { return }
            // A response to a correlated parent→child request cancels that
            // request's hang watchdog before the app sees the frame.
            if case .response(let r) = message, let id = r.id {
                self.completeRequest(idString: Self.idString(id))
            }
            self.onPluginMessage?(message)
        }
        // A protocol-level teardown (oversized frame, §5 max-frame bound) or a
        // plain EOF on the child's stdout surfaces here. Treat it like a
        // termination so any pending request timers are cleared; the
        // `terminationHandler` still delivers `onTermination` for the process exit.
        transport.onClose = { [weak self] in
            self?.failAllPendingRequests(generation: myGeneration)
        }

        // Supervision: a crashing child triggers terminationHandler. We translate
        // it into onTermination and tear down the transport. The parent lives on.
        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            let info = TerminationInfo(
                status: p.terminationStatus,
                byUncaughtSignal: p.terminationReason == .uncaughtSignal)
            self.lock.lock()
            // §5 race guard: only act if this handler belongs to the CURRENT
            // generation. A `restart()` bumps `generation` and swaps in a new
            // process+transport; an old child's terminationHandler firing late
            // must NOT stop the new child's transport or clear its state.
            let isCurrent = (myGeneration == self.generation)
            if isCurrent {
                self.transport?.stop()
                self.transport = nil
                self.process = nil
            }
            // Cancel any in-flight request timers from this generation regardless
            // (their child is gone), without touching a newer generation's.
            let staleTimers = self.pendingRequests.filter { $0.value.generation == myGeneration }
            for (key, pending) in staleTimers {
                pending.timer.cancel()
                self.pendingRequests[key] = nil
            }
            self.lock.unlock()
            self.onTermination?(info)
        }

        self.process = proc
        self.transport = transport
        lock.unlock()

        do {
            try proc.run()
        } catch {
            lock.lock()
            // Only roll back if we're still the current generation (paranoia: a
            // racing restart shouldn't have its state clobbered by our failure).
            if myGeneration == self.generation {
                self.process = nil
                self.transport = nil
            }
            lock.unlock()
            throw JSONRPCError.internalError(
                "ChildProcessHost: failed to launch \(executableURL.path): \(error)")
        }
        transport.resume()
    }

    /// Terminate the child (if any) and tear down the transport. Used by the
    /// owner on shutdown and by the crash-isolation test to simulate a crash.
    public func terminate() {
        lock.lock()
        let proc = process
        let t = transport
        // Cancel every in-flight request watchdog: the child is going away, so a
        // pending response will never arrive and we must not fire a spurious
        // timeout (or leak the timer).
        for (_, pending) in pendingRequests { pending.timer.cancel() }
        pendingRequests.removeAll()
        lock.unlock()
        t?.stop()
        if let proc, proc.isRunning {
            proc.terminate()   // SIGTERM
        }
    }

    /// Bring the child back after a crash (or a deliberate terminate). Spawns a
    /// fresh process + transport. The caller is responsible for re-`loadAndActivate`
    /// any plugins that were live before the crash (the child is stateless across
    /// restarts by design — its address space died with it).
    public func restart() throws {
        terminate()
        try start()
    }

    // MARK: - Parent → child control

    /// Send `host.loadPlugin` (manifest + source) then `plugin.activate` for
    /// `command`. Fire-and-forget over the pipe — the resulting `plugin.render`
    /// (and any `plugin.log`/`showToast`) come back asynchronously via
    /// `onPluginMessage`. Throws if no child is running.
    public func loadAndActivate(manifest: PluginManifest,
                                source: String,
                                command: String,
                                arguments: [String: JSONValue] = [:]) throws {
        let transport = try requireTransport()
        let loadParams = try JSONValueCoder.encode(LoadPluginParams(manifest: manifest, source: source))
        sendTrackedRequest(transport, id: "load-\(manifest.id)",
                           method: ChildHostMethods.loadPlugin, params: loadParams)
        let activateParams = try JSONValueCoder.encode(
            ActivateParams(pluginId: manifest.id, commandName: command, arguments: arguments))
        sendTrackedRequest(transport, id: "activate-\(manifest.id)",
                           method: RPCMethods.activate, params: activateParams)
    }

    /// Forward a `host.invokeAction` notification to the child.
    public func invokeAction(_ params: InvokeActionParams) throws {
        try forwardNotification(method: RPCMethods.invokeAction, params: params)
    }

    /// Forward a `host.onSearchTextChange` notification to the child.
    public func onSearchTextChange(_ params: SearchTextChangeParams) throws {
        try forwardNotification(method: RPCMethods.onSearchTextChange, params: params)
    }

    /// Forward a `host.submitForm` notification to the child.
    public func submitForm(_ params: SubmitFormParams) throws {
        try forwardNotification(method: RPCMethods.submitForm, params: params)
    }

    /// Forward a raw host→plugin notification (`host.invokeAction` /
    /// `host.onSearchTextChange` / `host.submitForm` / `plugin.deactivate`) to the
    /// child as-is — the passthrough the app's `CoordinatorTransport` bridge uses so
    /// it doesn't have to re-decode into the typed methods above. Fire-and-forget
    /// (notifications carry no response → no watchdog). A no-op when no child is
    /// running; the loss is already covered by `onTermination`/`restart()`.
    public func forward(_ message: JSONRPCMessage) {
        guard let transport = try? requireTransport() else { return }
        transport.send(message)
    }

    /// Send a `plugin.activate` for an already-loaded plugin (used after a
    /// restart that re-loaded the bundle, or to switch commands).
    public func activate(_ params: ActivateParams) throws {
        let transport = try requireTransport()
        let value = try JSONValueCoder.encode(params)
        sendTrackedRequest(transport, id: "activate-\(params.pluginId)",
                           method: RPCMethods.activate, params: value)
    }

    /// Send a `plugin.deactivate` request for a loaded plugin (the child stops
    /// delivering that command's events). Tracked like `activate`.
    public func deactivate(_ params: DeactivateParams) throws {
        let transport = try requireTransport()
        let value = try JSONValueCoder.encode(params)
        sendTrackedRequest(transport, id: "deactivate-\(params.pluginId)",
                           method: RPCMethods.deactivate, params: value)
    }

    /// Send a `host.loadPlugin` only (no activate). Lets the owner stage a plugin
    /// then activate a chosen command separately.
    public func load(manifest: PluginManifest, source: String) throws {
        let transport = try requireTransport()
        let value = try JSONValueCoder.encode(LoadPluginParams(manifest: manifest, source: source))
        sendTrackedRequest(transport, id: "load-\(manifest.id)",
                           method: ChildHostMethods.loadPlugin, params: value)
    }

    // MARK: - Child binary resolution

    /// Resolve the `vee-plugin-host` child binary for the *running* executable.
    ///
    /// In a shipped `.app`, the child is bundled next to the launcher executable
    /// (e.g. `Vee.app/Contents/MacOS/vee-plugin-host`, sibling of
    /// `Contents/MacOS/vee`), so the primary strategy is `Bundle.main.executableURL`
    /// → sibling `vee-plugin-host`. For `swift run`/`swift test` and other dev
    /// layouts the executable's own directory is searched as a fallback, and the
    /// `VEE_PLUGIN_HOST` environment override (an explicit absolute path) wins over
    /// everything so CI / tooling can point at a scratch build.
    ///
    /// - Parameter binaryName: the child executable's file name (default
    ///   `"vee-plugin-host"`).
    /// - Returns: the resolved URL if an executable file is found, else `nil` (the
    ///   caller decides whether to fall back to in-process or surface an error).
    public static func defaultChildBinaryURL(binaryName: String = "vee-plugin-host") -> URL? {
        let fm = FileManager.default

        // 1. Explicit override (CI / dev tooling).
        if let explicit = ProcessInfo.processInfo.environment["VEE_PLUGIN_HOST"],
           fm.isExecutableFile(atPath: explicit) {
            return URL(fileURLWithPath: explicit)
        }

        var candidates: [URL] = []
        // 2. Sibling of the bundle's main executable (the shipped `.app` layout).
        if let exe = Bundle.main.executableURL {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent(binaryName))
        }
        // 3. Sibling of the running process's argv[0] path (covers `swift run`
        //    and any layout where `Bundle.main.executableURL` is the same dir).
        if let argv0 = CommandLine.arguments.first {
            let exeDir = URL(fileURLWithPath: argv0).deletingLastPathComponent()
            candidates.append(exeDir.appendingPathComponent(binaryName))
        }

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }
        return nil
    }

    // MARK: - Helpers

    private func forwardNotification<P: Encodable>(method: String, params: P) throws {
        let transport = try requireTransport()
        let value = (try? JSONValueCoder.encode(params)) ?? .null
        transport.send(.notification(JSONRPCNotification(method: method, params: value)))
    }

    private func requireTransport() throws -> StdioTransport {
        lock.lock(); defer { lock.unlock() }
        guard let transport, process?.isRunning == true else {
            throw JSONRPCError.internalError("ChildProcessHost: no running child process")
        }
        return transport
    }

    // MARK: - Request timeout watchdog

    /// String form of a correlation id, for keying `pendingRequests`.
    private static func idString(_ id: JSONRPCID) -> String {
        switch id {
        case .string(let s): return s
        case .number(let n): return String(n)
        }
    }

    /// Send a parent→child *request* and arm a one-shot deadline timer keyed by
    /// `id`. If the child replies (any response carrying this id) the timer is
    /// cancelled in `completeRequest`; if the timer fires first we surface
    /// `onRequestTimeout` (the hang-isolation path — e.g. a plugin spinning inside
    /// `activate`). A `requestTimeout <= 0` disables the watchdog (send only).
    private func sendTrackedRequest(_ transport: StdioTransport, id: String,
                                    method: String, params: JSONValue) {
        if requestTimeout > 0 {
            lock.lock()
            // Replace any prior timer under the same id (a re-send supersedes it).
            pendingRequests[id]?.timer.cancel()
            let myGeneration = generation
            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(deadline: .now() + requestTimeout)
            timer.setEventHandler { [weak self] in
                self?.fireTimeout(id: id, method: method, generation: myGeneration)
            }
            pendingRequests[id] = PendingRequest(method: method, generation: myGeneration, timer: timer)
            lock.unlock()
            timer.resume()
        }
        transport.send(.request(JSONRPCRequest(id: .string(id), method: method, params: params)))
    }

    /// A response for `idString` arrived — cancel and forget its watchdog.
    private func completeRequest(idString id: String) {
        lock.lock()
        let pending = pendingRequests.removeValue(forKey: id)
        lock.unlock()
        pending?.timer.cancel()
    }

    /// The deadline elapsed with no response. Remove the entry and notify the
    /// owner (unless it was already completed/cancelled in the meantime).
    private func fireTimeout(id: String, method: String, generation: Int) {
        lock.lock()
        guard let pending = pendingRequests[id], pending.generation == generation else {
            lock.unlock(); return   // already answered / cancelled / superseded
        }
        pending.timer.cancel()
        pendingRequests[id] = nil
        lock.unlock()
        onRequestTimeout?(RequestTimeout(method: method, id: id, timeout: requestTimeout))
    }

    /// Cancel + drop every pending request for `generation` (the child's stdout
    /// hit EOF / a framing teardown). Does not fire timeouts — the loss is already
    /// signalled by `onClose`/`onTermination`.
    private func failAllPendingRequests(generation: Int) {
        lock.lock()
        let stale = pendingRequests.filter { $0.value.generation == generation }
        for (key, pending) in stale {
            pending.timer.cancel()
            pendingRequests[key] = nil
        }
        lock.unlock()
    }
}
