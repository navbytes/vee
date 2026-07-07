import SwiftUI
import VeePluginFormat
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

                    sandboxCallout

                    capabilitiesSection

                    featuresSection

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
                Text("from \(prompt.storeName)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            TrustChip(symbol: prompt.summary.level.symbol, label: prompt.summary.level.label, tint: prompt.summary.level.color)
        }
        .padding(20)
    }

    /// The un-sandboxed reality, hoisted above the capability list so it is the
    /// first thing read — not buried in muted footer text. This is the single
    /// most important fact at install time.
    private var sandboxCallout: some View {
        callout(
            symbol: "lock.open.fill",
            tint: .orange,
            title: "Runs with your full access — not sandboxed",
            body: "Like any script you run in Terminal, this plugin can reach your files, "
                + "network, and credentials with your privileges. Only install plugins you trust."
        )
    }

    @ViewBuilder
    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What this plugin can do")
                .font(.subheadline).fontWeight(.semibold)

            if prompt.summary.badges.isEmpty {
                callout(
                    symbol: "questionmark.circle.fill",
                    tint: .orange,
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
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(badge.capability.plainName).font(.callout).fontWeight(.medium)
                                if !badge.detail.isEmpty {
                                    Text(badge.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            // Severity as a word, not colour alone — legible to
                            // colour-blind users and to VoiceOver.
                            TrustChip(symbol: badge.severity.symbol,
                                      label: badge.severity.word,
                                      tint: badge.severity.color)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// The Vee-native features the plugin opts into (searchable menu, global
    /// hotkey). Hidden when it declares none. A global hotkey grabs a system-wide
    /// key, so it's disclosed here before install.
    @ViewBuilder
    private var featuresSection: some View {
        if !prompt.features.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Features it adds")
                    .font(.subheadline).fontWeight(.semibold)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(prompt.features.items.enumerated()), id: \.offset) { _, feature in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: feature.symbol)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).font(.callout).fontWeight(.medium)
                                Text(feature.detail).font(.caption).foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(diff.changes.enumerated()), id: \.offset) { _, change in
                        trustChangeRow(change)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Corner.callout, style: .continuous)
                        .fill(Color.orange.opacity(0.10))
                )
            }
        }
    }

    /// One line of the update trust-diff. Additions are tinted (red when they
    /// widen the plugin's reach, orange otherwise); removals are muted green —
    /// so a risky change reads differently from a benign one at a glance.
    @ViewBuilder
    private func trustChangeRow(_ change: TrustChange) -> some View {
        let added = change.direction == .added
        let tint: Color = added ? (change.isElevated ? .red : .orange) : .green
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: added ? "plus.circle.fill" : "minus.circle.fill")
                .font(.caption)
                .foregroundStyle(added ? tint : .secondary)
                .accessibilityHidden(true)
            Text("\(added ? "Adds" : "Removes") \(change.noun):")
                .font(.callout).foregroundStyle(.secondary)
            Text(change.item)
                .font(.callout.weight(.medium))
                .foregroundStyle(added ? Color.primary : Color.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("Advisory only — Vee doesn't restrict what a plugin can do.", systemImage: "info.circle")
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
        .background(RoundedRectangle(cornerRadius: Corner.callout, style: .continuous).fill(tint.opacity(0.12)))
    }
}
