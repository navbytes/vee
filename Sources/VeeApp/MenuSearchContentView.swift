import AppKit
import SwiftUI
import VeeMenu
import VeePluginFormat
import VeeSearch
import VeeUI

/// The content both of Vee's menu-surface presentations share: a focused search
/// field over a scrollable, keyboard-navigable result list with breadcrumbs.
///
/// Deliberately carries **no chrome and no size** — the transient panel wraps it
/// in a fixed-size Liquid Glass card (`MenuSearchPanel`), a detached window lets
/// it fill the window instead. Anything that differs between the two belongs to
/// the caller, not here, so the two can never drift on what a row means or how
/// one is activated. Business logic lives in the view model.
struct MenuSearchContentView: View {
    @ObservedObject var model: MenuSearchViewModel
    let pluginName: String
    let onActivate: (FlatRow) -> Void
    /// Called when an inline `toggle=`/`slider=` settles on a new value. The
    /// transient panel passes nothing — its controls open the popover on click
    /// like they always have; a detached window wires this so a control can be
    /// used without leaving the window.
    var onCommit: @MainActor (FlatRow, Double) -> Void = { _, _ in }

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(pluginName)…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .onSubmit { if let row = model.selectedRow() { onActivate(row) } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            if model.results.isEmpty {
                Spacer()
                Text("No matches").foregroundStyle(.secondary)
                Spacer()
            } else {
                resultList
            }
        }
        .onAppear { searchFocused = true }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.offset) { index, entry in
                        row(for: entry, index: index)
                            .id(index)
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selection) { _, selection in
                // `-1` (no `.action` entry in the results) has nothing to scroll to.
                guard model.results.indices.contains(selection) else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }

    /// Renders one entry by kind. Only `.action` is interactive — `.info` uses
    /// the same row view dimmed and inert, `.header`/`.separator` are plain
    /// structural furniture.
    @ViewBuilder
    private func row(for entry: SearchEntry, index: Int) -> some View {
        switch entry {
        case .action(let flatRow):
            // A row whose accessory is a live control is driven by the control
            // itself; a row-wide tap gesture would swallow the slider drag. The
            // keyboard path still activates it through the dispatcher, which is
            // what Return on a control row has always done.
            let hasLiveControl = flatRow.item.params.control != nil
            SearchRowView(
                row: flatRow,
                selected: index == model.selection,
                onCommit: { onCommit(flatRow, $0) }
            )
            .contentShape(Rectangle())
            .modifier(TapToActivate(enabled: !hasLiveControl) { onActivate(flatRow) })
        case .info(let flatRow):
            SearchRowView(row: flatRow, selected: false, enabled: false)
        case .header(let title):
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 2)
        case .separator:
            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
    }
}

/// Which base64-decoded image (if any) a search row should show, given the
/// item declares no `sfimage=` — that path renders via SwiftUI's
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

/// One result row: SF Symbol / base64 image (when the item declares one), the
/// item text, and a dim breadcrumb of its ancestor groups. `enabled: false`
/// renders an `.info` entry (a disabled item or a plain sub-text line) — same
/// layout/metrics so the list stays visually aligned, but dimmed, never
/// highlighted, and inert; the caller (not this view) is what leaves off the
/// tap gesture.
private struct SearchRowView: View {
    let row: FlatRow
    let selected: Bool
    var enabled: Bool = true
    var onCommit: @MainActor (Double) -> Void = { _ in }

    /// The graphic this row carries, if any — `progress=`, `sparkline=`, a
    /// chart, or a live control.
    private var accessory: MenuRowAccessory.Kind? { MenuRowAccessory.kind(for: row.item.params) }

    /// `accessory=leading` anchors the graphic to the row's leading edge, the
    /// same param the AppKit menu row honors.
    private var accessoryLeading: Bool { row.item.params.swiftbar.accessory == .leading }

    /// The item's text with its `color=` and ANSI runs applied, built by the
    /// same factory the native menu row uses — so styling, `length` truncation,
    /// `md=` and `symbolize=` cannot drift between the two surfaces.
    ///
    /// A selected or dimmed row drops the plugin's ink: the row is already
    /// painted (accent fill, or the secondary treatment for `.info`) and a
    /// plugin-chosen foreground on top of that is a contrast accident waiting to
    /// happen. Bold, italic, and underline runs survive either way.
    private var title: Text {
        var attributed = AttributedString(
            AttributedTitleFactory.make(
                text: row.item.text,
                params: row.item.params,
                ansiRuns: row.item.ansiRuns,
                defaultFont: .systemFont(ofSize: 13)
            )
        )
        if selected || !enabled { attributed.foregroundColor = nil }
        return Text(attributed)
    }

    var body: some View {
        HStack(spacing: 9) {
            // `.action` always shows an icon (a placeholder when the item
            // declares none); a dimmed `.info` row only shows one when the
            // item actually declares `sfimage=`/`image=`/`templateImage=` —
            // but keeps the 18pt frame either way, so text stays aligned
            // across rows.
            Group {
                if let sfimage = row.item.params.swiftbar.sfimage {
                    Image(systemName: sfimage)
                } else if let nsImage = SearchRowIcon.decodedImage(for: row.item.params) {
                    // A `templateImage=` tints with row selection like an SF
                    // Symbol; a plain `image=` keeps its own colors.
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(nsImage.isTemplate ? .template : .original)
                        .aspectRatio(contentMode: .fit)
                } else if enabled {
                    Image(systemName: "circle.dashed")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: 18, height: 18)
            if let accessory, accessoryLeading {
                MenuRowAccessory(kind: accessory, leading: true, onCommit: onCommit)
            }
            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(enabled ? (selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)) : AnyShapeStyle(.secondary))
                if !row.breadcrumb.isEmpty {
                    Text(row.breadcrumb)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let accessory, !accessoryLeading {
                MenuRowAccessory(kind: accessory, onCommit: onCommit)
            }
            // Surface the plugin's own "currently selected" marker (`checked=true`)
            // so an active choice (e.g. the current context) is visible in the panel.
            if row.item.params.swiftbar.checked == true {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(enabled && selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
        )
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
