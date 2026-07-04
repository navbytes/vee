import SwiftUI
import VeeTrust

/// The trust gate shown before installing a catalog plugin: what it declares it
/// accesses, plus warnings (including undeclared capabilities detected in the
/// source). Advisory — the user decides.
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Install \(prompt.title)?").font(.headline)
            Text("\(prompt.entry.filename) · \(prompt.entry.category) · matryer/xbar-plugins")
                .font(.caption).foregroundStyle(.secondary)

            if let description = prompt.description, !description.isEmpty {
                Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }

            if !prompt.dependencies.isEmpty {
                Label("Requires: \(prompt.dependencies.joined(separator: ", "))", systemImage: "shippingbox")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Divider()

            Text("Declared capabilities").font(.subheadline).bold()
            if prompt.summary.badges.isEmpty {
                Label("This plugin declares nothing about what it accesses.",
                      systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(prompt.summary.badges.enumerated()), id: \.offset) { _, badge in
                    Label("\(badge.capability.rawValue): \(badge.detail)", systemImage: icon(for: badge.severity))
                        .foregroundStyle(color(for: badge.severity))
                }
            }

            if !prompt.warnings.isEmpty {
                Divider()
                Text("Warnings").font(.subheadline).bold()
                ForEach(prompt.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            Spacer()
            HStack {
                Text("Plugins run un-sandboxed with your privileges.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Install") { onInstall() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 340)
    }

    private func icon(for severity: Severity) -> String {
        switch severity {
        case .high: return "exclamationmark.octagon"
        case .medium: return "exclamationmark.circle"
        case .low: return "checkmark.circle"
        }
    }

    private func color(for severity: Severity) -> Color {
        switch severity {
        case .high: return .red
        case .medium: return .orange
        case .low: return .secondary
        }
    }
}
