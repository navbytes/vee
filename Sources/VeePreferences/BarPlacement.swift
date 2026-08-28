import Foundation

/// Where a plugin appears in the menu bar — the user's choice, never the
/// plugin author's.
///
/// This is deliberately not the same question as `<vee.surface>`
/// (`HeaderMetadata.WidgetSurface`). That declaration decides whether a plugin
/// has a *menu surface at all*: a `.widget` plugin gets no status item, no menu,
/// and no menu-mode schedule. Placement decides only where an existing menu
/// surface is presented, so `.hidden` costs a plugin its menu-bar presence and
/// nothing else — its runs, its detached window, its search panel, and anything
/// it publishes for the widget all continue.
///
/// `folded` carries the shared item it folds into rather than being a second
/// boolean. There is exactly one group today (`defaultGroup`), and no UI to
/// make another, but the roadmap's Focus filters need a plugin-grouping model;
/// naming the group now means that arrives as a new value rather than as a
/// second migration of everyone's stored preference.
public enum BarPlacement: Equatable, Hashable, Sendable {
    /// Its own `NSStatusItem` — one icon per plugin, the shipped default.
    case own
    /// A row inside a shared item's menu, identified by group name.
    case folded(group: String)
    /// No menu-bar presence at all.
    case hidden

    /// The only group Vee folds into today: its own home item.
    public static let defaultGroup = "Vee"

    /// `folded` into the one group that exists — what every caller means until
    /// named groups ship.
    public static let foldedDefault = BarPlacement.folded(group: defaultGroup)

    // MARK: - Storage

    /// The stored spelling. `folded` keeps its group so a later multi-group
    /// build reads today's values unchanged.
    public var encoded: String {
        switch self {
        case .own: return "own"
        case .folded(let group): return "folded:" + group
        case .hidden: return "hidden"
        }
    }

    /// Decodes a stored spelling, or `nil` for anything this build does not
    /// recognise — an absent, truncated, or newer-than-us value. Callers fall
    /// back to the default placement rather than inventing one, so a
    /// preferences domain written by a future version can never strand a
    /// plugin on a surface this build cannot draw.
    public init?(encoded: String) {
        switch encoded {
        case "own": self = .own
        case "hidden": self = .hidden
        default:
            // Split on the FIRST separator only: the remainder is the group
            // name, which is free-form and may itself contain one.
            guard let separator = encoded.firstIndex(of: ":"),
                  encoded[..<separator] == "folded" else { return nil }
            let group = String(encoded[encoded.index(after: separator)...])
            guard !group.isEmpty else { return nil }
            self = .folded(group: group)
        }
    }

    /// Whether this placement draws anything in the menu bar. `hidden` is the
    /// only one that does not.
    public var hasBarPresence: Bool {
        self != .hidden
    }
}
