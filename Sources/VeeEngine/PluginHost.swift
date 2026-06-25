import Foundation
import VeeProtocol
import VeeJSONPatch
import VeeCache
import VeeKeychain

/// The JavaScriptCore plugin host: one `JSContext` per plugin on its own
/// `JSVirtualMachine`, the console/timer/fetch bridge, the JSON-RPC transport,
/// the render-tree mirror (patches applied via `VeeJSONPatch`), and hot reload.
///
/// > Wave 2a worker: implement per build plan §4. Design the `RPCTransport`
/// > protocol + in-memory loopback double, the bridge protocols (`HTTPClient`,
/// > `FileWatcher`, `Bundler`, `Clock`), and obey the two JSC memory rules:
/// > (1) never capture `context` inside a `@convention(block)` closure (use
/// > `JSContext.current`); (2) wrap stored JS callbacks in `JSManagedValue`.
/// > Drain microtasks before macrotasks. Tests first (incl. no-leak-after-reload).
public final class PluginHost {
    public init() {}
    // Wave 0 stub: real implementation lands in Wave 2a.
}
