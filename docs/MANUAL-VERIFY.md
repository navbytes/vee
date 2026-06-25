# Vee — Manual Verification Guide (desktop)

Most of Vee is covered by automated tests (146 Swift + 12 node), but the
OS-facing surfaces — the launcher window, menubar, global hotkey firing, real
app launching, and clipboard capture — can only be confirmed by a human at a
logged-in macOS desktop. This is that checklist.

## Build & run

```sh
swift build -c release
.build/release/vee        # or: swift run vee
```

Vee runs as a **menubar accessory** (no Dock icon) with a run loop, so the
command does not return — quit it with Ctrl-C or by killing the process.

## What you should see / check

1. **Menubar item** — a `Vee` item appears in the system menu bar.
2. **Open the launcher** — press **Option+Space**. A centered HUD panel appears
   with the search field focused.
3. **App search** — type part of an installed app's name (e.g. `saf`). The list
   filters to matching apps instantly (native fuzzy match — no per-keystroke
   I/O; the app set is enumerated once at startup).
4. **Keyboard nav** — ↑/↓ move the selection; the highlighted row tracks it.
5. **Launch** — press **Return** on a selected app → it launches (and Vee
   records the launch, feeding frecency ranking next time).
6. **Dismiss** — **Esc** hides the panel.
7. **Frecency** — after launching a few apps, reopen and note that
   recently/often-used apps rank higher on an empty query.

## Visual reference & autonomous snapshots

The launcher is rendered offscreen to a PNG by the built-in snapshot harness —
this is how the UI was iterated to a Raycast-grade look without a live desktop,
and it doubles as a visual-regression check:

```sh
VEE_SNAPSHOT_OUT=/tmp/vee.png swift run vee                 # dark, all apps
VEE_SNAPSHOT_OUT=/tmp/vee.png VEE_SNAPSHOT_DARK=0 swift run vee   # light
VEE_SNAPSHOT_OUT=/tmp/vee.png VEE_SNAPSHOT_QUERY=saf swift run vee  # filtered
```

Committed reference renders: [`docs/screenshots/launcher-dark.png`](screenshots/launcher-dark.png),
`launcher-light.png`, `launcher-filtered.png` — real app icons, an
"APPLICATIONS" section header, a right-aligned "Application" type accessory, a
rounded neutral selection, and a footer (selected icon + Launch ↩ + Actions ⌘K).

## Known limitations in this build (by design / follow-ups)

- **Real app icons** now render (full-color, via `NSWorkspace.icon`); ✅ done.
- The footer's **Actions ⌘K** is presentational — the actions panel isn't wired yet.
- **Clipboard history** is captured in memory and privacy-filtered
  (1Password/concealed/transient dropped) but has **no launcher surface yet** —
  it runs in the background; verify behavior via the unit tests, not the UI.
- **Only host-native app search** is wired as the launcher surface. JS plugins
  (the `hello-list` sample and the GitHub/Jira/meeting-bar plugins) are **not
  auto-loaded**; the hot-reload infra (FSEvents watcher + esbuild bundler) is
  wired but dormant until a plugin is loaded via `host.load`.
- **Out-of-process execution is not yet real** (in-process loopback transport),
  so a misbehaving plugin would not be crash-isolated.
- **No code signing / entitlements / Info.plist** → calendar (EventKit
  full-access TCC prompt) and App-Sandbox behaviors are untested.

## Hotkey notes

- The default chord is **Option+Space** (Cmd+Space is Spotlight's and the OS
  would refuse it). Rebind in `Sources/vee/main.swift`.
- If the launcher doesn't appear on the chord, Vee prints
  `vee: launcher hotkey not registered: …` to stderr when the OS refuses the
  registration. `RegisterEventHotKey` does **not** require Accessibility
  permission. Note the documented macOS 15 regression (FB15168205) for
  Option-only chords in *sandboxed* apps — Vee is unsandboxed, so it should not
  apply, but if Option+Space misbehaves try a Cmd/Ctrl-modified chord.

## What's already covered by automated tests (no desktop needed)

The engine (JSC bridge, memory rules, microtask ordering, render mirror,
capability-gated `fetch`/`clipboard`/`keychain`), the fuzzy matcher, the SWR
cache, the keychain store, RFC-6902 JSON-Patch, the clipboard **privacy filter**,
the coordinator's projection + selection-preservation + native-filter wiring, and
the TS↔Swift `hello-list` fixture handshake. Run `swift test` (146 tests, 1
live-keychain skipped) and `cd plugins && npm test` (12 tests). See
[STATUS.md](STATUS.md) for the full spec-coverage matrix.
