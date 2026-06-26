import Foundation
import JavaScriptCore
import VeeProtocol
import VeeJSONPatch
import VeeCache
import VeeKeychain

/// The JavaScriptCore plugin host: one `JSContext` per plugin on its own
/// `JSVirtualMachine`, the console/timer/fetch bridge, the JSON-RPC transport,
/// the render-tree mirror (patches applied via `VeeJSONPatch`), and hot reload.
///
/// Architecture (docs/ARCHITECTURE.md §1–§4, RUNTIME.md §5):
///   • `load` creates a `PluginInstance`, injects globals, and evaluates the
///     bundle so the bundle's top-level `definePlugin` publishes `__veePlugin`.
///   • `activate` builds the `CommandContext` and calls `activateCommand`.
///   • `reload` tears down the old context/VM, rebuilds via the injected
///     `Bundler`, and re-activates the previously-active command. The OLD
///     instance is dropped so its VM deallocates (no-leak guarantee).
///   • `deactivate`/`unload` stop event delivery / drop the instance.
///   • Hot reload: the injected `FileWatcher` fires per-plugin → `reload`.
///
/// Memory rules are enforced inside `JSBridge` (single auditable file): blocks
/// never capture `context`; stored JS callbacks are `JSManagedValue`s removed on
/// teardown. The host's only job is to drop the strong instance reference on
/// reload/unload so the graph collapses.
public final class PluginHost {
    private let transport: RPCTransport
    private let clock: Clock
    private let httpClient: HTTPClient
    private let fileWatcher: FileWatcher
    private let bundler: Bundler
    private let makeStorage: (String) -> StorageBackend
    private let clipboardProvider: ClipboardProviding
    private let secretStore: any SecretStore
    private let openProvider: OpenProviding
    private let fileProvider: FileProviding
    private let calendarProvider: CalendarProviding

    /// Live instances by plugin id.
    private var instances: [String: PluginInstance] = [:]
    /// The currently-activated command per plugin (for re-activation on reload).
    private var activeCommand: [String: (name: String, arguments: [String: JSONValue])] = [:]
    /// Manifests by plugin id (for rebuild/re-create on reload).
    private var manifests: [String: PluginManifest] = [:]

    public init(
        transport: RPCTransport,
        clock: Clock,
        httpClient: HTTPClient,
        fileWatcher: FileWatcher = NoopFileWatcher(),
        bundler: Bundler,
        storageFactory: @escaping (String) -> StorageBackend = { _ in InMemoryStorage() },
        clipboardProvider: ClipboardProviding = DenyingClipboardProvider(),
        secretStore: any SecretStore = InMemorySecretStore(),
        openProvider: OpenProviding = RecordingOpenProvider(),
        fileProvider: FileProviding = DenyingFileProvider(),
        calendarProvider: CalendarProviding = EmptyCalendarProvider()
    ) {
        self.transport = transport
        self.clock = clock
        self.httpClient = httpClient
        self.fileWatcher = fileWatcher
        self.bundler = bundler
        self.makeStorage = storageFactory
        self.clipboardProvider = clipboardProvider
        self.secretStore = secretStore
        self.openProvider = openProvider
        self.fileProvider = fileProvider
        self.calendarProvider = calendarProvider

        // Route inbound peer frames (host→plugin notifications) to the matching
        // instance. The transport delivers on its serial queue.
        self.transport.onReceive = { [weak self] message in
            self?.routeInbound(message)
        }
    }

    /// Convenience initializer wiring the production defaults (URLSession-backed
    /// HTTP, no-op file watcher). Bundler must still be supplied.
    public convenience init(bundler: Bundler) {
        self.init(
            transport: LoopbackTransport(),
            clock: DispatchClock(),
            httpClient: URLSessionHTTPClient(),
            fileWatcher: NoopFileWatcher(),
            bundler: bundler)
    }

    // MARK: - Lookup

    public func instance(for pluginId: String) -> PluginInstance? {
        instances[pluginId]
    }

    // MARK: - Load (create context, inject globals, evaluate bundle)

    /// Create a fresh instance for `manifest`, inject globals, evaluate `source`
    /// (the IIFE bundle), and register for hot reload. If an instance already
    /// exists for this id it is torn down first (so re-load is idempotent and
    /// leak-free).
    @discardableResult
    public func load(manifest: PluginManifest, source: String) throws -> PluginInstance {
        // Drop any prior instance for this id, dropping its strong ref so the old
        // VM deallocates.
        if let old = instances[manifest.id] {
            old.teardown()
            instances[manifest.id] = nil
        }

        let instance = try PluginInstance(
            manifest: manifest,
            transport: transport,
            clock: clock,
            httpClient: httpClient,
            storage: makeStorage(manifest.id),
            clipboardProvider: clipboardProvider,
            secretStore: secretStore,
            openProvider: openProvider,
            fileProvider: fileProvider,
            calendarProvider: calendarProvider,
            // The host owns the transport's `onReceive` multiplexer (installed in
            // init, routing to every instance by id). Instances must NOT seize it
            // or only the last-loaded plugin would get events (ARCH-2).
            ownsTransportInbound: false)

        // Evaluate the bundle; a malformed bundle throws pluginError.
        try instance.evaluateOrThrow(source)

        instances[manifest.id] = instance
        manifests[manifest.id] = manifest

        // Register for hot reload.
        fileWatcher.watch(pluginId: manifest.id) { [weak self] id in
            // A file change → rebuild + reload. Swallow build/reload errors into
            // a log frame so a bad rebuild doesn't kill the host.
            do { try self?.reload(ReloadParams(pluginId: id)) }
            catch { self?.transport.notify(method: RPCMethods.log,
                                           params: LogParams(pluginId: id, level: .error,
                                                             message: "reload failed: \(error)")) }
        }
        return instance
    }

    // MARK: - Activate (RUNTIME.md §5 step 3)

    public func activate(_ params: ActivateParams) throws {
        guard let instance = instances[params.pluginId] else {
            throw JSONRPCError.pluginError("no loaded plugin: \(params.pluginId)")
        }
        try instance.activateCommand(params.commandName, arguments: params.arguments)
        activeCommand[params.pluginId] = (params.commandName, params.arguments)
    }

    // MARK: - Deactivate (RUNTIME.md §5 step 5)

    public func deactivate(_ params: DeactivateParams) {
        // The current SDK has no explicit deactivate hook; we simply stop
        // delivering events for that command.
        activeCommand[params.pluginId] = nil
    }

    // MARK: - Reload (RUNTIME.md §5 step 6)

    /// Tear down the plugin's context, build a fresh bundle, create a new
    /// context, re-inject globals, re-eval, and re-activate the previously-active
    /// command. The OLD instance's strong reference is dropped here so its VM
    /// deallocates — the retain-cycle guard.
    public func reload(_ params: ReloadParams) throws {
        guard let manifest = manifests[params.pluginId] else {
            throw JSONRPCError.pluginError("no manifest to reload: \(params.pluginId)")
        }
        let previouslyActive = activeCommand[params.pluginId]

        // 1. Tear down + DROP the old instance (let the VM deallocate).
        if let old = instances[params.pluginId] {
            old.teardown()
            instances[params.pluginId] = nil
        }

        // 2. Rebuild the bundle via the injected bundler.
        let source = try bundler.build(pluginId: params.pluginId)

        // 3. Fresh context + globals + eval (load() handles teardown-if-present,
        //    which is now a no-op since we already dropped it).
        let instance = try load(manifest: manifest, source: source)

        // 4. Notify JS land of the reload (rehydrate from state if provided).
        let reloadValue = (try? JSONValueCoder.encode(params)) ?? .null
        _ = reloadValue   // available to a future plugin.reload JS hook

        // 5. Re-activate the previously-active command.
        if let active = previouslyActive {
            try instance.activateCommand(active.name, arguments: active.arguments)
            activeCommand[params.pluginId] = active
        }
    }

    // MARK: - Unload

    /// Stop watching, tear down, and drop the instance (VM deallocates).
    public func unload(pluginId: String) {
        fileWatcher.unwatch(pluginId: pluginId)
        if let instance = instances[pluginId] {
            instance.teardown()
        }
        instances[pluginId] = nil
        activeCommand[pluginId] = nil
        manifests[pluginId] = nil
    }

    // MARK: - Inbound routing (host → plugin notifications)

    /// Route a host→plugin notification (`host.invokeAction` /
    /// `host.onSearchTextChange` / `host.submitForm`) to its addressed instance.
    ///
    /// This is the same logic the host installs as its transport `onReceive` in
    /// `init`. It is exposed publicly so an owner that takes over the transport's
    /// `onReceive` for its own framing/control layer (e.g. the out-of-process
    /// `vee-plugin-host` child, which must also handle control *requests* the
    /// host's router ignores) can still delegate plugin event delivery here
    /// instead of reaching into `PluginInstance`.
    public func routeHostEvent(_ message: JSONRPCMessage) {
        routeInbound(message)
    }

    private func routeInbound(_ message: JSONRPCMessage) {
        guard case .notification(let note) = message,
              let params = note.params,
              let pluginId = params["pluginId"]?.stringValue,
              let instance = instances[pluginId] else { return }
        instance.dispatch(message)
    }
}

/// Production clock backed by `DispatchSourceTimer`. Each scheduled timer fires
/// on a private serial queue; the bridge hops back to the instance queue.
public final class DispatchClock: Clock {
    private let queue = DispatchQueue(label: "vee.engine.clock")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var timers: [Int: DispatchSourceTimer] = [:]
    private var nextToken = 1

    public init() {
        queue.setSpecific(key: queueKey, value: 1)
    }

    /// Run `work` on the serial queue, but inline if we're ALREADY on it. A
    /// one-shot timer's event handler fires *on* `queue` and then calls `cancel`;
    /// a plain `queue.sync` there re-enters the held queue and traps (R2-CRIT-1 /
    /// the original MAC-4). Mirrors the `LoopbackTransport` re-entrancy guard.
    private func onQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return work() }
        return queue.sync(execute: work)
    }

    public func schedule(after delay: TimeInterval, repeats: Bool, _ fire: @escaping () -> Void) -> Int {
        return onQueue {
            let token = nextToken; nextToken += 1
            let timer = DispatchSource.makeTimerSource(queue: queue)
            if repeats {
                timer.schedule(deadline: .now() + delay, repeating: delay)
            } else {
                timer.schedule(deadline: .now() + delay)
            }
            timer.setEventHandler { [weak self] in
                fire()
                if !repeats { self?.cancel(token) }
            }
            timers[token] = timer
            timer.resume()
            return token
        }
    }

    public func cancel(_ token: Int) {
        onQueue {
            timers[token]?.cancel()
            timers[token] = nil
        }
    }
}
