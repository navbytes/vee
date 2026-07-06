import SwiftUI
import VeeTrust

/// The trust gate shown before installing a catalog plugin: plain-language
/// statements of what it can do, plus warnings (including undeclared
/// capabilities detected in the source). Advisory — the user decides.
public struct InstallTrustSheet: View {
    private let prompt: InstallPrompt
    private let onCancel: () -> Void
    private let onInstall: () -> Void

    public init(prompt: InstallPrompt, onCancel: @escaping () -> Void, onInstall: @escaping () -> Void) {
        self.prompt = prompt
        self.onCancel = onCancel
        self.onInstall = onInstall
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let description = prompt.description, !description.isEmpty {
                        Text(description).font(.callout).foregroundStyle(.secondary)
                    }

                    capabilitiesSection

                    trustDiffSection

                    if !prompt.dependencies.isEmpty {
                        callout(
                            symbol: "shippingbox.fill",
                            tint: .orange,
                            title: "Requires other tools",
                            body: prompt.dependencies.joined(separator: ", ")
                        )
                    }

                    if !prompt.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(prompt.warnings, id: \.self) { warning in
                                callout(symbol: "exclamationmark.triangle.fill", tint: .yellow, title: nil, body: warning)
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 480, height: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            PluginTile(symbol: CategoryStyle.symbol(for: prompt.entry.category),
                       tint: CategoryStyle.tint(for: prompt.entry.category), size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(prompt.title).font(.title3).fontWeight(.semibold)
                Text("\(prompt.entry.filename) · \(prompt.entry.category)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("from matryer/xbar-plugins")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            TrustChip(symbol: prompt.summary.level.symbol, label: prompt.summary.level.label, tint: prompt.summary.level.color)
        }
        .padding(20)
    }

    @ViewBuilder
    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What this plugin can do")
                .font(.subheadline).fontWeight(.semibold)

            if prompt.summary.badges.isEmpty {
                callout(
                    symbol: "questionmark.circle.fill",
                    tint: .yellow,
                    title: "Nothing declared",
                    body: "This plugin doesn't say what it accesses. Review its source before trusting it."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(prompt.summary.badges.enumerated()), id: \.offset) { _, badge in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: badge.capability.symbol)
                                .font(.body)
                                .foregroundStyle(badge.severity.color)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(badge.capability.plainName).font(.callout).fontWeight(.medium)
                                if !badge.detail.isEmpty {
                                    Text(badge.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    /// For an update, the change in the plugin's trust footprint since it was
    /// installed. Hidden on a fresh install and when nothing changed.
    @ViewBuilder
    private var trustDiffSection: some View {
        if let diff = prompt.trustDiff, diff.hasChanges {
            VStack(alignment: .leading, spacing: 10) {
                Text("Changes since you installed it")
                    .font(.subheadline).fontWeight(.semibold)
                callout(
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .orange,
                    title: "This update changes what the plugin can do",
                    body: diff.summaryLines.joined(separator: "\n")
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("Plugins run un-sandboxed with your privileges.", systemImage: "lock.open")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
            Button("Install") { onInstall() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    /// A tinted callout box for warnings, requirements, and the undeclared state.
    @ViewBuilder
    private func callout(symbol: String, tint: Color, title: String?, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                if let title { Text(title).font(.callout).fontWeight(.medium) }
                Text(body).font(.callout).foregroundStyle(title == nil ? .primary : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12)))
    }
}
