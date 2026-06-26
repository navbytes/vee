import Foundation
import VeeEngine
import VeeProtocol
#if canImport(AppKit)
import AppKit
#endif

// MARK: - vee-plugin-host (out-of-process child)
//
// Speaks framed JSON-RPC over stdin/stdout to the parent `vee` launcher, running
// plugins in JavaScriptCore in its OWN address space so a crashing plugin cannot
// take down the launcher (architecture §2, "run plugins out-of-process"). This is
// the child end of `ChildProcessHost`.
//
// Inbound control protocol (parent → child):
//   • host.loadPlugin    {manifest, source}            → PluginHost.load
//   • plugin.activate     ActivateParams               → PluginHost.activate
//   • plugin.deactivate   DeactivateParams             → PluginHost.deactivate
//   • host.invokeAction / host.onSearchTextChange / host.submitForm
//                         (notifications)              → routed to the instance
//
// Outbound (child → parent), produced by the PluginHost's transport:
//   • plugin.render / plugin.setCandidates / plugin.log / plugin.showToast
//
// Bridges served LOCALLY (real implementations) in this process:
//   • HTTP   — URLSessionHTTPClient (real network, gated by each plugin's
//              `Capabilities.network` allowlist in the bridge).
//   • open   — NSWorkspaceOpenProvider (open URLs / launch apps).
//   • fs     — FileManagerFileProvider (path confinement enforced by the bridge
//              against `Capabilities.filesystem` before any call lands here).
//   • clipboard — NSPasteboard-backed read provider (copy + plain-text history of
//              the current pasteboard contents). Capability-gated by the bridge.
//
// Bridges DENIED / EMPTY in this process (documented caveats):
//   • calendar — EmptyCalendarProvider. EventKit access is bound to the *app's*
//                TCC identity (the user grants Calendar to the Vee app bundle, not
//                to this child executable), so a standalone child cannot serve it.
//                Returning an empty list ("no upcoming meetings") is the safe
//                default; the real calendar data is wired in the app layer, or via
//                a future delegation of `bridge.calendar.*` back over the pipe.
//   • keychain — InMemorySecretStore default. Real Keychain items are also scoped
//                to the app's identity; the app wires a real SecretStore. (Left at
//                the engine default here; not load-bearing for this milestone.)

/// Inbound control method the parent sends to load a plugin. Kept in sync with
/// `VeeEngine.ChildHostMethods.loadPlugin` (a private parent↔child control method,
/// deliberately NOT part of the frozen `RPCMethods`). Defined as a local constant
/// here per the build rules (do not edit VeeProtocol).
let kLoadPluginMethod = "host.loadPlugin"

// A `NoopFileWatcher` + `StaticBundler` placeholder: hot reload in OOP mode is
// driven by the parent re-sending `host.loadPlugin`, not by this child watching
// files (the bundle source arrives over the pipe). The bundler is only consulted
// on `PluginHost.reload`, which the parent does not invoke in this child.
let transport = StdioTransport(read: .standardInput, write: .standardOutput, label: "vee.host.stdio")

#if canImport(AppKit)
let clipboardProvider: ClipboardProviding = NSPasteboardClipboardProvider()
let openProvider: OpenProviding = NSWorkspaceOpenProvider()
let fileProvider: FileProviding = FileManagerFileProvider()
// `vee.notify` from a menu-bar plugin posts a real system notification. Best-effort
// from the child: `UserNotificationProvider` self-guards on the bundle identifier
// and degrades to a no-op when notifications aren't deliverable in this context.
let notificationProvider: NotificationProviding = UserNotificationProvider()
#else
let clipboardProvider: ClipboardProviding = DenyingClipboardProvider()
let openProvider: OpenProviding = RecordingOpenProvider()
let fileProvider: FileProviding = DenyingFileProvider()
let notificationProvider: NotificationProviding = NoopNotificationProvider()
#endif

let host = PluginHost(
    transport: transport,
    clock: DispatchClock(),
    httpClient: URLSessionHTTPClient(),
    fileWatcher: NoopFileWatcher(),
    bundler: UnsupportedBundler(),
    clipboardProvider: clipboardProvider,
    openProvider: openProvider,
    fileProvider: fileProvider,
    calendarProvider: EmptyCalendarProvider(),   // calendar caveat — see header.
    notificationProvider: notificationProvider)

// Keep the loaded manifests so a `plugin.activate` can map a plugin id → command.
// (Not strictly needed; PluginHost owns instances. Retained for clarity/logging.)
final class ControlRouter {
    let host: PluginHost
    let transport: StdioTransport
    init(host: PluginHost, transport: StdioTransport) {
        self.host = host
        self.transport = transport
    }

    /// Point the transport's inbound handler at this router. Called at startup and
    /// again after every `host.load` (which clobbers `onReceive` via
    /// `PluginInstance.init`).
    func reclaimTransport() {
        transport.onReceive = { [weak self] message in self?.route(message) }
    }

    /// Route one inbound frame. Control requests (loadPlugin/activate/deactivate)
    /// are handled here; host→plugin notifications are forwarded to the matching
    /// instance via the host's routing. We OWN `onReceive` (overriding the one the
    /// PluginHost installs in its init) because the control requests are not
    /// addressed to a plugin instance.
    func route(_ message: JSONRPCMessage) {
        switch message {
        case .request(let req):
            handleRequest(req)
        case .notification(let note):
            forwardNotification(note)
        case .response:
            break   // the parent does not currently send responses to the child
        }
    }

    private func handleRequest(_ req: JSONRPCRequest) {
        do {
            switch req.method {
            case kLoadPluginMethod:
                let params = try decode(LoadPluginParams.self, from: req.params)
                _ = try host.load(manifest: params.manifest, source: params.source)
                // `PluginInstance.init` (inside `host.load`) installs its OWN
                // `transport.onReceive` self-subscription, clobbering ours. Re-claim
                // the transport so subsequent control frames (activate, host→plugin
                // events) keep reaching this router. See the contract-gap note.
                reclaimTransport()
                respondOK(to: req.id)
            case RPCMethods.activate:
                let params = try decode(ActivateParams.self, from: req.params)
                try host.activate(params)
                respondOK(to: req.id)
            case RPCMethods.deactivate:
                let params = try decode(DeactivateParams.self, from: req.params)
                host.deactivate(params)
                respondOK(to: req.id)
            default:
                transport.send(.response(JSONRPCResponse(
                    id: req.id, error: .methodNotFound(req.method))))
            }
        } catch let rpc as JSONRPCError {
            transport.send(.response(JSONRPCResponse(id: req.id, error: rpc)))
        } catch {
            transport.send(.response(JSONRPCResponse(
                id: req.id, error: .internalError("\(error)"))))
        }
    }

    /// Host→plugin notifications (invokeAction / onSearchTextChange / submitForm):
    /// forward to the addressed instance. PluginInstance.dispatch decodes + runs
    /// the JS handler on the instance's serial queue.
    private func forwardNotification(_ note: JSONRPCNotification) {
        host.routeHostEvent(.notification(note))
    }

    private func respondOK(to id: JSONRPCID) {
        transport.send(.response(JSONRPCResponse(id: id, result: .object([:]))))
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue?) throws -> T {
        guard let value else { throw JSONRPCError.invalidParams("missing params") }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

let router = ControlRouter(host: host, transport: transport)

// Override the host's default `onReceive` so we see ALL inbound frames (including
// the control requests, which the host's own router ignores). We then forward
// host→plugin notifications into the instances ourselves. Re-claimed after each
// `host.load` (which re-points `onReceive` from inside `PluginInstance.init`).
router.reclaimTransport()

// Exit cleanly when the parent closes our stdin (EOF) — the launcher went away.
transport.onClose = {
    exit(0)
}

FileHandle.standardError.write(Data("vee-plugin-host: ready\n".utf8))
transport.resume()

// Park on the run loop so DispatchSource read events + timer fires are serviced.
// `transport.onClose` calls `exit(0)` on EOF, ending the process.
RunLoop.current.run()
