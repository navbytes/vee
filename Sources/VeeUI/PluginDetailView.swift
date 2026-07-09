import SwiftUI

/// The per-plugin models the consolidated window hosts in-pane when an installed
/// plugin is selected. Built by the app from the plugin's live `PluginCoordinator`
/// (see `AppController.makeLibraryModel`) without opening a window. `settings` is
/// `nil` when the plugin has nothing to configure; `debug` is always present (the
/// coordinator's live, cached console model).
public struct PluginDetailModels {
    public let settings: PluginSettingsModel?
    public let debug: PluginDebugModel

    public init(settings: PluginSettingsModel?, debug: PluginDebugModel) {
        self.settings = settings
        self.debug = debug
    }
}

/// The detail pushed into the Installed section when a plugin is selected: a
/// segmented Settings / Debug switch hosting the existing per-plugin views, so
/// selecting a plugin shows its configuration and console in-pane instead of in
/// separate windows. Pushed onto `LibraryView`'s existing detail `NavigationStack`
/// (there is no nested split view), which supplies the back button.
struct PluginDetailView: View {
    private enum Tab: Hashable { case settings, debug }

    let name: String
    let models: PluginDetailModels
    @State private var tab: Tab

    init(name: String, models: PluginDetailModels) {
        self.name = name
        self.models = models
        // Land on Settings when the plugin has any; otherwise open straight to
        // Debug so the initial tab is never a dead "No settings" state.
        _tab = State(initialValue: models.settings == nil ? .debug : .settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Settings").tag(Tab.settings)
                Text("Debug").tag(Tab.debug)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 8)

            Divider()

            switch tab {
            case .settings:
                if let settings = models.settings {
                    // The embeddable form content (no window chrome), filling the
                    // pane. Save is an in-form button that just applies and stays;
                    // the NavigationStack back button returns to the Installed list.
                    PluginSettingsFormContent(model: settings, onSave: { settings.save() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No settings",
                        systemImage: "slider.horizontal.3",
                        description: Text("This plugin has no configurable settings.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .debug:
                PluginDebugContent(model: models.debug)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(name)
    }
}
