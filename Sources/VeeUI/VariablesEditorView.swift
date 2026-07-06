import SwiftUI
import VeeCore
import VeePluginFormat
import VeePreferences

/// One editable control for a declared `<xbar.var>`, shared by the per-plugin
/// settings form and the app-wide Variables editor so the rendering is defined
/// once. Secret fields are masked via `RevealableSecureField`.
public struct VarDeclarationField: View {
    private let declaration: VarDeclaration
    @Binding private var stringValue: String
    @Binding private var boolValue: Bool

    public init(declaration: VarDeclaration, stringValue: Binding<String>, boolValue: Binding<Bool>) {
        self.declaration = declaration
        self._stringValue = stringValue
        self._boolValue = boolValue
    }

    @ViewBuilder
    public var body: some View {
        let label = declaration.summary.isEmpty ? declaration.name : declaration.summary
        switch declaration.kind {
        case .boolean:
            Toggle(label, isOn: $boolValue)
        case .select:
            Picker(label, selection: $stringValue) {
                ForEach(declaration.options, id: \.self) { Text($0).tag($0) }
            }
        case .string, .number:
            if declaration.isSecret {
                LabeledContent(label) {
                    RevealableSecureField("Required", text: $stringValue)
                        .frame(maxWidth: 200)
                }
            } else {
                TextField(label, text: $stringValue)
            }
        }
    }
}

/// View model for the app-wide Variables editor. It takes the pure aggregated
/// groups (`PluginVariableGroup`) and, per plugin, builds a `PluginPreferences`
/// that reads/writes values — non-secret vars to the `.vars.json` sidecar and
/// secret vars to the Keychain (both via existing storage). Editing is buffered
/// in `values` and flushed on `save()`.
@MainActor
public final class VariablesEditorModel: ObservableObject {
    /// A plugin's row-group as rendered in the editor, paired with the store
    /// that persists its values.
    public struct Group: Identifiable {
        public let id: String
        public let name: String
        public let declarations: [VarDeclaration]
        let prefs: PluginPreferences
    }

    @Published public private(set) var groups: [Group]
    /// Buffered edits keyed `pluginID → (varName → value)`.
    @Published var values: [String: [String: String]] = [:]

    private let onSaved: () -> Void

    /// Builds the editor from aggregated groups. `secretStore` lets tests inject
    /// an in-memory store; production uses the per-plugin Keychain store.
    public init(
        groups aggregated: [PluginVariableGroup],
        secretStore: ((PluginID) -> SecretStoring)? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        self.onSaved = onSaved
        var built: [Group] = []
        var initial: [String: [String: String]] = [:]
        for group in aggregated {
            let prefs = PluginPreferences(
                pluginPath: group.pluginPath,
                pluginID: group.pluginID,
                declarations: group.declarations,
                secretStore: secretStore?(group.pluginID)
            )
            var perPlugin: [String: String] = [:]
            for declaration in group.declarations {
                perPlugin[declaration.name] = prefs.value(for: declaration)
            }
            initial[group.pluginID.rawValue] = perPlugin
            built.append(Group(id: group.pluginID.rawValue, name: group.pluginName, declarations: group.declarations, prefs: prefs))
        }
        self.groups = built
        self.values = initial
    }

    func stringBinding(_ pluginID: String, _ declaration: VarDeclaration) -> Binding<String> {
        Binding(
            get: { self.values[pluginID]?[declaration.name] ?? "" },
            set: { self.values[pluginID, default: [:]][declaration.name] = $0 }
        )
    }

    func boolBinding(_ pluginID: String, _ declaration: VarDeclaration) -> Binding<Bool> {
        Binding(
            get: { (self.values[pluginID]?[declaration.name] ?? "false") == "true" },
            set: { self.values[pluginID, default: [:]][declaration.name] = $0 ? "true" : "false" }
        )
    }

    /// Persists every buffered value through each plugin's `PluginPreferences`
    /// (secrets to the Keychain, the rest to the sidecar), then notifies.
    public func save() {
        for group in groups {
            for declaration in group.declarations {
                let value = values[group.id]?[declaration.name] ?? declaration.defaultValue
                try? group.prefs.setValue(value, for: declaration)
            }
        }
        onSaved()
    }
}

/// The **Variables** tab: a top-level editor aggregating every installed
/// plugin's declared variables, grouped by plugin, each editable, with secret
/// fields masked. Supersedes xbar's per-plugin `xbar.var` GUI.
public struct VariablesEditorView: View {
    @ObservedObject private var model: VariablesEditorModel

    public init(model: VariablesEditorModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            if model.groups.isEmpty {
                ContentUnavailableView(
                    "No variables",
                    systemImage: "curlybraces",
                    description: Text("No installed plugin declares configurable variables.")
                )
            } else {
                Form {
                    ForEach(model.groups) { group in
                        Section(group.name) {
                            ForEach(group.declarations, id: \.name) { declaration in
                                VarDeclarationField(
                                    declaration: declaration,
                                    stringValue: model.stringBinding(group.id, declaration),
                                    boolValue: model.boolBinding(group.id, declaration)
                                )
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                Divider()
                HStack {
                    Text("Secret values are stored in your macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { model.save() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
        }
    }
}
