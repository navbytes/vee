import SwiftUI
import VeeCatalog

/// Backing model for the Preferences **Stores** tab. Wraps the `StoreRegistry`
/// and per-store token storage, and can test a store's connection. Token storage
/// and client construction are injected so the model is testable without the
/// Keychain or the network.
@MainActor
public final class StoresSettingsModel: ObservableObject {
    @Published public private(set) var stores: [StoreConfig] = []

    private let registry: StoreRegistry
    private let makeTokenStore: (StoreID) -> StoreTokenStoring
    private let makeClient: (StoreConfig, StoreTokenProviding?) -> CatalogFetching

    public init(
        registry: StoreRegistry = StoreRegistry(),
        makeTokenStore: @escaping (StoreID) -> StoreTokenStoring = { KeychainStoreTokenStore(storeID: $0) },
        makeClient: @escaping (StoreConfig, StoreTokenProviding?) -> CatalogFetching = { CatalogClientFactory.make(for: $0, tokenProvider: $1) }
    ) {
        self.registry = registry
        self.makeTokenStore = makeTokenStore
        self.makeClient = makeClient
        reload()
    }

    public func reload() { stores = registry.stores() }

    /// Toggles a store on/off. Managed stores are force-enabled and ignore this.
    public func setEnabled(_ enabled: Bool, _ store: StoreConfig) {
        registry.setEnabled(enabled, id: store.id)
        reload()
    }

    /// Removes a user store and clears its saved token.
    public func remove(_ store: StoreConfig) {
        try? registry.remove(store.id)
        makeTokenStore(store.id).set(nil)
        reload()
    }

    /// Adds a user store, saving its token if one was provided.
    public func add(_ config: StoreConfig, token: String?) throws {
        try registry.add(config)
        if let token, !token.isEmpty { makeTokenStore(config.id).set(token) }
        reload()
    }

    /// Loads the store's index once to verify the location + token, returning the
    /// plugin count or a human-readable failure.
    public func testConnection(_ config: StoreConfig, token: String?) async -> Result<Int, String> {
        let provider: StoreTokenProviding? = (token?.isEmpty == false) ? StaticToken(token ?? "") : nil
        do {
            let entries = try await makeClient(config, provider).fetchIndex()
            return .success(entries.count)
        } catch {
            return .failure(CatalogErrorPresenter.message(for: error))
        }
    }

    /// A one-shot token provider for a not-yet-saved store under test.
    private struct StaticToken: StoreTokenProviding {
        let value: String
        init(_ value: String) { self.value = value }
        func token() -> String? { value }
    }
}

/// The Preferences **Stores** tab: the configured stores with enable toggles,
/// managed rows shown force-enabled, and an Add-store sheet.
public struct StoresSettingsTab: View {
    @ObservedObject private var model: StoresSettingsModel
    @State private var showingAdd = false

    public init(model: StoresSettingsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                ForEach(model.stores) { store in
                    StoreRow(model: model, store: store)
                }
            } header: {
                Text("Stores")
            } footer: {
                Text("Discover shows plugins from every enabled store. Stores set by your organization are locked on.")
            }
            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Store…", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAdd) {
            AddStoreSheet(model: model, isPresented: $showingAdd)
        }
    }
}

/// One row in the Stores list.
private struct StoreRow: View {
    @ObservedObject var model: StoresSettingsModel
    let store: StoreConfig

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.displayName).fontWeight(.medium)
                    if store.isManaged {
                        StoreBadge(text: "Managed", tint: .orange)
                    } else if store.isBuiltIn {
                        StoreBadge(text: "Built-in", tint: .secondary)
                    }
                    if store.requireSignature {
                        StoreBadge(text: "Signed", tint: .accentColor)
                    }
                }
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var trailing: some View {
        if store.isManaged {
            // Force-enabled by the organization — a static state, not a control.
            Text("On").font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { store.isEnabled },
                    set: { model.setEnabled($0, store) }
                ))
                .labelsHidden()
                if !store.isBuiltIn {
                    Button(role: .destructive) {
                        model.remove(store)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this store")
                }
            }
        }
    }

    private var icon: String {
        switch store.kind {
        case .github, .githubEnterprise: return "shippingbox"
        case .http: return "globe"
        case .local: return "folder"
        }
    }

    private var subtitle: String {
        switch store.kind {
        case .github:
            return "\(store.owner ?? "?")/\(store.repo ?? "?")"
        case .githubEnterprise:
            return "\(store.apiHost?.host() ?? "GHE") · \(store.owner ?? "?")/\(store.repo ?? "?")"
        case .http, .local:
            return store.baseURL?.absoluteString ?? "—"
        }
    }
}

private struct StoreBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// A sheet to add a user store: kind, location, an optional token, and trust
/// posture, with a Test Connection check before saving.
private struct AddStoreSheet: View {
    @ObservedObject var model: StoresSettingsModel
    @Binding var isPresented: Bool

    @State private var kind: StoreKind = .github
    @State private var name = ""
    @State private var owner = ""
    @State private var repo = ""
    @State private var ref = "main"
    @State private var apiHost = ""
    @State private var rawHost = ""
    @State private var location = ""
    @State private var manifestPath = "vee-catalog.json"
    @State private var token = ""
    @State private var internalReviewed = true
    @State private var requireSignature = false

    @State private var testing = false
    @State private var testMessage: String?
    @State private var testOK = false
    @State private var addError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        Text("GitHub").tag(StoreKind.github)
                        Text("GitHub Enterprise").tag(StoreKind.githubEnterprise)
                        Text("Static HTTP").tag(StoreKind.http)
                        Text("Local folder").tag(StoreKind.local)
                    }
                    TextField("Name", text: $name, prompt: Text("Acme Internal Tools"))
                }
                locationFields
                Section {
                    if kind != .local {
                        SecureField("Access token (optional)", text: $token)
                    }
                    Toggle("Internal (reviewed) source", isOn: $internalReviewed)
                    Toggle("Require signed plugins", isOn: $requireSignature)
                } footer: {
                    Text("Tokens are stored in your Keychain and sent only to this store. Requiring signatures blocks unsigned plugins and can't be lowered by the store.")
                }
                if let testMessage {
                    Section {
                        Label(testMessage, systemImage: testOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(testOK ? Color.green : Color.red)
                    }
                }
                if let addError {
                    Section { Text(addError).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Test Connection") { Task { await test() } }
                    .disabled(!canBuild || testing)
                if testing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { addStore() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canBuild)
            }
            .padding()
        }
        .frame(width: 470, height: 540)
    }

    @ViewBuilder private var locationFields: some View {
        switch kind {
        case .github:
            Section {
                TextField("Owner", text: $owner, prompt: Text("acme"))
                TextField("Repository", text: $repo, prompt: Text("vee-plugins"))
                TextField("Branch", text: $ref, prompt: Text("main"))
            }
        case .githubEnterprise:
            Section {
                TextField("API host", text: $apiHost, prompt: Text("https://ghe.acme.corp/api/v3"))
                TextField("Raw host", text: $rawHost, prompt: Text("https://ghe.acme.corp/raw"))
                TextField("Owner", text: $owner, prompt: Text("platform"))
                TextField("Repository", text: $repo, prompt: Text("vee-plugins"))
                TextField("Branch", text: $ref, prompt: Text("main"))
            }
        case .http:
            Section {
                TextField("Base URL", text: $location, prompt: Text("https://store.acme.corp/vee/"))
                TextField("Manifest path", text: $manifestPath)
            }
        case .local:
            Section {
                TextField("Folder path", text: $location, prompt: Text("/opt/vee/store"))
                TextField("Manifest path", text: $manifestPath)
            }
        }
    }

    private var canBuild: Bool { buildConfig() != nil }

    /// Builds a `StoreConfig` from the form, or `nil` if required fields are
    /// missing. The id is randomly generated so it never collides.
    private func buildConfig() -> StoreConfig? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        let id = StoreID("user-\(UUID().uuidString.prefix(8).lowercased())")
        let policy: StoreTrustPolicy = internalReviewed ? .internalReviewed : .publicUntrusted
        let auth: StoreAuthMode = token.isEmpty ? .none : .token
        let refValue = ref.trimmingCharacters(in: .whitespaces).isEmpty ? "main" : ref

        switch kind {
        case .github:
            guard !owner.isEmpty, !repo.isEmpty else { return nil }
            return StoreConfig(
                id: id, displayName: trimmedName, kind: .github,
                apiHost: URL(string: "https://api.github.com"),
                rawHost: URL(string: "https://raw.githubusercontent.com"),
                owner: owner, repo: repo, ref: refValue,
                trustPolicy: policy, authMode: auth, requireSignature: requireSignature
            )
        case .githubEnterprise:
            guard !owner.isEmpty, !repo.isEmpty,
                  let api = URL(string: apiHost), api.scheme != nil,
                  let raw = URL(string: rawHost), raw.scheme != nil else { return nil }
            return StoreConfig(
                id: id, displayName: trimmedName, kind: .githubEnterprise,
                apiHost: api, rawHost: raw, owner: owner, repo: repo, ref: refValue,
                trustPolicy: policy, authMode: auth, requireSignature: requireSignature
            )
        case .http:
            guard let base = URL(string: location), base.scheme != nil else { return nil }
            return StoreConfig(
                id: id, displayName: trimmedName, kind: .http,
                baseURL: base, manifestPath: manifestPath,
                trustPolicy: policy, authMode: auth, requireSignature: requireSignature
            )
        case .local:
            guard let base = localURL() else { return nil }
            return StoreConfig(
                id: id, displayName: trimmedName, kind: .local,
                baseURL: base, manifestPath: manifestPath,
                trustPolicy: policy, authMode: .none, requireSignature: requireSignature
            )
        }
    }

    /// Resolves the local-folder field to a `file://` URL (accepts a path or an
    /// already-`file://` string).
    private func localURL() -> URL? {
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("file://") { return URL(string: trimmed) }
        return URL(fileURLWithPath: trimmed)
    }

    @MainActor
    private func test() async {
        guard let config = buildConfig() else { return }
        testing = true
        testMessage = nil
        let result = await model.testConnection(config, token: token)
        testing = false
        switch result {
        case .success(let count):
            testOK = true
            testMessage = "Connected — \(count) plugin\(count == 1 ? "" : "s") found."
        case .failure(let message):
            testOK = false
            testMessage = message
        }
    }

    private func addStore() {
        guard let config = buildConfig() else { return }
        do {
            try model.add(config, token: token)
            isPresented = false
        } catch {
            addError = "Couldn't add the store: \(error)"
        }
    }
}
