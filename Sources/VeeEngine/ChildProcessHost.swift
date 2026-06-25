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

    public struct TerminationInfo: Sendable {
        public var status: Int32
        /// True when the process ended via an uncaught signal (the typical
        /// "plugin crashed" shape) rather than a normal exit.
        public var byUncaughtSignal: Bool
    }

    private let lock = NSLock()
    private var process: Process?
    private var transport: StdioTransport?

    public init(executableURL: URL,
                arguments: [String] = [],
                environment: [String: String]? = nil) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
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
            self?.onPluginMessage?(message)
        }

        // Supervision: a crashing child triggers terminationHandler. We translate
        // it into onTermination and tear down the transport. The parent lives on.
        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            let info = TerminationInfo(
                status: p.terminationStatus,
                byUncaughtSignal: p.terminationReason == .uncaughtSignal)
            self.lock.lock()
            self.transport?.stop()
            // Only clear if this is still the current process (a restart may have
            // already swapped in a new one).
            if self.process === p {
                self.transport = nil
                self.process = nil
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
            lock.lock(); self.process = nil; self.transport = nil; lock.unlock()
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
        transport.send(.request(JSONRPCRequest(
            id: .string("load-\(manifest.id)"),
            method: ChildHostMethods.loadPlugin,
            params: loadParams)))
        let activateParams = try JSONValueCoder.encode(
            ActivateParams(pluginId: manifest.id, commandName: command, arguments: arguments))
        transport.send(.request(JSONRPCRequest(
            id: .string("activate-\(manifest.id)"),
            method: RPCMethods.activate,
            params: activateParams)))
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

    /// Send a `plugin.activate` for an already-loaded plugin (used after a
    /// restart that re-loaded the bundle, or to switch commands).
    public func activate(_ params: ActivateParams) throws {
        let transport = try requireTransport()
        let value = try JSONValueCoder.encode(params)
        transport.send(.request(JSONRPCRequest(
            id: .string("activate-\(params.pluginId)"),
            method: RPCMethods.activate, params: value)))
    }

    /// Send a `host.loadPlugin` only (no activate). Lets the owner stage a plugin
    /// then activate a chosen command separately.
    public func load(manifest: PluginManifest, source: String) throws {
        let transport = try requireTransport()
        let value = try JSONValueCoder.encode(LoadPluginParams(manifest: manifest, source: source))
        transport.send(.request(JSONRPCRequest(
            id: .string("load-\(manifest.id)"),
            method: ChildHostMethods.loadPlugin, params: value)))
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
}
