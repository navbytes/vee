import Foundation
import VeeProtocol
import VeeEngine
import VeeApp

// R2-CRIT-2: bridge the launcher's `AppCoordinator` to an out-of-process
// `ChildProcessHost`. The coordinator depends only on `CoordinatorTransport`
// (host↔launcher frames) and `PluginActivating` (lifecycle), so making plugins run
// in a separate process — the spec's headline crash-isolation guarantee — reduces
// to these two thin adapters plus staging the bundles into the child. A plugin that
// crashes JSC now kills the child, not the launcher (the supervisor restarts it).

/// `CoordinatorTransport` over a child process. Host→plugin frames
/// (`host.invokeAction`/`onSearchTextChange`/`submitForm`) are forwarded to the
/// child; the child's outbound `plugin.*` frames are delivered to the coordinator
/// on the main actor (the child's stdout reader runs off-main, and the coordinator
/// + AppKit both require main-thread access).
final class ChildCoordinatorTransport: CoordinatorTransport {
    private let child: ChildProcessHost
    init(_ child: ChildProcessHost) { self.child = child }

    func attachInbound(_ handler: @escaping (JSONRPCMessage) -> Void) {
        child.onPluginMessage = { message in
            DispatchQueue.main.async { MainActor.assumeIsolated { handler(message) } }
        }
    }

    func sendToHost(_ message: JSONRPCMessage) {
        child.forward(message)
    }
}

/// `PluginActivating` over a child process. The plugin bundle is staged once via
/// `child.load(...)`; activating a command (or deactivating it) becomes a tracked
/// control request to the child.
final class ChildActivatingHost: PluginActivating {
    private let child: ChildProcessHost
    init(_ child: ChildProcessHost) { self.child = child }

    func activate(_ params: ActivateParams) throws {
        try child.activate(params)
    }

    func deactivate(_ params: DeactivateParams) {
        try? child.deactivate(params)
    }
}
