import SwiftUI
import VeePluginFormat
import VeePreferences

/// View model for a plugin's auto-generated settings form.
@MainActor
public final class PluginSettingsModel: ObservableObject {
    public let pluginName: String
    public let declarations: [VarDeclaration]
    public let features: PluginFeatures
    @Published public var values: [String: String]

    private let prefs: PluginPreferences
    private let onSaved: () -> Void

    public init(pluginName: String, prefs: PluginPreferences, features: PluginFeatures = PluginFeatures(), onSaved: @escaping () -> Void) {
        self.pluginName = pluginName
        self.prefs = prefs
        self.declarations = prefs.declarations
        self.features = features
        self.onSaved = onSaved
        var initial: [String: String] = [:]
        for declaration in prefs.declarations {
            initial[declaration.name] = prefs.value(for: declaration)
        }
        self.values = initial
    }

    func stringBinding(_ declaration: VarDeclaration) -> Binding<String> {
        Binding(
            get: { self.values[declaration.name] ?? "" },
            set: { self.values[declaration.name] = $0 }
        )
    }

    func boolBinding(_ declaration: VarDeclaration) -> Binding<Bool> {
        Binding(
            get: { (self.values[declaration.name] ?? "false") == "true" },
            set: { self.values[declaration.name] = $0 ? "true" : "false" }
        )
    }

    public func save() {
        for declaration in declarations {
            try? prefs.setValue(values[declaration.name] ?? declaration.defaultValue, for: declaration)
        }
        onSaved()
    }
}

/// An auto-generated settings form: one control per declared `<xbar.var>`.
public struct PluginSettingsView: View {
    @ObservedObject private var model: PluginSettingsModel
    private let onClose: () -> Void

    public init(model: PluginSettingsModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.declarations.isEmpty && model.features.isEmpty {
                    ContentUnavailableView(
                        "No preferences",
                        systemImage: "slider.horizontal.3",
                        description: Text("This plugin has no configurable settings.")
                    )
                } else {
                    Form {
                        if !model.features.isEmpty {
                            Section("Features") {
                                ForEach(model.features.items, id: \.title) { item in
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: item.symbol)
                                    }
                                }
                            }
                        }
                        if !model.declarations.isEmpty {
                            Section {
                                ForEach(model.declarations, id: \.name) { declaration in
                                    row(for: declaration)
                                }
                            } footer: {
                                Text("Saved for \(model.pluginName). Secret values are masked.")
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle("\(model.pluginName) Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.save(); onClose() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.declarations.isEmpty)
                }
            }
        }
        .frame(width: 460, height: 420)
    }

    private func row(for declaration: VarDeclaration) -> some View {
        VarDeclarationField(
            declaration: declaration,
            stringValue: model.stringBinding(declaration),
            boolValue: model.boolBinding(declaration)
        )
    }
}
