import Foundation

/// VeeEngine-local bridge method names that the frozen `VeeProtocol.RPCMethods`
/// catalog does not (yet) declare.
///
/// CONTRACT GAP: `vee.open` / `vee.openApp` are new JS→host bridges, but the
/// frozen protocol has no `bridge.open` / `bridge.openApp` method string (and no
/// `Capabilities` flag for opening — see `JSBridge.handleOpen`). Rather than edit
/// the frozen `RPCMethods` (out of scope), we define the method strings here so
/// the engine has a stable local name should it ever route these over the wire.
/// They follow the existing `bridge.*` convention. When the protocol is unfrozen,
/// these should migrate into `RPCMethods` and this file be deleted.
enum BridgeMethods {
    /// `vee.open(url)` — open a URL/file in the default handler.
    static let open = "bridge.open"
    /// `vee.openApp(bundleId)` — launch an app by bundle id.
    static let openApp = "bridge.openApp"
}
