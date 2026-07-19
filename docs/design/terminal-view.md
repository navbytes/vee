# Design: the terminal view (`vee show`) and its roadmap

Status: **Tier 1 shipped** ([#76](https://github.com/navbytes/vee/pull/76)); the
follow-ups below are **proposed**. Captures what the terminal-view surface is,
the fidelity boundary that scopes it, and the ordered follow-ups — written down
so the direction is agreed and the deferred items don't get re-proposed from
scratch (like [`widget-surface-contract.md`](widget-surface-contract.md) and
[`ui-consolidation.md`](ui-consolidation.md)).

## What this is

`vee show <plugin>` renders what a plugin's menu-bar dropdown would look like —
natively in the terminal — and live-refreshes it on the plugin's own filename
cadence. It came out of a feasibility question about adding a TUI surface, and is
scoped deliberately as a **view** (peek at one plugin, live, without installing
it into the menu bar), not a co-equal third UI surface that competes with the
menu bar.

It reuses the existing AppKit-free cores — `VeeRuntime` (execution/scheduling),
the `VeePluginFormat` parser — and adds only a new frontend under `VeeCLI`:

| Piece | Role | Tested |
| ----- | ---- | ------ |
| `TerminalRenderer` | Pure `ParsedOutput → ANSI` view: `color=`/ANSI as SGR, `progress=` as a block gauge, `sparkline=` as a block sparkline, `toggle=`/`slider=` inline, SF Symbols / base64 images shown by name. | unit |
| `PluginResolver` | Resolves `<plugin>` as a path or an installed name against the plugins folder (mirrors the app's resolution order, dependency-free). | unit |
| `LiveView` | The only real-terminal piece: raw-mode stdin, alt screen, a `poll`-based interval/keypress loop (`r` refresh, `q`/`Ctrl-C` quit). | — (I/O edge) |

Reference: [`../_content/cli-and-urls.md`](../_content/cli-and-urls.md) §`vee show`.

## The fidelity boundary (why the scope is what it is)

A terminal view is a high-fidelity *representation* of the dropdown, not a pixel
copy. This boundary is a deliberate design line, not a bug backlog:

- **Faithful** — item text, nested submenus, separators, alternates (`⌥`),
  section headers, `disabled`/`checked` state, and which action each row would
  fire.
- **Renders well (terminal-native)** — `color=`/ANSI (the terminal is ANSI's home
  turf), emoji, `progress=` (block gauge), `sparkline=` (block ramp).
- **Represented, not reproduced** — `toggle=`/`slider=` show state inline but not
  the Liquid Glass popover; SF Symbols and base64 images show by name
  (`[cpu]`, `[img]`); `webview=` can only be `open`ed, never embedded.

The rich native surfaces (control/sparkline popovers, the WebView, WidgetKit)
remain the menu bar's job by design — trying to reach parity with them in a
terminal is the path this doc explicitly declines (see *Principles*).

## Roadmap

Ordered by value. Tier 1 (the live read-only view) has shipped; everything below
is a follow-up.

### Tier 2 — make rows actionable (recommended next)

Turn the view into a mini-controller. Add selection state to `LiveView` (arrow-key
navigation through the flattened/nested tree) and `Enter` to fire the **safe**
action subset, mirroring `AppActionDispatcher`'s dispatch order:

- `shell=`/`bash=` (detached), `refresh=`, `shortcut=` (via `/usr/bin/shortcuts`),
  `href=` (via `open`).
- `toggle=`/`slider=`: flip / prompt for a value, then re-invoke the item's
  command with `VEE_CONTROL_VALUE` — reusing `ControlReinvocation`, which is
  already a pure, unit-tested core.

The main new piece is a **headless action dispatcher**: today `AppActionDispatcher`
lives in `VeeApp` and is `@MainActor`/AppKit-bound, so extract a GUI-free
equivalent (shell/href/refresh/shortcut/control) that `LiveView` and a future
dashboard can share. The genuinely GUI-only actions (embedded WebView, the native
popovers) stay out — they degrade or are simply not offered.

### Streaming (`~~~`) plugins

`vee show` currently re-runs the plugin each interval; a streaming plugin emits
continuously and is only polled. Tap the runtime's existing `StreamingSession` /
`StreamingProcess` so the view repaints on each emission instead of on a timer.

### Cross-plugin dashboard (larger; only with appetite)

The original "full TUI" — an htop-for-all-plugins view listing every enabled
plugin and its live output — was **deliberately deferred**. It reuses the same
headless cores plus the Tier-2 dispatcher, but it is a substantially bigger
surface to keep at parity. If picked up, keep it a monitoring/dev dashboard; do
**not** let it become a co-equal front-of-house surface to the menu bar (see
*Principles*).

### Polish

- **README + demo.** The CLI docs, CHANGELOG, and ARCHITECTURE mention `vee show`;
  the README feature list does not. A one-line bullet plus an asciinema/GIF would
  surface it.
- **Width-aware layout.** Truncate long rows to the terminal width; right-align
  trailing accessories.
- **Inline images.** SF Symbols / base64 images show by name today; terminals with
  an image protocol (iTerm2 / Kitty / Ghostty, detected via env) could render
  base64 images instead of `[img]`.
- **`cron` cadence.** `.cron` plugins currently behave like `.manual` (wait for
  `r`); compute the next fire time from the expression via the runtime's
  `Cron.swift`.

## Principles (carried from the app)

1. **A view, not a co-equal surface.** The terminal view composes with the menu
   bar; it never tries to replace it or reach parity with its native rich UI.
   This is what keeps it cheap and free of a permanent "why doesn't X render in
   the terminal?" parity tax.
2. **Reuse the headless cores.** All the hard logic (execution, scheduling,
   parsing, search, trust, catalog) already lives in AppKit-free targets. New
   terminal work is frontend only — no `VeeApp` changes.
3. **Zero third-party dependencies.** Terminal control is hand-rolled ANSI +
   `termios`, consistent with the app's zero-dependency policy — the on-brand
   answer that a cross-platform TUI library would violate.
4. **Degrade honestly.** What a terminal can't draw is shown by name, never
   silently dropped; the fidelity boundary above is documented, not hidden.
