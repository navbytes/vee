# Vee

A modern, native macOS menu-bar script runner — a fast, leak-free successor to
[xbar](https://github.com/matryer/xbar) / [SwiftBar](https://github.com/swiftbar/SwiftBar).

Vee runs plugins — any executable in any language — on a schedule and renders
their stdout as menu-bar items and dropdowns. It aims to be a **SwiftBar
superset**: existing xbar/SwiftBar plugins run unchanged, while Vee adds a native
AppKit UI, a trust/transparency layer, and (later) a typed plugin SDK.

## Status

Under active construction. See the staged build plan below.

## Principles

1. **Native & leak-free** — pure Swift/AppKit (`NSStatusItem`/`NSMenu`), no
   embedded WebView in the menu. Rigorous subprocess handling (incremental pipe
   draining, timeout/kill) so long-running use doesn't leak memory the way xbar's
   WebView architecture does.
2. **Runs the existing ecosystem** — the xbar/SwiftBar plugin format
   (filename-encoded refresh intervals, `---`/`--` menus, `|` params, `<xbar.*>`
   / `<swiftbar.*>` headers, SF Symbols, streaming) works on day one.
3. **Transparency, not a sandbox** — plugins run un-sandboxed with full user
   privileges (the model requires it). Instead of pretending to isolate them,
   Vee lets plugins **declare** what they touch (network, filesystem, secrets)
   and surfaces a per-plugin trust summary. This is advisory, never enforced.
4. **Configuration belongs to the plugin** — plugins declare their own typed
   preferences (`<xbar.var>`); the app renders a generic settings form and never
   hardcodes service names or credentials. Secrets live in the Keychain.

Distributed Developer-ID-signed and notarized **outside** the Mac App Store (the
sandbox App Store requires is incompatible with arbitrary plugin execution).

## Requirements

macOS 26+ (Liquid Glass; newest AppKit/SwiftUI APIs). Swift 6.2+ / Xcode 26+.

## Repository layout

```
vee/
├─ Package.swift          # SwiftPM manifest — libraries hold all testable logic
├─ Sources/
│  ├─ VeeCore/            # Shared primitives (RefreshInterval, PluginFilename, clock, errors)
│  ├─ VeeApp/             # AppKit shell (status items, app delegate) as a library
│  └─ vee/               # Thin executable entry point (`swift run vee`)
├─ Tests/                 # XCTest suites (TDD)
├─ project.yml            # XcodeGen spec → Vee.app bundle (Info.plist, entitlements)
└─ App/                   # Info.plist properties + entitlements for the app target
```

## Build & test

```sh
swift build          # build the libraries + dev executable
swift test           # run the test suites
swift run vee        # run the menu-bar app for development

# Build the distributable app bundle:
xcodegen generate
xcodebuild -project Vee.xcodeproj -scheme Vee build
```

## Staged build plan

0. **Scaffold + static status item** — SPM package, `Vee.app`, one menu-bar item. ← current
1. **Plugin-format parser** — the xbar/SwiftBar output + header format.
2. **Runtime** — discovery, execution, scheduling (leak-free).
3. **Menu rendering + actions** — real community plugins render end-to-end.
4. **Streaming plugins** — `~~~` live updates with restart/backoff.
5. **Declared preferences** — `<xbar.var>` forms; secrets in Keychain.
6. **Trust layer** — `<vee.*>` capability declarations + trust summaries.
7. **Plugin manager, login item, notarized distribution.**
8. **Structured protocol + typed TypeScript SDK.**
