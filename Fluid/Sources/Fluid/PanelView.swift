#if os(macOS)
import AppKit
import SwiftUI
import FluidProtocol

/// The popover a plugin's panel tree is drawn in, with a footer for the
/// plugin's state and the host's own controls.
struct PanelView: View {
    let controller: PluginController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(maxHeight: 520)
            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 360)
    }

    @ViewBuilder private var content: some View {
        if let problem = controller.problem {
            Text("\(controller.name) could not start").font(.headline)
            Text(problem)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        } else if let panel = controller.panel {
            NodeView(node: panel, send: controller.send)
        } else if controller.state == .starting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting \(controller.name)…").foregroundStyle(.secondary)
            }
        } else {
            Text("\(controller.name) has no panel.").foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(stateColor).frame(width: 8, height: 8)
            Text(controller.name).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                controller.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            Menu {
                Button("Restart Plugin") { controller.restart() }
                Button("Copy Recent Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.logs.joined(separator: "\n"), forType: .string)
                }
                Divider()
                Button("Quit Fluid") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var stateColor: Color {
        switch controller.state {
        case .running: return .green
        case .starting, .restarting: return .orange
        case .failed: return .red
        case .stopped: return .gray
        }
    }
}

/// Draws one `ViewNode`. Every case of the vocabulary is handled here; the
/// switch has no `default`, so a new node type will not compile until the
/// panel knows how to draw it.
struct NodeView: View {
    let node: ViewNode
    let send: (ActionID, EventValue?) -> Void

    var body: some View {
        switch node {
        case .text(let string, let style, let role):
            Text(string).font(style.font).foregroundStyle(role.color)
        case .label(let title, let symbol, let role):
            Label(title, systemImage: symbol).foregroundStyle(role.color)
        case .stack(.vertical, let spacing, let children):
            VStack(alignment: .leading, spacing: spacing.map { CGFloat($0) }) { nodes(children) }
        case .stack(.horizontal, let spacing, let children):
            HStack(spacing: spacing.map { CGFloat($0) }) { nodes(children) }
        case .list(let searchable, let children):
            ListNodeView(searchable: searchable, children: children, send: send)
        case .section(let title, let children):
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
                }
                nodes(children)
            }
        case .row(let row):
            RowView(row: row, send: send)
        case .badge(let text, let role):
            BadgeView(text: text, role: role)
        case .button(let title, let symbol, let role, let action):
            Button(role: role == .critical ? .destructive : nil) {
                send(action, nil)
            } label: {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .tint(role.color)
        case .toggle(let title, let isOn, let action):
            Toggle(title, isOn: Binding(get: { isOn }, set: { send(action, .bool($0)) }))
        case .progress(let value, let total, let label, let role):
            ProgressView(value: min(max(value, 0), total), total: max(total, .leastNonzeroMagnitude)) {
                if let label { Text(label).font(.caption) }
            }
            .tint(role.color)
        case .divider:
            Divider()
        }
    }

    private func nodes(_ children: [ViewNode]) -> some View {
        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
            NodeView(node: child, send: send)
        }
    }
}

/// A list, with the optional filter field `searchable` asks for. Filtering is
/// done here, by the host, so it works the same for every plugin.
struct ListNodeView: View {
    let searchable: Bool
    let children: [ViewNode]
    let send: (ActionID, EventValue?) -> Void
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if searchable {
                TextField("Filter", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.bottom, 4)
            }
            ForEach(Array(visible.enumerated()), id: \.offset) { _, child in
                NodeView(node: child, send: send)
            }
            if visible.isEmpty && !query.isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            }
        }
    }

    private var visible: [ViewNode] {
        guard !query.isEmpty else { return children }
        return children.filter { child in
            child.rows.contains { row in
                row.title.localizedCaseInsensitiveContains(query) || (row.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
    }
}

struct RowView: View {
    let row: RowNode
    let send: (ActionID, EventValue?) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = row.symbol {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).lineLimit(2)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ForEach(Array(row.accessories.enumerated()), id: \.offset) { _, accessory in
                accessoryView(accessory)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering && !row.actions.isEmpty ? Color.primary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let primary = row.actions.first { send(primary.id, nil) }
        }
        .contextMenu {
            ForEach(row.actions, id: \.id) { action in
                Button(action.title, role: action.role == .critical ? .destructive : nil) { send(action.id, nil) }
            }
        }
        .help(row.actions.first?.title ?? "")
    }

    @ViewBuilder private func accessoryView(_ node: ViewNode) -> some View {
        if case .progress(let value, let total, _, let role) = node {
            ProgressView(value: min(max(value, 0), total), total: max(total, .leastNonzeroMagnitude))
                .tint(role.color)
                .frame(width: 64)
        } else {
            NodeView(node: node, send: send)
        }
    }
}

struct BadgeView: View {
    let text: String
    let role: Role

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(role.color)
            .background(Capsule().fill(role.color.opacity(0.15)))
    }
}

extension Role {
    var color: Color {
        switch self {
        case .primary: return .primary
        case .secondary: return .secondary
        case .accent: return .accentColor
        case .success: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

extension TextStyle {
    var font: Font {
        switch self {
        case .title: return .title2.weight(.semibold)
        case .headline: return .headline
        case .body: return .body
        case .caption: return .caption
        case .monospaced: return .system(.body, design: .monospaced)
        }
    }
}
#endif
