import Foundation
import VeeProtocol
import VeeEngine
import VeeServices
import VeeFuzzy

/// Drives the launcher: owns the search query, runs `VeeFuzzy` over the current
/// candidate set, maps the plugin's `RenderNode` tree (and incoming `PatchOp`
/// diffs) into AppKit view models (the "view-model shielding" layer), and
/// dispatches actions back to the host.
///
/// > Wave 3 worker: implement per build plan §4. Keep ALL logic here (testable);
/// > keep `NSView`/`NSApplication`/menubar code behind protocols and thin.
/// > Preserve selection by candidate `id` across list patches. Tests first
/// > (render-tree→view-model mapping, selection preservation, action dispatch).
public final class AppCoordinator {
    public init() {}
    // Wave 0 stub: real implementation lands in Wave 3.
}
