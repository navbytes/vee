## Context

See `proposal.md` — Why. The constraints that shape the approach:

- **An `NSMenu` cannot be hosted in a window.** Everything hanging off it is
  `NSMenuItem`-shaped — `NSMenuItem.view`, `sectionHeader`, `isAlternate`,
  `keyEquivalent`. None of it transfers. Two renderers is not a choice made for
  convenience; it is forced by AppKit.
- **The detached window and transient panel already share one view**
  (`MenuSearchContentView`). They move together as one change and cannot drift
  from each other. Only the menu bar is a separate path.
- **The flattener destroys structure deliberately.** `MenuFlattener.walk`'s
  `depth` gate suppresses nested headers and separators, and every row carries a
  breadcrumb precisely because its ancestors are gone. Hierarchy is not latent
  in `[SearchEntry]` waiting to be switched on; the tree view must consume
  `[MenuNode]` directly.
- **Windows are live.** `StatusItemController.render` pushes fresh output on
  every plugin tick, and that is the only place output reaches the UI.
- **`AttributedTitleFactory` and `SymbolImageFactory` are already shared** by
  both paths. Text styling and icons are not sources of drift today and must not
  become sources of drift after the refactor.

## Goals / Non-Goals

**Goals:**

- One resolved description of a plugin's menu that both renderers consume, with
  no presentation decision left in either renderer.
- The window and panel present the plugin's authored structure, openable in
  place, with expansion that survives live refreshes.
- Delete the cross-plugin aggregator and every dependency that exists only to
  serve it.

**Non-Goals:**

- Pixel-identical menu bar and window. They are two presentations of one model;
  flyouts and inline disclosure are both correct.
- Replacing `NSMenu`. Native flyouts, `key=`, `alternate=` modifier-swap,
  type-select, and menu VoiceOver semantics are kept.
- Sharing views with the WidgetKit extension. It renders a different model from
  a separate plugin run in a sandboxed process under a restricted SwiftUI
  subset. Only leaf gauge/sparkline drawing is shared.
- The terminal surface (`vee show` / `vee dev`). Parked, decided separately.

## Decisions

### D1 — One model, two emitters (not one renderer)

A shared `MenuTree` / `MenuRowSpec` in `VeeMenu` resolves every decision once.
`MenuBuilder` becomes an `NSMenu` emitter over it; a new SwiftUI tree view
becomes the other emitter. The acceptance test for the extraction is mechanical:
**if `MenuBuilder` still contains any `if params.x != nil`, it did not land.**

The model must own: which nodes become rows (`dropdown=false`, empty text,
header section scope), actionable vs. inert, submenu-wins-over-action, accessory
selection, alternate placement, title attributes, icon.

*Alternative considered — menu bar adopts SwiftUI in a popover.* Delivers literal
identity and deletes ~600 lines, but requires reimplementing `key=` equivalents,
`alternate=` modifier-swap, type-select, and `NSMenuItem.sectionHeader`, and puts
a SwiftUI hosting controller on the most latency-scrutinised surface in a macOS
app. Rejected: it buys pixel-identity on a surface visible for two seconds by
spending native menu semantics the plugin format directly exposes.

### D2 — Inline disclosure, not hover flyouts or drill-down

The window's purpose is to be left open and watched. Hover flyouts are built for
a surface that vanishes on click-away and are absurd in a resizable window;
drill-down shows one level at a time, which defeats watching two values at once.
Inline disclosure is the only option whose premise is "several things visible
simultaneously," and it is keyboard-trivial and robust.

Cost: visibly different from the menu bar's flyouts, and indentation eats width
in the fixed-size transient panel. Accepted under D1 — presentation may differ,
semantics may not.

### D3 — Filter prunes the tree; ranking is dropped

A query keeps rows that match plus their ancestor chain, and auto-expands the
survivors. `FuzzyScorer` and `SearchText` still decide *what* matches; the
projection changes from "ranked flat list" to "pruned tree."

This gives up fuzzy ranking, which is a real loss — a tree cannot reorder. It is
acceptable because a single plugin's menu is shallow (2–3 levels) and small
(10–40 rows), the scale at which ranking barely pays. It would **not** have been
acceptable for the cross-plugin aggregate (~300 rows, 15 roots), which is why
that surface's removal (D5) and this decision are the same decision viewed twice.

### D4 — Expansion keyed by title path, degrading to closing one branch

`MenuNode` / `MenuItem` are value types with no stable identity, so expansion
must be keyed by something derived. Key on the ancestor **title path**
(`["Disks", "Macintosh HD"]`).

Known failure: a plugin that retitles a group each tick (`"Disks (3)"` →
`"Disks (4)"` — a common idiom) changes its own key and its branch closes. The
spec constrains the degradation: an unrecognisable branch closes *alone* and must
never cascade into unrelated branches.

Mitigations in order, cheapest first:
1. `render()` already short-circuits byte-identical output. Free, and covers the
   many plugins that mostly do not change.
2. If retitling proves common in practice, fall back to a position+depth key,
   which survives retitling but not reordering.
3. A plugin-declared stable key. Correct, but plugin-format surface area for a
   problem most plugins do not have — hold until someone hits it.

Start at (1). Do not build (3) speculatively.

### D5 — Remove cross-plugin search rather than make it a tree

Fifteen plugins are fifteen roots, not one hierarchy, so a tree there needs a
synthetic plugin-name root level and branch ordering by best-descendant score
just to recover the ranking a flat list gives free — while making "type three
letters, Enter" slower. It is unwanted, so it is deleted rather than ported.

Consequences accepted, not engineered around: two orphaned `UserDefaults` keys
are left in place (no migration is worth writing for two dead booleans), and a
user who had enabled the hotkey loses it silently — a CHANGELOG line, not code.

### D6 — Normalization is deleted, not ported

`normalized` / `collapseSeparators` / `dropDanglingHeaders` exist to repair
damage flattening causes: spliced-out submenu contents and suppressed deep
headers leave dangling furniture. A tree creates none of that, and `MenuBuilder`
already emits structural elements exactly as authored without normalizing. The
tree projection is therefore *simpler* than the flat one — a useful signal that
the direction is right. Porting it would reintroduce a divergence from the menu
bar that does not currently exist.

### D7 — Controls live in the window's chrome

Refresh / Settings / About / Reveal / Edit / Debug move into window chrome rather
than into the row list, so the filter cannot match them and they cannot be
confused with plugin output. `⌘R` / `⌘,` become window-level shortcuts rather
than menu key-equivalents.

`⌘F` necessarily means different things per surface: in the window and panel it
focuses the filter field; in the menu bar it must keep opening the panel, because
an `NSMenu` cannot host a text field. `<vee.filter>` therefore keeps its current
job unchanged.

## Risks / Trade-offs

- **Expansion collapsing under live refreshes** → The primary hazard (D4).
  Constrain the degradation in the spec, start with the byte-identical
  short-circuit, and instrument before adding key strategies.
- **A half-landed extraction is worse than none** → If some decisions move to the
  model and others stay in the emitters, drift risk is unchanged but the code is
  larger. Enforce D1's mechanical test: no `params` inspection left in either
  emitter.
- **Deleting a shipped feature with no spec covering it** → Cross-plugin search
  is unspecced, so nothing fails when it disappears. Its tests
  (`aggregateSearchRows`) must be deleted deliberately rather than left to rot,
  and the docs referencing it updated in the same change.
- **Losing fuzzy ranking in the window** → Accepted (D3), bounded by plugin menu
  size. If a user reports a large menu where filtering feels worse than the old
  panel, the fallback is a ranked-flat mode toggled by the presence of a query —
  but do not build it now.
- **Indentation in the fixed 440pt panel** → Deep trees will crowd. The window is
  resizable so it is unaffected; if the panel proves cramped, its fixed size is
  the thing to revisit, not the disclosure model.
- **`vee search` is the last flat consumer** → `MenuFlattener.flatten` /
  `FlatRow` / `FuzzyScorer` survive solely for it. This couples the parked
  terminal decision to a larger cleanup than it appears: removing the terminal
  surface later removes the entire flat projection with it.

## Migration Plan

Land in order, each step green before the next:

1. Extract the shared model; `MenuBuilder` becomes an emitter over it, with **no
   behavior change**. The existing menu tests are the safety net.
2. Delete cross-plugin search and everything that exists only for it, including
   `SearchEntry`, `flattenEntries`, the normalization pass, and `prefixed(with:)`.
3. Build the tree view over the model; switch the window and panel to it.
4. Add expansion persistence and window controls.

Step 1 is independently valuable and independently revertible: it removes all
three real duplications even if steps 3–4 are abandoned. Steps 2 and 3 are the
irreversible ones.

## Open Questions

- Whether the transient panel's fixed 440×380 needs to grow for indented trees —
  answerable from use, and it changes no requirement.
- Whether inline disclosure should also replace the menu bar's flyouts later.
  Deliberately not decided here; D1 makes it a presentation swap rather than a
  re-architecture, so it can be revisited without touching the model.
