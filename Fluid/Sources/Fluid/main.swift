#if os(macOS)
import AppKit

// The Fluid menu-bar app. Everything interesting lives in FluidHostCore; this
// target is the AppKit/SwiftUI shell around it.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#else
import Foundation

print("The Fluid app runs on macOS. On this platform, use fluidctl to build and render plugins.")
#endif
