import Foundation

/// Where each item of the menu's vocabulary stands on the widget surface:
/// drawn there too, or deliberately left out for a stated reason.
///
/// This type exists to be a **compile-time guard**, not a lookup table. Nothing
/// in the app calls it at runtime — its whole job is that
/// `disposition(of: MenuAccessory)` switches over every case with no `default`,
/// so adding a display graphic to the menu stops compiling until someone says
/// what the widget does with it. The gap between the two surfaces is allowed to
/// exist; going unanswered is not. That is the same discipline as `MenuSurface`
/// deciding row membership once, rather than each renderer deciding for itself.
///
/// The dispositions are published as a table in `docs/design/surface-parity.md`,
/// which `WidgetParityTests` regenerates and asserts is current — so a *reason*
/// can't drift from the ledger either. Exclusions are recorded rather than
/// implied: "no `shell` on a widget" is a security decision (the widget surface
/// contract's §6) and "no live sliders" is a WidgetKit fact, and both are the
/// kind of answer that gets re-litigated every year if nobody wrote it down.
///
/// Lives in `VeePluginFormat` because it is the only module that can see both
/// halves: the menu vocabulary (`MenuAccessory`, `LineParams`) and the widget
/// schema it depends on (`VeeWidgetShared`).
public enum WidgetParity {
    /// A vocabulary item's standing on the widget. An exclusion always carries
    /// its reason — an unexplained one is indistinguishable from an oversight,
    /// which is the state this whole type exists to make impossible.
    public enum Disposition: Equatable, Sendable {
        case supported
        case excluded(reason: String)
    }

    /// The widget's answer for every display graphic a menu row can draw.
    ///
    /// Exhaustive on purpose — **do not add a `default`**. The compiler
    /// refusing to build a new `MenuAccessory` case until it appears here is
    /// the guard; a `default` would turn it back into a silent gap.
    public static func disposition(of accessory: MenuAccessory) -> Disposition {
        switch accessory {
        case .progress:
            // The `gauge` template and the layout tree's `gauge` leaf draw the
            // same clamped 0…1 fill as `progress=`.
            return .supported
        case .sparkline:
            // The `trend` template and the `sparkline` leaf, from the same series.
            return .supported
        case .chart:
            // The `chart` leaf, carrying the same three `ChartKind` shapes and
            // the same eight-segment fold as a menu row's.
            return .supported
        }
    }

    /// What a menu row can *do* when it is activated.
    ///
    /// A hand-kept mirror of the set `MenuTree.dispatches` tests, one case per
    /// `if` there, and the only reason it exists: Swift cannot enumerate that
    /// function's checks, so the parity ledger needs a set it can iterate.
    /// Adding a kind to `MenuTree.dispatches` means adding it here too — the
    /// switch below then refuses to compile until the widget question is
    /// answered, which is the whole point.
    public enum ActionKind: String, CaseIterable, Sendable {
        case control
        case shell
        case webview
        case sparkline
        case chart
        case href
        case shortcut
        case refresh
    }

    /// The widget's answer for every action kind the menu dispatches.
    ///
    /// Exhaustive on purpose, for the same reason as `disposition(of:)`.
    public static func disposition(ofActionKind kind: ActionKind) -> Disposition {
        switch kind {
        case .control:
            return .excluded(reason: "WidgetKit renders a static timeline with discrete AppIntent buttons; a toggle or slider has no live value to track and no continuous input to receive")
        case .shell:
            return .excluded(reason: "the widget surface contract's §6 trust decision: a widget button must not run an arbitrary command without the menu's context")
        case .webview:
            return .excluded(reason: "the bounded-canvas policy: the widget vocabulary is a closed set of native primitives, never a freeform drawing surface")
        case .sparkline:
            // The graphic itself renders (the `sparkline` leaf). Clicking one on
            // a menu opens a popover; a tile has no popover, and the data the
            // popover would show is already on the tile.
            return .supported
        case .chart:
            // As `.sparkline`, via the `chart` leaf.
            return .supported
        case .href:
            return .supported
        case .shortcut:
            return .supported
        case .refresh:
            return .supported
        }
    }
}
