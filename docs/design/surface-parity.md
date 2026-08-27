# Design: the surface parity ledger

What each of Vee's surfaces can express, and — where one of them can't — why.

## Why this file exists

Vee draws a plugin's menu on four surfaces that all read the *same* decided
model (`MenuRowSpec`): the menu-bar dropdown, the search panel, a detached
plugin window, and the CLI listing. Parity between those four is structural —
they are handed the same rows, so a difference is a renderer bug, not a policy.

The widget is a different kind of surface. WidgetKit renders it in another
process, from a snapshot the app wrote minutes ago, out of a **bounded
vocabulary** of its own (`WidgetCard` templates and the `WidgetNode` layout
tree) rather than the menu's rows. So the widget can lag the menu, and
sometimes should: a live slider is not a thing a timeline of static views can
host, and an arbitrary `shell=` command is not a thing a tap on the desktop
should run.

Lagging is allowed. Lagging *silently* is what this ledger stops. Every display
graphic a menu row can draw and every action it can dispatch has a recorded
widget disposition — supported, or excluded with a reason — and
`WidgetParity` (in `VeePluginFormat`) holds them in switches with no `default`
case, so a new menu graphic does not compile until its widget question is
answered. See [`widget-surface-contract.md`](widget-surface-contract.md) for
what the widget surface is and why it is bounded.

## Dispositions

Generated from `WidgetParity`; `WidgetParityTests` fails with the replacement
text if this section drifts from the switches. Edit the switch, not the table.

A `(click)` row is the *graphic's* disposition: the widget draws it, and the
popover a click opens on a menu row is a menu-only presentation of data the
tile is already showing.

<!-- BEGIN GENERATED: dispositions (WidgetParity) -->

### Display graphics (`MenuAccessory`)

| Menu | Widget | Reason |
|---|---|---|
| `progress=` | supported | — |
| `sparkline=` | supported | — |
| `pie=` / `donut=` / `stackedbar=` | supported | — |

### Dispatchable actions (`MenuTree.dispatches`)

| Menu | Widget | Reason |
|---|---|---|
| `toggle=` / `slider=` | excluded | WidgetKit renders a static timeline with discrete AppIntent buttons; a toggle or slider has no live value to track and no continuous input to receive |
| `shell=` / `bash=` | excluded | the widget surface contract's §6 trust decision: a widget button must not run an arbitrary command without the menu's context |
| `webview=` | excluded | the bounded-canvas policy: the widget vocabulary is a closed set of native primitives, never a freeform drawing surface |
| `sparkline=` (click) | supported | — |
| `pie=` / `donut=` / `stackedbar=` (click) | supported | — |
| `href=` | supported | — |
| `shortcut=` | supported | — |
| `refresh=true` | supported | — |

<!-- END GENERATED -->

## Feature × surface

The four menu surfaces differ only where the *presentation* cannot carry a row,
never in which rows exist (`visibleOn=` is the one thing that subtracts, and it
subtracts on purpose). The widget differs by vocabulary.

| Feature | Menu bar | Search panel | Window | CLI | Widget |
|---|---|---|---|---|---|
| Body rows, submenus, separators | yes | flattened to matches | yes | yes | no — a plugin targets the widget whole (`<vee.surface>`) and prints a card, not rows |
| Display graphics (`progress=`, `sparkline=`, charts) | inline | inline | inline | text/truecolor | as card fields and layout-tree leaves |
| Live controls (`toggle=`, `slider=`) | graphic inline, control on click | no | control drawn in place | no | no — see the ledger above |
| `key=` equivalents | yes (only an open `NSMenu` can bind one) | no | no | no | no |
| `alternate=true` (⌥ swap) | yes | as an ordinary row | as an ordinary row | as an ordinary row | n/a |
| Actions | full dispatch set | full dispatch set | full dispatch set | printed | `href` / `shortcut` / `refresh` only |

## Deferred, not lost

Recorded here so they stay decisions rather than oversights:

- **Bitmap images on the widget** — awaiting the contract's cache-and-reference
  scheme; the layout tree's `image` leaf renders SF Symbols only.
- **An interactive `toggle` action kind** — a widget button that flips a value
  is expressible in WidgetKit (an `AppIntent`), unlike a live slider; it needs
  a write path back to the plugin, which does not exist yet.
- **Timeline arrays** — a card describes now, not a schedule of futures.
