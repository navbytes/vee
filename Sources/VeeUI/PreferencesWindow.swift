import AppKit
import SwiftUI

/// The app-wide Preferences window content: a standard tabbed layout with a
/// **General** tab (app-level settings) and a **Variables** tab (the
/// cross-plugin `<xbar.var>` editor).
public struct PreferencesView: View {
    @ObservedObject private var general: GeneralSettingsModel
    @ObservedObject private var variables: VariablesEditorModel
    @ObservedObject private var stores: StoresSettingsModel

    public init(general: GeneralSettingsModel, variables: VariablesEditorModel, stores: StoresSettingsModel) {
        self.general = general
        self.variables = variables
        self.stores = stores
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(model: general)
                .tabItem { Label("General", systemImage: "gearshape") }
            StoresSettingsTab(model: stores)
                .tabItem { Label("Stores", systemImage: "shippingbox") }
            VariablesEditorView(model: variables)
                .tabItem { Label("Variables", systemImage: "curlybraces") }
        }
        .frame(width: 540, height: 480)
    }
}

/// Presents the single app-wide Preferences window (the ⌘, target), hosting the
/// SwiftUI `PreferencesView` in an `NSWindow`. Reopening focuses the existing
/// window and swaps in fresh models.
@MainActor
public final class PreferencesWindow {
    public static let shared = PreferencesWindow()

    private var window: NSWindow?

    public init() {}

    public func show(general: GeneralSettingsModel, variables: VariablesEditorModel, stores: StoresSettingsModel) {
        let view = PreferencesView(general: general, variables: variables, stores: stores)
        if let window {
            (window.contentViewController as? NSHostingController<PreferencesView>)?.rootView = view
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Vee — Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
