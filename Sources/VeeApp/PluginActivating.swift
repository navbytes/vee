import Foundation
import VeeProtocol
import VeeEngine

/// The lifecycle surface the coordinator drives: activate / deactivate a plugin
/// command. Injected so tests use a fake and production wires the real
/// `VeeEngine.PluginHost` (which conforms below). The coordinator never talks to
/// the host's render API — only lifecycle flows through here; renders/candidates/
/// events flow over the `CoordinatorTransport`.
public protocol PluginActivating: AnyObject {
    func activate(_ params: ActivateParams) throws
    func deactivate(_ params: DeactivateParams)
}

/// The real engine host satisfies the lifecycle contract directly (its
/// `activate(_:)` already throws, `deactivate(_:)` is void). Verified by
/// compilation; the GUI wiring is exercised manually.
extension PluginHost: PluginActivating {}
