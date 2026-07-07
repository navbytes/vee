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

    /// Whether the plugin declares a global hotkey the user can control.
    public let hotkeyControllable: Bool
    @Published public var hotkeyEnabled: Bool
    @Published public var hotkeyCombo: String
    @Published public var hotkeyStatus: HotkeyStatus

    private let prefs: PluginPreferences
    private let onSaved: () -> Void
    private let onApplyHotkey: (Bool, String) -> HotkeyStatus

    public init(
        pluginName: String,
        prefs: PluginPreferences,
        features: PluginFeatures = PluginFeatures(),
        hotkeyControllable: Bool = false,
        hotkeyEnabled: Bool = true,
        hotkeyCombo: String = "",
        hotkeyStatus: HotkeyStatus = .none,
        onApplyHotkey: @escaping (Bool, String) -> HotkeyStatus = { _, _ in .none },
        onSaved: @escaping () -> Void
    ) {
        self.pluginName = pluginName
        self.prefs = prefs
        self.declarations = prefs.declarations
        self.features = features
        self.hotkeyControllable = hotkeyControllable
        self.hotkeyEnabled = hotkeyEnabled
        self.hotkeyCombo = hotkeyCombo
        self.hotkeyStatus = hotkeyStatus
        self.onApplyHotkey = onApplyHotkey
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

    /// Applies the current hotkey enable/combo state immediately (a hotkey is a
    /// live system resource, so it commits on change rather than on Save) and
    /// reflects the resulting status.
    func applyHotkey() {
        hotkeyStatus = onApplyHotkey(hotkeyEnabled, hotkeyCombo)
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
                                if model.features.searchPanel {
                                    featureRow(
                                        symbol: "magnifyingglass",
                                        title: "Searchable menu",
                                        detail: "Filter this plugin's items from a search panel (⌘F)."
                                    )
                                }
                                if model.hotkeyControllable {
                                    hotkeyControl
                                }
                            }
                        }
                        if !model.declarations.isEmpty {
                            Section {
                                ForEach(model.declarations, id: \.name) { declaration in
                                    row(for: declaration)
                                }
                            } footer: {
                                Text("Secret values are masked and stored in your macOS Keychain. Saving refreshes \(model.pluginName).")
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

    @ViewBuilder
    private func featureRow(symbol: String, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }

    /// The interactive global-hotkey control: enable/disable, rebind by typing a
    /// combination, and a live status line (active / already-in-use / invalid).
    @ViewBuilder
    private var hotkeyControl: some View {
        Toggle(isOn: $model.hotkeyEnabled) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global hotkey")
                    Text("Opens the search panel from anywhere.").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "keyboard")
            }
        }
        .onChange(of: model.hotkeyEnabled) { _, _ in model.applyHotkey() }

        if model.hotkeyEnabled {
            TextField("Shortcut", text: $model.hotkeyCombo, prompt: Text("e.g. cmd+shift+k"))
                .onSubmit { model.applyHotkey() }
            hotkeyStatusLabel
        }
    }

    @ViewBuilder
    private var hotkeyStatusLabel: some View {
        switch model.hotkeyStatus {
        case .active(let display):
            Label("Active — \(display)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .unavailable(let display):
            Label("\(display) is already in use — try another", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .invalid:
            Label("Not a valid shortcut", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
        case .disabled, .none:
            EmptyView()
        }
    }
}
