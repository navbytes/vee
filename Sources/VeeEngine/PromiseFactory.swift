import Foundation
import JavaScriptCore

/// Creates a JS `Promise` whose `resolve`/`reject` are surfaced to native code.
///
/// JSC has `Promise` but no native API to construct a deferred. The portable
/// technique: evaluate `new Promise((resolve, reject) => …)` and, inside the
/// executor, hand the two functions back to native via a captured block. We then
/// invoke them when the underlying native operation settles.
///
/// Microtask note: when `resolve`/`reject` is called, JSC schedules the
/// dependent `.then` callbacks as microtasks and drains them on return from the
/// native→JS call. The bridge additionally calls `drainMicrotasks()` after
/// settling to guarantee the queue is flushed before the next macrotask.
///
/// Memory note (rule a): the executor block does NOT capture a `JSContext`; it
/// only captures the local `box` (a native reference holder). The returned
/// `JSValue` (the Promise) is owned by JS land for the duration of its lifetime.
enum PromiseFactory {
    /// Build a Promise in `ctx`. `executor` receives `resolve`/`reject` closures
    /// that forward a `JSValue` into the JS Promise machinery. They are safe to
    /// call asynchronously (later, from the instance's serial queue).
    static func make(
        in ctx: JSContext,
        _ executor: (_ resolve: @escaping (JSValue) -> Void,
                     _ reject: @escaping (JSValue) -> Void) -> Void
    ) -> JSValue {
        // Holder for the JS resolve/reject functions captured from the executor.
        final class Resolvers {
            var resolve: JSValue?
            var reject: JSValue?
        }
        let box = Resolvers()

        // The JS-side executor captures the two functions into native via this
        // block. It does not capture `ctx`.
        let capture: @convention(block) (JSValue, JSValue) -> Void = { resolve, reject in
            box.resolve = resolve
            box.reject = reject
        }
        let promiseCtor = ctx.evaluateScript("""
            (function(capture){
                return new Promise(function(resolve, reject){ capture(resolve, reject); });
            })
        """)!
        let promise: JSValue = promiseCtor.call(withArguments: [unsafeBitCast(capture, to: AnyObject.self)])
            ?? JSValue(undefinedIn: ctx)!

        // Native-facing settle closures. They tolerate being called before/after
        // the executor has run (the executor runs synchronously inside the
        // Promise constructor above, so resolvers are always set by now).
        let resolve: (JSValue) -> Void = { value in
            box.resolve?.call(withArguments: [value])
        }
        let reject: (JSValue) -> Void = { error in
            box.reject?.call(withArguments: [error])
        }
        executor(resolve, reject)
        return promise
    }
}
