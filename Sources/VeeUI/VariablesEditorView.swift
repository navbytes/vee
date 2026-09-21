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
            } else if declaration.kind == .number {
                // Keep the field to a valid decimal as the user types, so a
                // numeric preference can't be saved with letters or symbols.
                TextField(label, text: $stringValue)
                    .onChange(of: stringValue) { _, newValue in
                        let sanitized = NumericInput.sanitize(newValue)
                        if sanitized != newValue { stringValue = sanitized }
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
    public struct SaveFailure: Equatable, Sendable {
        public let pluginName: String
        public let fieldName: String
    }

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
    private var persistedValues: [String: [String: String]] = [:]
    @Published public private(set) var saveFailures: [SaveFailure] = []

    private let onSaved: () -> Void
    private let persistValue: ((String, VarDeclaration, String) throws -> Void)?
    private let secretStore: ((PluginID) -> SecretStoring)?

    /// Builds the editor from aggregated groups. `secretStore` lets tests inject
    /// an in-memory store; production uses the per-plugin Keychain store.
    public init(
        groups aggregated: [PluginVariableGroup],
        secretStore: ((PluginID) -> SecretStoring)? = nil,
        persistValue: ((String, VarDeclaration, String) throws -> Void)? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        self.onSaved = onSaved
        self.persistValue = persistValue
        self.secretStore = secretStore
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
        self.persistedValues = initial
    }

    public var isDirty: Bool { values != persistedValues }

    public func bufferedValue(pluginID: String, field: String) -> String? { values[pluginID]?[field] }

    public func setBufferedValue(_ value: String, pluginID: String, field: String) {
        values[pluginID, default: [:]][field] = value
    }

    public func reconcile(groups aggregated: [PluginVariableGroup]) {
        let previous = values
        let previousDeclarations = Dictionary(uniqueKeysWithValues: groups.map { group in
            (group.id, Dictionary(group.declarations.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }))
        })
        var built: [Group] = []
        var reconciled: [String: [String: String]] = [:]
        var persisted: [String: [String: String]] = [:]
        for group in aggregated {
            let prefs = PluginPreferences(
                pluginPath: group.pluginPath, pluginID: group.pluginID, declarations: group.declarations,
                secretStore: secretStore?(group.pluginID)
            )
            var current: [String: String] = [:]
            var baseline: [String: String] = [:]
            for declaration in group.declarations {
                let stored = prefs.value(for: declaration)
                baseline[declaration.name] = stored
                let prior = previousDeclarations[group.pluginID.rawValue]?[declaration.name]
                let compatible = prior?.kind == declaration.kind && prior?.isSecret == declaration.isSecret
                let oldValue = previous[group.pluginID.rawValue]?[declaration.name]
                let oldBaseline = persistedValues[group.pluginID.rawValue]?[declaration.name]
                current[declaration.name] = compatible && oldValue != oldBaseline ? (oldValue ?? stored) : stored
            }
            built.append(Group(id: group.pluginID.rawValue, name: group.pluginName, declarations: group.declarations, prefs: prefs))
            reconciled[group.pluginID.rawValue] = current
            persisted[group.pluginID.rawValue] = baseline
        }
        groups = built
        values = reconciled
        persistedValues = persisted
        saveFailures = []
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
    @discardableResult
    public func save() -> Bool {
        var failures: [SaveFailure] = []
        for group in groups {
            for declaration in group.declarations {
                let value = values[group.id]?[declaration.name] ?? declaration.defaultValue
                do {
                    if let persistValue {
                        try persistValue(group.id, declaration, value)
                    } else {
                        try group.prefs.setValue(value, for: declaration)
                    }
                } catch {
                    failures.append(SaveFailure(pluginName: group.name, fieldName: declaration.name))
                }
            }
        }
        saveFailures = failures
        guard failures.isEmpty else { return false }
        persistedValues = values
        onSaved()
        return true
    }
}

/// The **Variables** tab: a top-level editor aggregating every installed
/// plugin's declared variables, grouped by plugin, each editable, with secret
/// fields masked. Supersedes xbar's per-plugin `xbar.var` GUI.
public struct VariablesEditorView: View {
    @ObservedObject private var model: VariablesEditorModel
    @State private var justSaved = false

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
                    // `.lineLimit(1)` on both: a narrow window otherwise wraps
                    // this sentence onto a second line and squeezes "Saved"/
                    // the Save button into the same hyphenation risk as a
                    // capsule chip.
                    Text("Secret values are stored in your macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if justSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                .animation(.easeInOut(duration: 0.2), value: justSaved)
                if !model.saveFailures.isEmpty {
                    Text(saveFailureMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .accessibilityLabel(saveFailureMessage)
                }
            }
        }
        .navigationTitle("Variables")
    }

    /// Persists edits and shows a brief "Saved" confirmation, so the fire-and-
    /// forget Save button gives visible feedback that changes took effect.
    private func save() {
        guard model.save() else {
            justSaved = false
            return
        }
        justSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justSaved = false
        }
    }

    private var saveFailureMessage: String {
        let fields = model.saveFailures.map { "\($0.pluginName): \($0.fieldName)" }.joined(separator: ", ")
        return "Couldn’t save \(fields). Check storage permissions and try again."
    }
}
