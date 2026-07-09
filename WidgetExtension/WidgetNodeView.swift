import WidgetKit
import SwiftUI
import VeeWidgetShared

/// Walks a `WidgetCard.layout` tree into native SwiftUI — the renderer half of
/// the layout-tree escape hatch (see `docs/design/widget-surface-contract.md`
/// §"Layout tree"). Each node maps to one primitive; the tree is already
/// sanitized and capped app-side by `WidgetCardParser` (depth ≤ 8, ≤ 64 nodes,
/// numerics clamped), so the walk here is a plain, bounded render with no
/// validation of its own. `AnyView` recursion is fine at this scale — a card
/// is at most 64 nodes.
///
/// Compile-only, like the rest of `WidgetExtension` (not an SPM target): the
/// pure schema/parser layers in `VeeWidgetShared`/`VeePluginFormat` carry the
/// test coverage; this view is exercised by the built widget.
struct WidgetNodeView: View {
    @Environment(\.widgetFamily) private var family
    let node: WidgetNode

    var body: some View {
        LayoutNodeRenderer.render(node, family: family)
    }
}

enum LayoutNodeRenderer {
    static func render(_ node: WidgetNode, family: WidgetFamily) -> AnyView {
        guard included(node, family: family) else { return AnyView(EmptyView()) }

        switch node.type {
        case "vstack":
            return wrap(VStack(alignment: verticalStackAlignment(node.align), spacing: spacing(node)) {
                childViews(node, family: family)
            }, node)
        case "hstack":
            return wrap(HStack(alignment: horizontalStackAlignment(node.align), spacing: spacing(node)) {
                childViews(node, family: family)
            }, node)
        case "zstack":
            return wrap(ZStack(alignment: zStackAlignment(node.align)) {
                childViews(node, family: family)
            }, node)
        case "grid":
            let count = max(1, node.columns ?? 2)
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing(node)), count: count)
            return wrap(LazyVGrid(columns: columns, alignment: .leading, spacing: spacing(node)) {
                childViews(node, family: family)
            }, node)
        case "text":
            return wrap(textView(node), node)
        case "image":
            return wrap(imageView(node), node)
        case "gauge":
            return wrap(gaugeView(node), node)
        case "sparkline":
            return wrap(sparklineView(node), node)
        case "spacer":
            return AnyView(Spacer(minLength: node.minLength.map { CGFloat($0) }))
        case "divider":
            return AnyView(Divider())
        default:
            // Unknown type: the parser already emitted a diagnostic; render
            // nothing rather than guess.
            return AnyView(EmptyView())
        }
    }

    // MARK: - Family filtering

    private static func included(_ node: WidgetNode, family: WidgetFamily) -> Bool {
        guard let families = node.families, !families.isEmpty else { return true }
        return families.contains(familyToken(family))
    }

    private static func familyToken(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "small"
        case .systemLarge, .systemExtraLarge: return "large"
        default: return "medium"
        }
    }

    // MARK: - Containers

    @ViewBuilder
    private static func childViews(_ node: WidgetNode, family: WidgetFamily) -> some View {
        let children = node.children ?? []
        ForEach(children.indices, id: \.self) { index in
            render(children[index], family: family)
        }
    }

    private static func spacing(_ node: WidgetNode) -> CGFloat? {
        node.spacing.map { CGFloat($0) }
    }

    // MARK: - Leaves

    private static func textView(_ node: WidgetNode) -> some View {
        let style = node.style
        var text = Text(node.text ?? "").font(font(style?.font))
        if style?.monospacedDigit == true { text = text.monospacedDigit() }
        return text
            .foregroundStyle(color(style?.tint) ?? .primary)
            .multilineTextAlignment(textAlignment(style?.align))
            .lineLimit(style?.lineLimit)
            .minimumScaleFactor(style?.minScale.map { CGFloat($0) } ?? 1)
    }

    private static func imageView(_ node: WidgetNode) -> some View {
        Image(systemName: node.symbol ?? "questionmark")
            .font(font(node.style?.font))
            .foregroundStyle(color(node.style?.tint) ?? .primary)
    }

    @ViewBuilder
    private static func gaugeView(_ node: WidgetNode) -> some View {
        let gauge = Gauge(value: node.value ?? 0) { EmptyView() }
            .tint(color(node.style?.tint) ?? .accentColor)
        if node.gaugeStyle == "circular" {
            gauge.gaugeStyle(.accessoryCircularCapacity)
        } else {
            gauge.gaugeStyle(.accessoryLinearCapacity)
        }
    }

    private static func sparklineView(_ node: WidgetNode) -> some View {
        Sparkline(values: node.values ?? [])
            .stroke(color(node.style?.tint) ?? .primary,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(height: 24)
    }

    // MARK: - Common wrapping (padding + fill)

    private static func wrap(_ view: some View, _ node: WidgetNode) -> AnyView {
        var erased = AnyView(view)
        if let padding = node.style?.padding {
            erased = AnyView(erased.padding(CGFloat(padding)))
        }
        if node.style?.fill == true {
            erased = AnyView(erased.frame(maxWidth: .infinity))
        }
        return erased
    }

    // MARK: - Style mapping

    private static func color(_ tint: SnapshotColor?) -> Color? {
        tint?.swiftUIColor
    }

    private static func font(_ f: WidgetNodeFont?) -> Font {
        guard let f else { return .body }
        let design = fontDesign(f.design)
        var font: Font = f.pointSize.map { Font.system(size: CGFloat($0), design: design) }
            ?? .system(textStyle(f.size), design: design)
        if let weight = f.weight { font = font.weight(fontWeight(weight)) }
        return font
    }

    private static func textStyle(_ s: String?) -> Font.TextStyle {
        switch s {
        case "caption2": return .caption2
        case "caption": return .caption
        case "footnote": return .footnote
        case "subheadline": return .subheadline
        case "headline": return .headline
        case "title3": return .title3
        case "title2": return .title2
        case "title": return .title
        case "largeTitle": return .largeTitle
        default: return .body
        }
    }

    private static func fontWeight(_ w: String) -> Font.Weight {
        switch w {
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .regular
        }
    }

    private static func fontDesign(_ d: String?) -> Font.Design {
        switch d {
        case "rounded": return .rounded
        case "monospaced": return .monospaced
        case "serif": return .serif
        default: return .default
        }
    }

    private static func textAlignment(_ a: String?) -> TextAlignment {
        switch a {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }

    private static func verticalStackAlignment(_ a: String?) -> HorizontalAlignment {
        switch a {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }

    private static func horizontalStackAlignment(_ a: String?) -> VerticalAlignment {
        switch a {
        case "top": return .top
        case "bottom": return .bottom
        default: return .center
        }
    }

    private static func zStackAlignment(_ a: String?) -> Alignment {
        switch a {
        case "topLeading": return .topLeading
        case "top": return .top
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }
}
