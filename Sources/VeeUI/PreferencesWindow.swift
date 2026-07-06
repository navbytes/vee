import AppKit
import SwiftUI

/// The app-wide Preferences window content: a standard tabbed layout with a
/// **General** tab (app-level settings) and a **Variables** tab (the
/// cross-plugin `<xbar.var>` editor).
public struct PreferencesView: View {
    @ObservedObject private var general: GeneralSettingsModel
    @ObservedObject private var variables: VariablesEditorModel

    public init(general: GeneralSettingsModel, variables: VariablesEditorModel) {
        self.general = general
        self.variables = variables
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(model: general)
                .tabItem { Label("General", systemImage: "gearshape") }
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

    public func show(general: GeneralSettingsModel, variables: VariablesEditorModel) {
        let view = PreferencesView(general: general, variables: variables)
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
