# Proposal: widget-vocabulary-parity

## Why

The widget's bounded vocabulary lags the menu surface — no category charts
(`pie=`/`donut=`/`stackedbar=`), no per-item tap targets in `list`/`board`
cards — and nothing forces the gap to close or even be acknowledged: when menu
vocabulary grows, the widget silently falls further behind. The gaps that are
*deliberate* (no `shell` actions — the contract's §6 security decision; no
sliders, scrolling, or freeform layout — WidgetKit and the bounded-canvas
policy) are recorded nowhere a build can enforce.

## What Changes

- **Category charts on the widget**: a `chart` leaf joins the `WidgetNode`
  layout-tree vocabulary (kind pie/donut/stackedbar, values, labels, colors),
  clamped by `WidgetCardParser` app-side and rendered by a small Swift Charts
  view in the extension — the same seam every widget feature already uses
  (schema in `VeeWidgetShared`, parse app-side, render in extension; the
  extension links nothing new).
- **Per-item tap targets**: `WidgetCardItem` gains optional `href` / `shortcut`,
  rendered as tappable rows (`Link` / App-Intent button) in the `list` and
  `board` templates. `shell` remains excluded, per the contract and the
  recorded trust-model decision.
- **Compile-time parity guard**: an exhaustive mapping in `VeePluginFormat`
  (which already depends on `VeeWidgetShared`) from every `MenuAccessory` case
  and dispatchable action kind to a widget disposition — supported or
  excluded-with-reason. Adding a menu display graphic without answering the
  widget question becomes a build failure.
- **Parity ledger**: `docs/design/surface-parity.md` — the feature × surface
  matrix, exclusions with reasons, kept current by the guard plus review.
- **Always-on rule**: a repo `CLAUDE.md` (none exists today) instructing any
  session touching `LineParams`/`MenuAccessory`/`WidgetNode` to update the
  parity switch and ledger.
- SDKs (TS/Python/Go), fixtures, JSON schema, and docs-site updates for the two
  new vocabulary items.
- Deferred to future changes (recorded in the ledger, not lost): bitmap images
  via the contract's cache-and-reference scheme, an interactive `toggle` action
  kind, timeline arrays.

## Capabilities

### New Capabilities

- `widget-vocabulary`: what the widget layout tree and card templates can
  express — category charts, tappable items — and the parity guarantee: every
  menu display graphic and action kind has a declared, build-enforced widget
  disposition.

### Modified Capabilities

_None — the menu surfaces are untouched._

## Impact

- `Sources/VeeWidgetShared` — `WidgetNode` (`chart` leaf), `WidgetCardItem`
  (`href`/`shortcut`).
- `Sources/VeePluginFormat` — `WidgetCardParser` (clamping/diagnostics), the
  new parity mapping.
- `WidgetExtension` — chart renderer, tappable list/board rows
  (`WidgetNodeView`, `WidgetCardView`, intents).
- `plugins/typescript|python|go` SDKs, fixtures, `docs/schemas`, docs site.
- New: `docs/design/surface-parity.md`, repo `CLAUDE.md`.
- Widget extension build/signing is Xcode-project-side; QA per the recorded
  build lesson for Vee's extensions.
