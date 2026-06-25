import Foundation
import VeeEngine

// Out-of-process plugin host (child process). Speaks framed JSON-RPC over
// stdin/stdout to the parent `vee` app, running plugins in JavaScriptCore in its
// own address space so a crashing plugin can't take down the launcher.
//
// Wave R2a worker implements the run loop here (read stdin → drive PluginHost →
// write stdout) per build plan. This stub keeps the target compiling.
FileHandle.standardError.write(Data("vee-plugin-host: stub (not yet wired)\n".utf8))
