import Foundation
import VeeProtocol
import VeeJSONPatch

/// The host's mirror of a plugin's render tree.
///
/// Flow (RUNTIME.md §3, ARCHITECTURE.md §3): the plugin calls `vee.render(tree)`
/// with a complete tree; the host diffs it against the previously-rendered tree
/// (`JSONPatch.diff`), bumps a monotonic `revision`, and emits the patch as a
/// `plugin.render` notification. The host keeps a mirror it advances by applying
/// the very same patch (`JSONPatch.apply`) — so the mirror is exactly what a
/// patch-applying consumer downstream would reconstruct.
///
/// - First render: diff against `.null` ⇒ a single `replace ""` (whole tree).
/// - Subsequent renders: minimal diffs (a one-prop change ⇒ one `replace`).
/// - Out-of-order: a revision ≤ the last accepted revision is dropped.
public final class RenderMirror {
    public let pluginId: String

    /// The current mirrored document (JSONValue projection). `.null` until the
    /// first accepted render.
    private(set) var mirror: JSONValue = .null

    /// Monotonic revision of the last accepted render (0 = nothing yet).
    public private(set) var revision: Int = 0

    public init(pluginId: String) {
        self.pluginId = pluginId
    }

    /// Ingest a freshly-rendered tree projection.
    ///
    /// - If `revision` is explicit and not greater than the current revision,
    ///   the frame is stale and dropped (returns nil — no patch, no change).
    /// - Otherwise compute the diff vs. the current mirror, advance the mirror
    ///   by applying that diff, set the revision, and return `RenderParams`
    ///   ready to ship as a `plugin.render` notification.
    ///
    /// `explicitRevision` lets tests inject specific revisions to prove the
    /// monotonic guard. In the live pipeline the instance passes the next
    /// auto-incremented revision.
    @discardableResult
    public func ingest(tree: JSONValue, revision explicitRevision: Int? = nil) -> RenderParams? {
        let next = explicitRevision ?? (revision + 1)
        // Drop stale / out-of-order frames.
        guard next > revision else { return nil }

        let patch = JSONPatch.diff(mirror, tree)
        // Advance the mirror by applying the patch we just computed, so the
        // mirror is precisely the patched document (not merely the input tree).
        if let applied = try? JSONPatch.apply(patch, to: mirror) {
            mirror = applied
        } else {
            // Defensive: a diff we computed should always apply; if not, fall
            // back to the input so the mirror never silently diverges.
            mirror = tree
        }
        revision = next
        return RenderParams(pluginId: pluginId, revision: next, patch: patch)
    }

    /// The current mirror as a `RenderNode`, or nil if nothing has rendered.
    public func currentTree() throws -> RenderNode? {
        if case .null = mirror { return nil }
        return try RenderNode(jsonValue: mirror)
    }

    /// The raw mirrored JSONValue (for tests/diagnostics).
    public func currentValue() -> JSONValue { mirror }
}
