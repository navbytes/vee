import Foundation
import JavaScriptCore
import VeeProtocol
import VeeJSONPatch

/// One live plugin: a single `JSContext` on its own `JSVirtualMachine`, the
/// injected bridge, the render mirror, and the serial execution context.
///
/// Lifecycle (RUNTIME.md §5): create context → inject globals (`install()`) →
/// evaluate the IIFE bundle → read `__veePlugin` → `activateCommand`. The host
/// drives reload by discarding the instance and building a fresh one.
///
/// Memory: the instance owns the context, the VM, and the bridge. The bridge's
/// blocks hold only a `weak` reference back here, and stored JS callbacks are
/// `JSManagedValue`s removed on `teardown()`. So dropping the host's strong
/// reference to an instance (on reload/unload) lets the whole graph — instance,
/// bridge, context, VM — deallocate. The no-leak-after-reload test proves it.
public final class PluginInstance {
    public let manifest: PluginManifest
    public var pluginId: String { manifest.id }
    public var capabilities: Capabilities { manifest.capabilities }

    let context: JSContext
    public let virtualMachine: JSVirtualMachine
    private let bridge: JSBridge
    private let mirror: RenderMirror

    let transport: RPCTransport
    let clock: Clock
    let httpClient: HTTPClient
    let storage: StorageBackend

    /// Serial queue for all JS execution & frame handling, so frames stay
    /// ordered and JSC's single-threaded-per-VM rule is never violated. The
    /// deterministic test path runs everything inline on the calling thread via
    /// `runOnQueue`, which detects re-entrancy.
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()

    /// Optional hook: observe the raw rendered tree projection (used by the
    /// fixture-handshake test to capture exactly what `vee.render` received).
    public var onRenderTree: ((JSONValue) -> Void)?

    /// The last error captured by the JSC exception handler during the current
    /// synchronous evaluation, surfaced as a Swift error by `evaluateOrThrow`.
    private var pendingException: JSONRPCError?

    public init(
        manifest: PluginManifest,
        transport: RPCTransport,
        clock: Clock,
        httpClient: HTTPClient,
        storage: StorageBackend = InMemoryStorage()
    ) throws {
        self.manifest = manifest
        self.transport = transport
        self.clock = clock
        self.httpClient = httpClient
        self.storage = storage
        self.queue = DispatchQueue(label: "vee.engine.instance.\(manifest.id)")
        self.mirror = RenderMirror(pluginId: manifest.id)

        guard let vm = JSVirtualMachine() else {
            throw JSONRPCError.internalError("failed to create JSVirtualMachine")
        }
        guard let ctx = JSContext(virtualMachine: vm) else {
            throw JSONRPCError.internalError("failed to create JSContext")
        }
        self.virtualMachine = vm
        self.context = ctx
        self.bridge = JSBridge(context: ctx, virtualMachine: vm, pluginId: manifest.id)

        queue.setSpecific(key: queueKey, value: ())

        // RULE: install the exception handler BEFORE any evaluation, so syntax
        // and runtime errors are captured (evaluateScript fails silently
        // otherwise). The handler captures [weak self] — never the context.
        ctx.exceptionHandler = { [weak self] _, exception in
            guard let self else { return }
            self.captureException(exception)
        }

        // Wire the bridge back to this instance and inject all globals BEFORE
        // the bundle is ever evaluated (RUNTIME.md §5 step 1).
        self.bridge.instance = self
        self.bridge.install()

        // Self-subscribe to inbound host→plugin frames addressed to this plugin.
        // When this instance is owned by a `PluginHost`, the host installs its
        // own multiplexing `onReceive` (overriding this) and forwards via
        // `dispatch`. For a standalone instance + loopback (the round-trip test
        // path) this self-subscription is what delivers `host.invokeAction` etc.
        // The closure captures [weak self] — never the context.
        self.transport.onReceive = { [weak self] message in
            guard let self else { return }
            if self.isAddressedToUs(message) {
                self.dispatch(message)
            }
        }
    }

    /// True when an inbound frame's `pluginId` targets this instance (or carries
    /// no plugin id, in which case a standalone instance still handles it).
    private func isAddressedToUs(_ message: JSONRPCMessage) -> Bool {
        guard case .notification(let note) = message else { return false }
        guard let pid = note.params?["pluginId"]?.stringValue else { return true }
        return pid == pluginId
    }

    deinit {
        // Defensive: ensure managed references are gone even if teardown wasn't
        // explicitly called (it normally is, by the host, before drop).
        bridge.teardown()
    }

    // MARK: - Serial execution

    /// Run `work` on the instance's serial queue. If we're already on it
    /// (re-entrant native→JS→native call), run inline to preserve ordering and
    /// avoid deadlock. This keeps the synchronous test driver deterministic.
    func runOnQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync { work() }
        }
    }

    // MARK: - Evaluation

    /// Evaluate `script`, returning the result `JSValue` (or nil). Errors are
    /// captured by the exception handler but not thrown (use `evaluateOrThrow`).
    @discardableResult
    public func evaluate(_ script: String) -> JSValue? {
        var result: JSValue?
        runOnQueue {
            self.pendingException = nil
            result = self.context.evaluateScript(script)
            // JSC drains the microtask queue on return from evaluateScript; the
            // explicit drain is belt-and-suspenders.
            self.drainMicrotasksInline()
        }
        return result
    }

    /// Evaluate `script`; throw a `JSONRPCError.pluginError` if the exception
    /// handler fired (syntax or runtime error).
    @discardableResult
    public func evaluateOrThrow(_ script: String) throws -> JSValue? {
        var thrown: JSONRPCError?
        var result: JSValue?
        runOnQueue {
            self.pendingException = nil
            result = self.context.evaluateScript(script)
            self.drainMicrotasksInline()
            thrown = self.pendingException
        }
        if let thrown { throw thrown }
        return result
    }

    private func captureException(_ exception: JSValue?) {
        let message = exception?.toString() ?? "unknown JS exception"
        // Attach the JS stack in `data` when available (RUNTIME.md §5 step 3).
        var data: JSONValue? = nil
        if let stack = exception?.objectForKeyedSubscript("stack"), !stack.isUndefined, !stack.isNull,
           let s = stack.toString() {
            data = .object(["stack": .string(s)])
        }
        pendingException = JSONRPCError.pluginError(message, data: data)
    }

    // MARK: - Microtask discipline (ARCHITECTURE.md §1, the ordering hazard)

    /// Drain the JS microtask (Promise job) queue. JSC runs queued microtasks
    /// when control returns to the VM, so evaluating a trivial script flushes any
    /// pending `.then` jobs. We call this after every native→JS callback (timer
    /// fire, fetch/storage settle, host→plugin dispatch) so a chained Promise
    /// `.then` always runs BEFORE the next macrotask is dequeued.
    func drainMicrotasks() {
        runOnQueue { self.drainMicrotasksInline() }
    }

    private func drainMicrotasksInline() {
        // Returning to the VM via evaluateScript flushes the microtask queue.
        // A no-op expression is enough to give the engine a turn.
        context.evaluateScript("")
    }

    // MARK: - Command discovery & activation (RUNTIME.md §4, §5)

    /// Read `globalThis.__veePlugin.commandNames`. Throws pluginError if the
    /// bundle never registered (malformed).
    public func commandNames() throws -> [String] {
        var names: [String]?
        var error: JSONRPCError?
        runOnQueue {
            guard let plugin = self.context.objectForKeyedSubscript("__veePlugin"),
                  !plugin.isUndefined, !plugin.isNull else {
                error = .pluginError("bundle did not register __veePlugin")
                return
            }
            guard let namesValue = plugin.objectForKeyedSubscript("commandNames"),
                  let array = namesValue.toArray() else {
                error = .pluginError("__veePlugin.commandNames is missing or not an array")
                return
            }
            names = array.compactMap { $0 as? String }
        }
        if let error { throw error }
        return names ?? []
    }

    /// Call `__veePlugin.activateCommand(name, ctx)`. Builds the `CommandContext`
    /// (RUNTIME.md §5 step 3) with a `render` convenience bound to `vee.render`.
    /// A throw/rejection surfaces as `JSONRPCError.pluginError` with the JS stack.
    public func activateCommand(_ name: String, arguments: [String: JSONValue]) throws {
        var thrown: JSONRPCError?
        runOnQueue {
            self.pendingException = nil
            guard let plugin = self.context.objectForKeyedSubscript("__veePlugin"),
                  !plugin.isUndefined, !plugin.isNull else {
                thrown = .pluginError("bundle did not register __veePlugin")
                return
            }
            // Build CommandContext: { pluginId, commandName, arguments, render }.
            let ctxObj = JSValue(newObjectIn: self.context)!
            ctxObj.setObject(self.pluginId, forKeyedSubscript: "pluginId" as NSString)
            ctxObj.setObject(name, forKeyedSubscript: "commandName" as NSString)
            let argsValue = JSONBridge.toJSValue(.object(arguments), in: self.context)
            ctxObj.setObject(argsValue, forKeyedSubscript: "arguments" as NSString)
            // render convenience === vee.render
            if let vee = self.context.objectForKeyedSubscript("vee"),
               let render = vee.objectForKeyedSubscript("render") {
                ctxObj.setObject(render, forKeyedSubscript: "render" as NSString)
            }

            let result = plugin.invokeMethod("activateCommand", withArguments: [name, ctxObj])
            self.drainMicrotasksInline()

            // A synchronous throw was captured by the exception handler.
            if let ex = self.pendingException { thrown = ex; return }

            // If activate returned a Promise, surface a rejection as pluginError.
            if let result, PluginInstance.isPromise(result) {
                if let rejection = self.awaitPromiseRejection(result) {
                    thrown = rejection
                }
            }
        }
        if let thrown { throw thrown }
    }

    private static func isPromise(_ value: JSValue) -> Bool {
        guard let ctx = value.context else { return false }
        let check = ctx.evaluateScript("(function(x){ return x && typeof x.then === 'function'; })")!
        return check.call(withArguments: [value])?.toBool() ?? false
    }

    /// Synchronously settle a returned Promise (deterministic test path) and
    /// return a pluginError if it rejected. Resolved/pending → nil.
    private func awaitPromiseRejection(_ promise: JSValue) -> JSONRPCError? {
        var rejection: JSONRPCError?
        let onReject: @convention(block) (JSValue) -> Void = { err in
            let message = err.objectForKeyedSubscript("message")?.toString() ?? err.toString() ?? "rejected"
            var data: JSONValue? = nil
            if let stack = err.objectForKeyedSubscript("stack"), !stack.isUndefined,
               let s = stack.toString() { data = .object(["stack": .string(s)]) }
            rejection = .pluginError(message, data: data)
        }
        promise.invokeMethod("catch", withArguments: [unsafeBitCast(onReject, to: AnyObject.self)])
        drainMicrotasksInline()
        return rejection
    }

    // MARK: - Render handling (called by the bridge on vee.render)

    /// The bridge projected a `vee.render(tree)` call to a JSONValue. Notify the
    /// optional observer, diff against the mirror, advance the mirror, and emit
    /// `plugin.render` with the next monotonic revision (RUNTIME.md §3).
    func handleRenderTree(_ tree: JSONValue) {
        onRenderTree?(tree)
        guard let params = mirror.ingest(tree: tree) else { return }
        transport.notify(method: RPCMethods.render, params: params)
    }

    /// The current mirrored tree as a `RenderNode` (nil before first render).
    public func currentRenderTree() -> RenderNode? {
        var node: RenderNode?
        runOnQueue { node = try? self.mirror.currentTree() }
        return node
    }

    // MARK: - Outbound notifications (called by the bridge)

    func emitLog(level: LogParams.Level, message: String) {
        transport.notify(method: RPCMethods.log,
                         params: LogParams(pluginId: pluginId, level: level, message: message))
    }

    func emitToast(style: ToastParams.Style, title: String, message: String?) {
        transport.notify(method: RPCMethods.toast,
                         params: ToastParams(pluginId: pluginId, style: style, title: title, message: message))
    }

    func emitSetCandidates(_ candidatesValue: JSONValue) {
        // Decode to [Candidate] for a typed, validated payload, then re-emit.
        let candidates: [Candidate] = (try? JSONValueCoder.decode([Candidate].self, from: candidatesValue)) ?? []
        transport.notify(method: RPCMethods.setCandidates,
                         params: SetCandidatesParams(pluginId: pluginId, candidates: candidates))
    }

    // MARK: - Bridge service calls

    func performFetch(_ params: FetchParams, completion: @escaping (Result<FetchResult, Error>) -> Void) {
        httpClient.perform(params, completion: completion)
    }

    // MARK: - Host → plugin event dispatch (RUNTIME.md §6)

    func dispatch(_ message: JSONRPCMessage) {
        guard case .notification(let note) = message, let params = note.params else { return }
        runOnQueue {
            switch note.method {
            case RPCMethods.invokeAction:
                if let p = try? JSONValueCoder.decode(InvokeActionParams.self, from: params) {
                    self.bridge.dispatchInvokeAction(p)
                }
            case RPCMethods.onSearchTextChange:
                if let p = try? JSONValueCoder.decode(SearchTextChangeParams.self, from: params) {
                    self.bridge.dispatchSearchTextChange(p)
                }
            case RPCMethods.submitForm:
                if let p = try? JSONValueCoder.decode(SubmitFormParams.self, from: params) {
                    self.bridge.dispatchSubmitForm(p)
                }
            default:
                break
            }
        }
    }

    // MARK: - Quiescence (test helper)

    /// Drive the deterministic path until no microtasks remain. For the test
    /// clock + synchronous HTTP client, settling happens inline, so this just
    /// drains the microtask queue a few times to flush chained `.then`s.
    public func runUntilQuiescent() {
        runOnQueue {
            for _ in 0..<16 { self.drainMicrotasksInline() }
        }
    }

    // MARK: - Teardown

    /// Remove all managed references so the context + VM can deallocate. Called
    /// by the host before dropping its strong reference (reload/unload).
    func teardown() {
        runOnQueue {
            self.bridge.teardown()
            self.context.exceptionHandler = nil
        }
    }
}
