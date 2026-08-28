import AppKit
import SwiftUI
import VeeMenu
import VeePluginFormat
import VeeSearch
import VeeUI

/// The content both of Vee's menu-surface presentations share: a focused filter
/// field over the plugin's menu, drawn as the structure the plugin authored —
/// nested rows that open and close in place.
///
/// Deliberately carries **no chrome and no size** — the transient panel wraps it
/// in a fixed-size Liquid Glass card (`MenuSearchPanel`), a detached window lets
/// it fill the window instead. Anything that differs between the two belongs to
/// the caller, not here, so the two can never drift on what a row means or how
/// one is activated. Business logic lives in the view model.
///
/// Nesting is presented inline rather than as a flyout: this surface exists to
/// be left open and watched, and inline disclosure is the only presentation
/// whose premise is several branches visible at once. The menu bar keeps its
/// native flyouts — both read the same `MenuTree`, so they differ in how they
/// unfold, never in what they contain.
struct MenuSearchContentView: View {
    @ObservedObject var model: MenuSearchViewModel
    let pluginName: String
    let onActivate: (MenuRowSpec) -> Void
    /// Called when an inline `toggle=`/`slider=` settles on a new value. The
    /// transient panel passes nothing — its controls open the popover on click
    /// like they always have; a detached window wires this so a control can be
    /// used without leaving the window.
    var onCommit: @MainActor (MenuRowSpec, Double) -> Void = { _, _ in }

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(pluginName)…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .onSubmit { activateSelection() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            if model.visible.isEmpty {
                Spacer()
                Text("No matches").foregroundStyle(.secondary)
                Spacer()
            } else {
                rowList
            }
        }
        .onAppear { searchFocused = true }
        // `⌘F` returns focus to the field from anywhere in the surface. The
        // menu bar cannot offer this — an `NSMenu` has nowhere to put a text
        // field — which is why its `⌘F` still opens this surface instead.
        .background(FocusFilterShortcut { searchFocused = true })
    }

    /// Runs whatever Return means for the highlighted line: fire an actionable
    /// row, or open/close a parent. A parent that also declares a command is
    /// inert by the shared rule, so this can never run a command the dropdown
    /// would not have run.
    private func activateSelection() {
        guard let row = model.selectedVisibleRow() else { return }
        if row.spec.isActionable {
            onActivate(row.spec)
        } else if row.canExpand {
            model.toggle(row.key)
        }
    }

    private var rowList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.visible.enumerated()), id: \.offset) { index, node in
                        line(for: node, index: index)
                            .id(index)
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selection) { _, selection in
                // `-1` (no selectable line) has nothing to scroll to.
                guard model.visible.indices.contains(selection) else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }

    /// Renders one line by kind. Only rows are interactive — a header is a plain
    /// section title and a separator is a divider, both structural furniture the
    /// plugin authored and neither selectable.
    @ViewBuilder
    private func line(for node: VisibleNode, index: Int) -> some View {
        switch node {
        case .row(let row):
            // A row whose accessory is a live control is driven by the control
            // itself; a row-wide tap gesture would swallow the slider drag. The
            // keyboard path still activates it, which is what Return on a
            // control row has always done.
            let hasLiveControl = row.spec.control != nil
            MenuRowView(
                row: row,
                selected: index == model.selection,
                onToggleBranch: { model.toggle(row.key) },
                onCommit: { onCommit(row.spec, $0) }
            )
            .contentShape(Rectangle())
            .modifier(TapToActivate(enabled: !hasLiveControl) {
                model.selection = index
                if row.spec.isActionable {
                    onActivate(row.spec)
                } else if row.canExpand {
                    model.toggle(row.key)
                }
            })
        case .header(let title, let depth):
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, MenuRowView.indent(for: depth) + 10)
                .padding(.trailing, 10)
                .padding(.top, 10)
                .padding(.bottom, 2)
        case .separator(let depth):
            Divider()
                .padding(.leading, MenuRowView.indent(for: depth) + 10)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
        }
    }
}

/// Which base64-decoded image (if any) a row should show, given the item
/// declares no `sfimage=` — that path renders via SwiftUI's
/// `Image(systemName:)` directly instead (crisper SF Symbol scaling at the
/// row's font size), so this only ever resolves the `image=`/
/// `templateImage=` fallback. Decodes through `SymbolImageFactory` — the
/// same cached path `MenuBuilder`'s native rows use — so a plugin's custom
/// icon shows here too instead of the generic placeholder. `nil` means no
/// declared icon at all; the caller falls back to a placeholder.
enum SearchRowIcon {
    static func decodedImage(for params: LineParams) -> NSImage? {
        guard params.swiftbar.sfimage == nil else { return nil }
        return SymbolImageFactory.image(for: params)
    }
}

/// One line of the menu: a disclosure chevron when the row has children, the
/// declared icon, the item text, and whatever graphic or control the row
/// carries. Indented by depth, so position in the structure is what says where
/// a row sits — there is no textual breadcrumb, because its ancestors are on
/// screen above it.
private struct MenuRowView: View {
    let row: VisibleRow
    let selected: Bool
    var onToggleBranch: () -> Void = {}
    var onCommit: @MainActor (Double) -> Void = { _ in }

    private var spec: MenuRowSpec { row.spec }

    /// A row that neither acts nor opens is inert: a plain sub-text line or a
    /// disabled item. Same layout and metrics so the list stays aligned, but
    /// dimmed and never highlighted.
    private var enabled: Bool { spec.isActionable || row.canExpand }

    /// One indentation step per nesting level.
    static func indent(for depth: Int) -> CGFloat { CGFloat(depth) * 14 }

    /// `accessory=leading` anchors the graphic to the row's leading edge, the
    /// same param the AppKit menu row honors.
    private var accessoryLeading: Bool { spec.accessoryLeading }

    /// Whether the row has a label at all. A graphic-only row draws no title
    /// view — not even an empty one — so it costs no gap.
    private var hasTitle: Bool { !spec.item.text.isEmpty }

    /// What this row draws inline. A live control wins here because a window
    /// can host one; the dropdown draws the display graphic instead and opens
    /// the control on click. Both read the same resolved row.
    private var accessory: MenuRowAccessory.Kind? {
        if let control = spec.control { return .control(control, width: spec.controlWidth) }
        return spec.accessory.map(MenuRowAccessory.Kind.display)
    }

    /// The item's text with its `color=` and ANSI runs applied, built by the
    /// same factory the native menu row uses — so styling, `length` truncation,
    /// `md=` and `symbolize=` cannot drift between the two surfaces.
    ///
    /// A selected or dimmed row drops the plugin's ink: the row is already
    /// painted (accent fill, or the secondary treatment for an inert row) and a
    /// plugin-chosen foreground on top of that is a contrast accident waiting to
    /// happen. Bold, italic, and underline runs survive either way.
    private var title: Text {
        var attributed = AttributedString(
            AttributedTitleFactory.make(
                text: spec.item.text,
                params: spec.item.params,
                ansiRuns: spec.item.ansiRuns,
                defaultFont: .systemFont(ofSize: 13)
            )
        )
        if selected || !enabled { attributed.foregroundColor = nil }
        return Text(attributed)
    }

    var body: some View {
        // Gaps hang off the pieces rather than off the stack, because a stack's
        // uniform `spacing:` is paid even by a piece with no width — a bar-only
        // row (`" | progress=… progressw=full"`, the shape a plugin uses for a
        // hero gauge) has a zero-width title, and the 9pt on each side of it
        // pushed the bar 18pt inboard of the text rows above and below it. The
        // dropdown reserves its gap the same way: only when the label has width
        // (`ProgressBarLayout.stretchedWidth`).
        HStack(spacing: 0) {
            chevron
            icon
            if let accessory, accessoryLeading {
                MenuRowAccessory(kind: accessory, leading: true, onCommit: onCommit)
                    .padding(.trailing, hasTitle ? 9 : 0)
            }
            if hasTitle {
                title
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(enabled ? (selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 0)
            if let accessory, !accessoryLeading {
                MenuRowAccessory(kind: accessory, onCommit: onCommit)
                    .padding(.leading, hasTitle ? 9 : 0)
            }
            // Surface the plugin's own "currently selected" marker (`checked=true`)
            // so an active choice (e.g. the current context) is visible here.
            if spec.isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
                    .padding(.leading, 9)
            }
        }
        .padding(.leading, MenuRowView.indent(for: row.depth) + 10)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .help(spec.tooltip ?? "")
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(enabled && selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
        )
    }

    /// The disclosure control, drawn only on a row that has children.
    ///
    /// No blank gutter for the rest: reserving one because *some* row in the
    /// list can expand pushes every line of a mostly-flat menu inboard, which
    /// is the one thing the dropdown never does. Depth is already carried by
    /// `indent(for:)`, so the column bought alignment and nothing else.
    @ViewBuilder
    private var chevron: some View {
        if row.canExpand {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 10)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleBranch)
                .accessibilityLabel(row.isExpanded ? "Collapse" : "Expand")
                .padding(.trailing, 9)
        }
    }

    /// The row's declared icon, and nothing at all when the row declares none.
    ///
    /// Same rule as the chevron, and the same rule the `NSMenu` rows follow: an
    /// `sfimage=`/`image=`/`templateImage=` hangs to the left of its own text,
    /// it does not open an 18pt column every other row then has to pay for.
    @ViewBuilder
    private var icon: some View {
        if let sfimage = spec.item.params.swiftbar.sfimage {
            Image(systemName: sfimage)
                .font(.system(size: 13))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 18)
                .padding(.trailing, 9)
        } else if let nsImage = SearchRowIcon.decodedImage(for: spec.item.params) {
            // A `templateImage=` tints with row selection like an SF Symbol;
            // a plain `image=` keeps its own colors.
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(nsImage.isTemplate ? .template : .original)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 18)
                .padding(.trailing, 9)
        }
    }
}

/// Attaches a tap gesture only when `enabled`. A `.onTapGesture` applied
/// unconditionally and then ignored still consumes the event, which is exactly
/// what must not happen over a live slider.
private struct TapToActivate: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

/// A zero-size `⌘F` sink. SwiftUI has no "focus this field" command, so this
/// hangs an invisible keyboard shortcut off the surface and calls back.
private struct FocusFilterShortcut: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Color.clear }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
