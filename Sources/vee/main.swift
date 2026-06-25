import VeeApp

// Thin executable entrypoint. The real AppKit bootstrap (NSApplication, the
// launcher panel, the menubar item, global hotkey registration) is added in
// Wave 3 and lives behind protocols in `VeeApp`; `main` stays minimal.
_ = AppCoordinator()
print("vee: engine scaffold OK — see docs/ARCHITECTURE.md")
