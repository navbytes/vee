import Foundation

/// One presentation of a plugin's menu, in the vocabulary a plugin writes it in
/// (`visibleOn=menu,window`).
///
/// The names are the surfaces a *reader* sees rather than the modules that draw
/// them: `menu` is the menu-bar dropdown, `search` the transient filter panel,
/// `window` a detached plugin window, `cli` a terminal listing (`vee search`).
///
/// `widget` is deliberately not a case. Body rows never reach the widget, which
/// a plugin targets whole via `<vee.surface>`; offering the value here would
/// promise a per-row control that nothing could honour.
public enum MenuSurface: String, CaseIterable, Sendable {
    case menu
    case search
    case window
    case cli

    /// Every surface — what a row declaring no `visibleOn=` exists on, and what
    /// an unreadable declaration falls back to. Targeting only ever subtracts.
    public static let everywhere = Set(MenuSurface.allCases)

    /// Whether a row declaring `params` exists on this surface.
    ///
    /// `dropdown=false` is the compatibility alias for "no surface at all": the
    /// same subtree-removing path targeting takes, which is what ends its old
    /// fork (`MenuFlattener` used to hide the row and keep descending). An
    /// explicit `visibleOn=` outranks it — the parsers report that conflict,
    /// where both keys are still in view.
    public func shows(_ params: LineParams) -> Bool {
        if let declared = params.swiftbar.visibleOn { return declared.contains(self) }
        return params.dropdown != false
    }

    /// Resolves the raw values of a `visibleOn` declaration into the surfaces a
    /// row exists on, or `nil` for "not declared".
    ///
    /// A declaration naming nothing this build recognises degrades to `nil`
    /// rather than to the empty set: hiding takes a whole subtree with it, and
    /// a row is worth more than a typo. Shared by the line and JSON parsers so
    /// the two spellings cannot come to mean different things.
    static func parseList(_ values: [String], diagnostics: inout [ParseDiagnostic]) -> Set<MenuSurface>? {
        var declared: Set<MenuSurface> = []
        var sawUnknown = false
        for raw in values {
            let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if token.isEmpty { continue }
            guard let surface = MenuSurface(rawValue: token) else {
                sawUnknown = true
                diagnostics.append(.init(
                    severity: .warning,
                    message: "visibleOn= expects 'menu', 'search', 'window', or 'cli'; ignored '\(token)'"
                ))
                continue
            }
            declared.insert(surface)
        }
        guard !declared.isEmpty else {
            if sawUnknown {
                diagnostics.append(.init(
                    severity: .warning,
                    message: "visibleOn= named no surface Vee knows; the row stays visible everywhere"
                ))
            }
            return nil
        }
        return declared
    }
}
