import SwiftUI

/// Backing model for the per-plugin debug console. The coordinator updates it
/// after each run; "Run again" triggers a fresh run through `onRerun`.
@MainActor
public final class PluginDebugModel: ObservableObject {
    public let pluginName: String
    @Published public var stdout: String = ""
    @Published public var stderr: String = ""
    @Published public var exitCode: Int32 = 0
    @Published public var timedOut: Bool = false
    @Published public var diagnostics: [String] = []

    private let onRerun: () -> Void

    public init(pluginName: String, onRerun: @escaping () -> Void) {
        self.pluginName = pluginName
        self.onRerun = onRerun
    }

    public func rerun() { onRerun() }

    public func update(stdout: String, stderr: String, exitCode: Int32, timedOut: Bool, diagnostics: [String]) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.diagnostics = diagnostics
    }
}

/// A developer view of a plugin's last run: exit status, parse diagnostics, and
/// raw stdout/stderr — answering "why didn't my plugin work?". The console body
/// only, with **no** fixed frame, so the caller sizes it: the standalone window
/// pins it to 580×540; the in-pane Debug tab lets it fill the pane.
public struct PluginDebugContent: View {
    @ObservedObject private var model: PluginDebugModel

    public init(model: PluginDebugModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                statusLabel
                Spacer()
                Button {
                    model.rerun()
                } label: {
                    Label("Run again", systemImage: "arrow.clockwise")
                }
            }

            if !model.diagnostics.isEmpty {
                section("Parse diagnostics") {
                    ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, line in
                        Text(line).foregroundStyle(.orange)
                    }
                }
            }

            section("Standard output") {
                Text(model.stdout.isEmpty ? "(empty)" : model.stdout)
                    .foregroundStyle(model.stdout.isEmpty ? .secondary : .primary)
            }

            section("Standard error") {
                Text(model.stderr.isEmpty ? "(empty)" : model.stderr)
                    .foregroundStyle(model.stderr.isEmpty ? .secondary : .primary)
            }
        }
        .padding(16)
    }

    @ViewBuilder private var statusLabel: some View {
        if model.timedOut {
            Label("Timed out", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
        } else if model.exitCode == 0 {
            Label("Exit 0", systemImage: "checkmark.circle").foregroundStyle(.green)
        } else {
            Label("Exit \(model.exitCode)", systemImage: "xmark.octagon").foregroundStyle(.red)
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .padding(8)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Corner.surface, style: .continuous).fill(.background.secondary))
        }
    }
}

/// The plugin debug console in its own resizable window (status-item "Debug…"
/// menu and the notification "Open Log" action). Wraps `PluginDebugContent` in
/// the fixed 580×540 frame it had before, so the window is unchanged. The
/// in-pane Debug tab uses `PluginDebugContent` directly, sized to fill the pane.
public struct PluginDebugView: View {
    private let model: PluginDebugModel

    public init(model: PluginDebugModel) {
        self.model = model
    }

    public var body: some View {
        PluginDebugContent(model: model)
            .frame(width: 580, height: 540, alignment: .topLeading)
    }
}
