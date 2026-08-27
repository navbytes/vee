# Design: widget-vocabulary-parity

## Context

See proposal.md — Why. The widget pipeline's one seam: schema types in
`VeeWidgetShared` (Foundation-only; the sandboxed extension links only this
module), sanitizing in `WidgetCardParser` (`VeePluginFormat`, app-side),
rendering in `WidgetExtension` (SwiftUI + WidgetKit). `VeePluginFormat`
already depends on `VeeWidgetShared`. The extension already renders gauges and
sparklines with plain SwiftUI/Charts; `SparklineChartView` (app side) proves
Swift Charts works AppKit-free. Menu display graphics are the closed
`MenuAccessory` enum; widget actions are the closed `WidgetActionKind` enum
(`shell` excluded by contract §6 and the recorded trust-model decision).

## Goals / Non-Goals

**Goals:**
- Close the two highest-value gaps (category charts, tappable items) through
  the existing seam — no new module linkage for the extension.
- Make future gaps impossible to create silently: a build-time answer is
  demanded for every new menu graphic/action kind.

**Non-Goals:**
- Bitmap images, interactive toggle, timeline arrays — deferred, recorded in
  the ledger.
- Rendering menu body rows on the widget, or any parity for live sliders,
  scrolling, freeform layout, shell (permanent exclusions).
- Sharing chart *view* code between app and extension — the models and
  clamping rules are shared; the compact widget drawing is its own ~60-line
  view, sized for tiles.

## Decisions

1. **`chart` as a `WidgetNode` leaf, not a new template.** Fields: `kind`
   (`pie`/`donut`/`stackedbar`), `values`, optional `labels`, optional
   `colors` (`SnapshotColor`), reusing the node `style` for sizing/tint. The
   parser clamps like existing leaves (drop non-finite, cap segment count,
   unknown kind → diagnostic + drop the leaf, card survives). Templates stay
   frozen; the tree is the designed extension point.

2. **Item taps reuse the action vocabulary.** `WidgetCardItem` gains optional
   `url` and `shortcut` (mirroring `WidgetCardAction`'s `href`/`shortcut`
   kinds); `list`/`board` render a declaring row as `Link` (href) or an
   App-Intent button through the existing `WidgetActionRequest` path
   (shortcut). No `shell`, enforced by the schema simply not carrying it.

3. **The parity guard is an exhaustive switch, not a test.** In
   `VeePluginFormat`: `WidgetParity.disposition(of: MenuAccessory) ->
   Disposition` and `disposition(ofActionKind:)` over the dispatch set, where
   `Disposition` is `.supported` / `.excluded(reason: String)`. A new
   `MenuAccessory` case fails compilation until answered — the compiler is the
   drift test. A small unit test renders the dispositions into
   `docs/design/surface-parity.md`'s table section and asserts the file is
   current (same regenerate-on-drift pattern as the SDK fixtures).

4. **The always-on rule is a repo `CLAUDE.md`.** One short section: touching
   `LineParams`/`MenuAccessory`/`WidgetNode`/`WidgetCard` requires updating
   `WidgetParity` and the ledger. A skill only fires when invoked; CLAUDE.md
   loads every session — right home for a guard. (No repo CLAUDE.md exists
   yet; keep it minimal so it stays read.)

5. **SDK surface**: `chart(...)` node builder + item `href`/`shortcut` fields
   in TS/Python/Go, one new fixture example per axis, JSON schema updated.

## Risks / Trade-offs

- [Ledger doc drifts from the switch] → The unit test regenerates/asserts the
  table from the switch itself; prose around it can drift, facts cannot.
- [Widget chart legibility at `small` family] → Follow the node `families`
  mechanism already designed for adaptation-by-subtraction; document
  pie/donut minimum sizes in the docs site.
- [Extension binary growth from Swift Charts] → The extension already ships
  SwiftUI; Charts is a system framework, no bundle cost.
- [Xcode-project target changes (intent wiring) are outside SPM CI] → Matches
  the existing compile-only reality documented in the widget contract; QA per
  the recorded extension build/sign lesson.

## Open Questions

None.
