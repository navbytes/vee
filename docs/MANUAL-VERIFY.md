# Vee — Manual Verification Guide (desktop)

Most of Vee is covered by automated tests (336 Swift + 38 node), but the
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

Committed reference renders in [`docs/screenshots/`](screenshots/): `launcher-dark.png`
/ `launcher-light.png` (app list), `launcher-root-commands.png` (plugin commands +
apps in the root), `launcher-plugin.png` (a plugin rendering in the launcher), and
`launcher-empty.png` — real app icons, accent-tinted floating selection, key-cap
footer (↩ / ⌘K). The launcher UI passed an independent UX review at 8.6/10
("Raycast-grade, ship it").

## Plugins

Three plugins ship as `@vee/sdk` bundles (`plugins/samples/`, built to
`plugins/fixtures/*.bundle.js`, bundled into the app at `Resources/vee-plugins/`):

| Plugin | Bridge | What it does |
|---|---|---|
| **Essentials** | none | Static command list (Search Files, Clipboard History, Calculator, …) |
| **Hacker News** | `vee.http.fetch` | Live top stories from the public HN API |
| **Clipboard History** | `vee.clipboard` | Recent privacy-filtered clipboard items; ↩ copies |

They appear at the top of the launcher root (⌥Space → they're listed above your
apps); selecting one and pressing ↩ activates the plugin, which renders its list
in the launcher. Each is proven by VeeEngine tests (load → activate → render in
real JSC with faked bridges) and node tests. **Backlog:** an `open URL` / `run`
bridge (so a Hacker News story or an Essentials command can actually open its
target), and wiring the live `vee.clipboard` provider into the app host (today the
Clipboard plugin renders live only if a `ClipboardProviding` is injected — it's
proven against a fake in tests).

## Plugin preferences (the Raycast configuration model)

Configuration is **owned by the plugin author, not the app**. The launcher itself
never asks you to configure GitHub or any API key — open **⌥Space** and you see
apps + plugin commands, nothing else.

1. **Generic Extensions pane** — menubar **Settings… → Extensions**. A sidebar
   lists the *installed* extensions; selecting one renders a form built entirely
   from that plugin's declared preferences (text fields, secure fields,
   checkboxes, dropdowns). There is **no hardcoded GitHub/Linear/OpenAI roster** —
   an extension that declares nothing shows "no settings to configure."
2. **GitHub** declares a required `password` preference "Personal Access Token";
   **Jira** declares Site / Email / API Token. These appear *because the plugins
   declared them* — nothing app-side enumerates them.
3. **Secrets** (password type) are stored in the Keychain; other values in a
   preferences store. A saved secret shows "•••••••• (saved)" and is never echoed.
4. **Setup required** — run *GitHub Pull Requests* from the launcher with no token
   set: instead of running, Vee opens Settings focused on the GitHub extension
   (its form shows a "needs setup" banner). Save a token, run it again → it loads.
5. A plugin reads its own values at runtime via `getPreferenceValues()` (see
   `plugins/RUNTIME.md` §2.3); the host injects them on each activate.

## Menu-bar commands (Raycast-style menu-bar extras)

A plugin command with `mode: "menu-bar"` runs in the background and owns its own
menu-bar item (separate from the "Vee" item). Verify on the desktop:

1. **Folder Monitor** (`plugins/samples/folder-monitor`) ships as a menu-bar
   command, so a second menu-bar item appears on launch (titled "Folder" until
   configured). Open **Settings → Extensions → Folder Monitor**, set "Folder to
   Watch" to a real path → its menu-bar item updates to that folder's file count
   and the dropdown lists the files. Choosing a file opens it; "Refresh" re-reads.
   When the count changes between the 30-second refreshes, a system notification
   fires (`vee.notify`).
2. The item is driven by the plugin's render tree (root `title`/`icon` →
   status button; `list-item`s → dropdown rows) — the same declarative
   `RenderNode` model as a launcher view, projected onto an `NSStatusItem`.

The OS-facing bits (the live status item, real folder reads, notification
banners) are desktop-manual; the projection, the per-plugin render mirror, the
coordinator demux, the `fs.list` capability gate, and `notify` delivery are all
covered by the automated suite (`MenuBarTests`, `Wave2cBridgeTests`).

## Known limitations in this build (by design / follow-ups)

- **Real app icons** now render (full-color, via `NSWorkspace.icon`); ✅ done.
- The footer's **Actions ⌘K** opens a keyboard-driven popover of the selected
  item's actions (↑/↓ + ↩ to invoke, esc to dismiss). ✅ done.
- **Clipboard history** is captured in memory and privacy-filtered
  (1Password/concealed/transient dropped) but has **no launcher surface yet** —
  it runs in the background; verify behavior via the unit tests, not the UI.
- Plugins are now **discovered, staged into the out-of-process child, and
  surfaced** in the launcher root (each command appears as a `cmd:` candidate
  above your apps; selecting it activates the plugin, which renders into the
  launcher). App search is the pluginless root surface alongside them.
- **Out-of-process execution is now real**: the app runs plugins in a
  `vee-plugin-host` child (in-process fallback only if the child binary is
  missing), so a crashing plugin is isolated from the launcher and the child is
  auto-restarted. It is a *crash*-isolation boundary, not yet a privilege/sandbox
  boundary (the child runs with real providers + ambient authority). Verify on the
  desktop: kill the `vee-plugin-host` process and confirm the launcher survives and
  plugins keep working after a reopen.
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
the TS↔Swift `hello-list` fixture handshake. Run `swift test` (336 tests, 1
live-keychain skipped) and `cd plugins && npm test` (38 tests). See
[STATUS.md](STATUS.md) for the full spec-coverage matrix.
