import Foundation
import JavaScriptCore
import VeeProtocol

/// The native bridge injected into a plugin's `JSContext`: `console`, `vee`,
/// timers, and `fetch`. **All `@convention(block)` closures live in this one
/// file** so the two JSC memory rules are auditable in a single place:
///
///   RULE (a) — NEVER capture `context` inside a block. Every closure below
///   captures `[weak self]` (the bridge) and resolves the live context via
///   `JSContext.current()`. No closure closes over a `JSContext` or a strong
///   `JSBridge`/`PluginInstance` reference. This is what lets the context + VM
///   deallocate on teardown (proven by the no-leak-after-reload test).
///
///   RULE (b) — Wrap every STORED JS callback in `JSManagedValue` and register
///   it with `JSVirtualMachine.addManagedReference(_:withOwner:)`. Timer
///   callbacks, pending fetch resolvers, and `on*` event handlers are all stored
///   as `JSManagedValue`s owned by this bridge, and removed on teardown. This
///   gives "conditional retain" — the callback lives as long as the bridge
///   without forming a `context ⇄ block` cycle.
///
/// The bridge holds a `weak` back-reference to its `PluginInstance` for the few
/// operations that need instance services (emit a frame, schedule on the clock,
/// run an HTTP request). It never retains the instance.
final class JSBridge {
    /// The context this bridge is installed into. Strong here is fine: the
    /// instance owns the bridge owns the context; no block closes over it, so
    /// there is no cycle back from JS into native that would pin the context.
    private let context: JSContext
    let virtualMachine: JSVirtualMachine
    private let pluginId: String

    /// Back-reference to the owner for services (transport, clock, http,
    /// storage, capabilities, render). WEAK — the instance owns the bridge.
    weak var instance: PluginInstance?

    // MARK: Stored JS callbacks (RULE b — all JSManagedValue)

    /// Timer id → managed callback. The clock fires by token; we look up the
    /// managed value and call it (then drain microtasks).
    private var timerCallbacks: [Int: JSManagedValue] = [:]
    /// Registered host→plugin event handlers, by event kind. Additive.
    private var invokeActionHandlers: [JSManagedValue] = []
    private var searchTextChangeHandlers: [JSManagedValue] = []
    private var submitFormHandlers: [JSManagedValue] = []
    /// All managed values we created, so teardown removes every reference.
    private var allManaged: [JSManagedValue] = []

    init(context: JSContext, virtualMachine: JSVirtualMachine, pluginId: String) {
        self.context = context
        self.virtualMachine = virtualMachine
        self.pluginId = pluginId
    }

    // MARK: - Installation

    /// Inject all globals. MUST be called before evaluating the bundle.
    func install() {
        installConsole()
        installTimers()
        installVee()
    }

    /// Tear down: remove every managed reference so the context/VM can dealloc.
    /// Idempotent.
    func teardown() {
        for managed in allManaged {
            virtualMachine.removeManagedReference(managed, withOwner: self)
        }
        allManaged.removeAll()
        timerCallbacks.removeAll()
        invokeActionHandlers.removeAll()
        searchTextChangeHandlers.removeAll()
        submitFormHandlers.removeAll()
    }

    /// Store a JS callback as a managed reference owned by this bridge (RULE b).
    private func manage(_ value: JSValue) -> JSManagedValue {
        let managed = JSManagedValue(value: value)!
        virtualMachine.addManagedReference(managed, withOwner: self)
        allManaged.append(managed)
        return managed
    }

    private func unmanage(_ managed: JSManagedValue) {
        virtualMachine.removeManagedReference(managed, withOwner: self)
        allManaged.removeAll { $0 === managed }
    }

    // MARK: - console (RUNTIME.md §2.1)

    private func installConsole() {
        let console = JSValue(newObjectIn: context)!

        func makeLogger(_ level: LogParams.Level) -> @convention(block) () -> Void {
            // RULE (a): capture [weak self], not `context`. Resolve args via the
            // current invocation's arguments.
            return { [weak self] in
                guard let self else { return }
                let args = JSContext.currentArguments() as? [JSValue] ?? []
                let message = self.stringify(args)
                self.instance?.emitLog(level: level, message: message)
            }
        }

        console.setObject(makeLogger(.debug) as Any, forKeyedSubscript: "debug" as NSString)
        console.setObject(makeLogger(.info) as Any, forKeyedSubscript: "info" as NSString)
        console.setObject(makeLogger(.info) as Any, forKeyedSubscript: "log" as NSString)   // log aliases info
        console.setObject(makeLogger(.warn) as Any, forKeyedSubscript: "warn" as NSString)
        console.setObject(makeLogger(.error) as Any, forKeyedSubscript: "error" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    /// Stringify console args: objects via JSON.stringify, else String(x),
    /// joined by a space (RUNTIME.md §2.1).
    private func stringify(_ args: [JSValue]) -> String {
        guard let ctx = JSContext.current() else { return "" }
        let stringifier = ctx.evaluateScript("""
            (function(x){
                if (typeof x === 'string') return x;
                if (x === undefined) return 'undefined';
                if (x === null) return 'null';
                try { var s = JSON.stringify(x); return s === undefined ? String(x) : s; }
                catch (e) { return String(x); }
            })
        """)!
        return args.map { arg in
            stringifier.call(withArguments: [arg])?.toString() ?? "undefined"
        }.joined(separator: " ")
    }

    // MARK: - timers (ARCHITECTURE.md §1; backed by injectable Clock)

    private func installTimers() {
        // setTimeout(cb, delayMs, ...args) → token
        let setTimeout: @convention(block) (JSValue, JSValue) -> Int = { [weak self] cb, delay in
            self?.scheduleTimer(cb, delayMs: delay.toDouble(), repeats: false) ?? 0
        }
        let setInterval: @convention(block) (JSValue, JSValue) -> Int = { [weak self] cb, delay in
            self?.scheduleTimer(cb, delayMs: delay.toDouble(), repeats: true) ?? 0
        }
        let clearTimer: @convention(block) (JSValue) -> Void = { [weak self] id in
            self?.cancelTimer(Int(id.toInt32()))
        }
        context.setObject(unsafeBitCast(setTimeout, to: AnyObject.self), forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(unsafeBitCast(setInterval, to: AnyObject.self), forKeyedSubscript: "setInterval" as NSString)
        context.setObject(unsafeBitCast(clearTimer, to: AnyObject.self), forKeyedSubscript: "clearTimeout" as NSString)
        context.setObject(unsafeBitCast(clearTimer, to: AnyObject.self), forKeyedSubscript: "clearInterval" as NSString)
    }

    private func scheduleTimer(_ cb: JSValue, delayMs: Double, repeats: Bool) -> Int {
        guard let instance else { return 0 }
        let managed = manage(cb)
        let delaySeconds = (delayMs.isFinite ? delayMs : 0) / 1000.0
        // The token returned by the clock IS the JS-visible timer id.
        var assignedToken = 0
        let token = instance.clock.schedule(after: delaySeconds, repeats: repeats) { [weak self] in
            guard let self else { return }
            // Marshal onto the instance's serial queue: JSC serializes execution
            // per VM, so the JS callback MUST run there (the production
            // DispatchClock fires on its own queue; the TestClock fires inline).
            self.instance?.runOnQueue {
                // Fire the stored callback. After it returns JSC has drained the
                // microtask queue (a Promise .then chained off the callback runs
                // here); we also drain explicitly as belt-and-suspenders so a
                // microtask never trails into the next macrotask.
                if let managedCb = self.timerCallbacks[assignedToken], let value = managedCb.value {
                    value.call(withArguments: [])
                }
                self.instance?.drainMicrotasks()
                // One-shot timers retire after firing.
                if !repeats {
                    if let m = self.timerCallbacks.removeValue(forKey: assignedToken) {
                        self.unmanage(m)
                    }
                }
            }
        }
        assignedToken = token
        timerCallbacks[token] = managed
        return token
    }

    private func cancelTimer(_ token: Int) {
        instance?.clock.cancel(token)
        if let managed = timerCallbacks.removeValue(forKey: token) {
            unmanage(managed)
        }
    }

    // MARK: - vee host object (RUNTIME.md §2.2)

    private func installVee() {
        let vee = JSValue(newObjectIn: context)!

        // pluginId (readonly identity)
        vee.setObject(pluginId, forKeyedSubscript: "pluginId" as NSString)

        // render(node) — capture [weak self]; resolve the tree from the arg.
        let render: @convention(block) (JSValue) -> Void = { [weak self] node in
            self?.handleRender(node)
        }
        vee.setObject(unsafeBitCast(render, to: AnyObject.self), forKeyedSubscript: "render" as NSString)

        // setCandidates(candidates)
        let setCandidates: @convention(block) (JSValue) -> Void = { [weak self] candidates in
            self?.handleSetCandidates(candidates)
        }
        vee.setObject(unsafeBitCast(setCandidates, to: AnyObject.self), forKeyedSubscript: "setCandidates" as NSString)

        // showToast(style, title, message?)
        let showToast: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] style, title, message in
            self?.handleToast(style: style, title: title, message: message)
        }
        vee.setObject(unsafeBitCast(showToast, to: AnyObject.self), forKeyedSubscript: "showToast" as NSString)

        // onInvokeAction / onSearchTextChange / onSubmitForm → return an
        // unsubscribe function. Handlers stored as managed values (RULE b).
        installEventRegistrar(on: vee, name: "onInvokeAction", kind: .invokeAction)
        installEventRegistrar(on: vee, name: "onSearchTextChange", kind: .searchTextChange)
        installEventRegistrar(on: vee, name: "onSubmitForm", kind: .submitForm)

        // http.fetch(url, init?) → Promise
        let http = JSValue(newObjectIn: context)!
        let fetch: @convention(block) (JSValue, JSValue) -> JSValue? = { [weak self] url, options in
            self?.handleFetch(url: url, options: options)
        }
        http.setObject(unsafeBitCast(fetch, to: AnyObject.self), forKeyedSubscript: "fetch" as NSString)
        vee.setObject(http, forKeyedSubscript: "http" as NSString)

        // storage.get(key) / set(key, value, ttl?) → Promise
        let storage = JSValue(newObjectIn: context)!
        let storageGet: @convention(block) (JSValue) -> JSValue? = { [weak self] key in
            self?.handleStorageGet(key: key)
        }
        let storageSet: @convention(block) (JSValue, JSValue, JSValue) -> JSValue? = { [weak self] key, value, ttl in
            self?.handleStorageSet(key: key, value: value, ttl: ttl)
        }
        storage.setObject(unsafeBitCast(storageGet, to: AnyObject.self), forKeyedSubscript: "get" as NSString)
        storage.setObject(unsafeBitCast(storageSet, to: AnyObject.self), forKeyedSubscript: "set" as NSString)
        vee.setObject(storage, forKeyedSubscript: "storage" as NSString)

        context.setObject(vee, forKeyedSubscript: "vee" as NSString)
    }

    private enum EventKind { case invokeAction, searchTextChange, submitForm }

    private func installEventRegistrar(on vee: JSValue, name: String, kind: EventKind) {
        let register: @convention(block) (JSValue) -> JSValue? = { [weak self] handler in
            guard let self, let ctx = JSContext.current() else { return nil }
            let managed = self.manage(handler)
            switch kind {
            case .invokeAction:     self.invokeActionHandlers.append(managed)
            case .searchTextChange: self.searchTextChangeHandlers.append(managed)
            case .submitForm:       self.submitFormHandlers.append(managed)
            }
            // Return an unsubscribe function. It captures [weak self] and the
            // managed value (a native object, not the context) — no context capture.
            let unsubscribe: @convention(block) () -> Void = { [weak self] in
                guard let self else { return }
                self.removeHandler(managed, kind: kind)
            }
            return JSValue(object: unsafeBitCast(unsubscribe, to: AnyObject.self), in: ctx)
        }
        vee.setObject(unsafeBitCast(register, to: AnyObject.self), forKeyedSubscript: name as NSString)
    }

    private func removeHandler(_ managed: JSManagedValue, kind: EventKind) {
        switch kind {
        case .invokeAction:     invokeActionHandlers.removeAll { $0 === managed }
        case .searchTextChange: searchTextChangeHandlers.removeAll { $0 === managed }
        case .submitForm:       submitFormHandlers.removeAll { $0 === managed }
        }
        unmanage(managed)
    }

    // MARK: - vee member handlers

    private func handleRender(_ node: JSValue) {
        // Project the JS value to a JSONValue (the canonical wire shape) and hand
        // it to the instance, which diffs + emits + mirrors.
        guard let value = JSONBridge.toJSONValue(node) else { return }
        instance?.handleRenderTree(value)
    }

    private func handleSetCandidates(_ candidates: JSValue) {
        guard let value = JSONBridge.toJSONValue(candidates),
              case .array = value else { return }
        instance?.emitSetCandidates(value)
    }

    private func handleToast(style: JSValue, title: JSValue, message: JSValue) {
        let styleStr = style.toString() ?? "info"
        let toastStyle = ToastParams.Style(rawValue: styleStr) ?? .info
        let msg = (message.isUndefined || message.isNull) ? nil : message.toString()
        instance?.emitToast(style: toastStyle, title: title.toString() ?? "", message: msg)
    }

    // MARK: - fetch (capability-gated)

    private func handleFetch(url: JSValue, options: JSValue) -> JSValue? {
        guard let ctx = JSContext.current(), let instance else { return nil }
        let urlString = url.toString() ?? ""

        // Build the FetchParams from the JS init object.
        var method = "GET"
        var headers: [String: String] = [:]
        var bodyBase64: String? = nil
        if !options.isUndefined, !options.isNull {
            if let m = options.objectForKeyedSubscript("method"), !m.isUndefined, !m.isNull {
                method = m.toString() ?? "GET"
            }
            if let h = options.objectForKeyedSubscript("headers"),
               let dict = JSONBridge.toJSONValue(h)?.objectValue {
                for (k, v) in dict { if let s = v.stringValue { headers[k] = s } }
            }
            if let b = options.objectForKeyedSubscript("body"), !b.isUndefined, !b.isNull,
               let s = b.toString() {
                bodyBase64 = Data(s.utf8).base64EncodedString()
            }
        }
        let params = FetchParams(url: urlString, method: method, headers: headers, bodyBase64: bodyBase64)

        return PromiseFactory.make(in: ctx) { resolve, reject in
            // Capability gate: reject without ever touching the client when the
            // host is not in the network allowlist.
            let host = URL(string: urlString)?.host ?? ""
            guard instance.capabilities.allowsNetworkHost(host) else {
                instance.runOnQueue {
                    let err = JSONRPCError.capabilityDenied("network host not allowed: \(host)")
                    reject(JSBridge.errorValue(in: ctx, code: err.code, message: err.message))
                    instance.drainMicrotasks()
                }
                return
            }
            instance.performFetch(params) { result in
                // Hop back onto the instance's serial queue to settle the Promise.
                instance.runOnQueue {
                    switch result {
                    case .success(let fetchResult):
                        let responseObj = JSBridge.makeResponseObject(in: ctx, result: fetchResult)
                        resolve(responseObj)
                    case .failure(let error):
                        let code = (error as? JSONRPCError)?.code ?? -32000
                        reject(JSBridge.errorValue(in: ctx, code: code, message: "\(error)"))
                    }
                    instance.drainMicrotasks()
                }
            }
        }
    }

    /// Build the JS Response façade: { status, headers, text(), json() }.
    private static func makeResponseObject(in ctx: JSContext, result: FetchResult) -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        obj.setObject(result.status, forKeyedSubscript: "status" as NSString)
        obj.setObject(result.headers, forKeyedSubscript: "headers" as NSString)
        let bodyText = (Data(base64Encoded: result.bodyBase64)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        // text() → Promise<string>
        let text: @convention(block) () -> JSValue? = {
            guard let cur = JSContext.current() else { return nil }
            return PromiseFactory.make(in: cur) { resolve, _ in
                resolve(JSValue(object: bodyText, in: cur))
            }
        }
        obj.setObject(unsafeBitCast(text, to: AnyObject.self), forKeyedSubscript: "text" as NSString)
        // json() → Promise<JSONValue>
        let json: @convention(block) () -> JSValue? = {
            guard let cur = JSContext.current() else { return nil }
            return PromiseFactory.make(in: cur) { resolve, reject in
                let parsed = cur.evaluateScript("(function(s){ return JSON.parse(s); })")!
                if let result = parsed.call(withArguments: [bodyText]), !result.isUndefined {
                    resolve(result)
                } else {
                    reject(JSBridge.errorValue(in: cur, code: -32000, message: "invalid json"))
                }
            }
        }
        obj.setObject(unsafeBitCast(json, to: AnyObject.self), forKeyedSubscript: "json" as NSString)
        return obj
    }

    // MARK: - storage

    private func handleStorageGet(key: JSValue) -> JSValue? {
        guard let ctx = JSContext.current(), let instance else { return nil }
        let k = key.toString() ?? ""
        return PromiseFactory.make(in: ctx) { resolve, _ in
            instance.runOnQueue {
                let value = instance.storage.get(k) ?? .null
                resolve(JSONBridge.toJSValue(value, in: ctx))
                instance.drainMicrotasks()
            }
        }
    }

    private func handleStorageSet(key: JSValue, value: JSValue, ttl: JSValue) -> JSValue? {
        guard let ctx = JSContext.current(), let instance else { return nil }
        let k = key.toString() ?? ""
        let v = JSONBridge.toJSONValue(value) ?? .null
        let ttlSeconds: Double? = (ttl.isUndefined || ttl.isNull) ? nil : ttl.toDouble()
        return PromiseFactory.make(in: ctx) { resolve, _ in
            instance.runOnQueue {
                instance.storage.set(k, value: v, ttlSeconds: ttlSeconds)
                resolve(JSValue(undefinedIn: ctx))
                instance.drainMicrotasks()
            }
        }
    }

    // MARK: - Host → plugin dispatch (called by the instance)

    func dispatchInvokeAction(_ params: InvokeActionParams) {
        let paramsValue = JSONBridge.toJSValue((try? JSONValueCoder.encode(params)) ?? .null, in: context)
        for managed in invokeActionHandlers {
            managed.value?.call(withArguments: [paramsValue])
        }
        instance?.drainMicrotasks()
    }

    func dispatchSearchTextChange(_ params: SearchTextChangeParams) {
        let paramsValue = JSONBridge.toJSValue((try? JSONValueCoder.encode(params)) ?? .null, in: context)
        let query = JSValue(object: params.query, in: context)!
        for managed in searchTextChangeHandlers {
            managed.value?.call(withArguments: [query, paramsValue])   // query first, then full params
        }
        instance?.drainMicrotasks()
    }

    func dispatchSubmitForm(_ params: SubmitFormParams) {
        let paramsValue = JSONBridge.toJSValue((try? JSONValueCoder.encode(params)) ?? .null, in: context)
        for managed in submitFormHandlers {
            managed.value?.call(withArguments: [paramsValue])
        }
        instance?.drainMicrotasks()
    }

    // MARK: - error helper

    /// Build a JS Error carrying a numeric `code` so plugins can branch on
    /// capability denials etc.
    static func errorValue(in ctx: JSContext, code: Int, message: String) -> JSValue {
        let factory = ctx.evaluateScript("(function(code, msg){ var e = new Error(msg); e.code = code; return e; })")!
        return factory.call(withArguments: [code, message]) ?? JSValue(newErrorFromMessage: message, in: ctx)
    }
}
