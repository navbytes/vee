## Why

Discover draws the catalog as an adaptive card grid whose rows are as tall as
their tallest card and whose cards have different heights (a screenshot is
optional, and a badge row can push a card taller). Because `LazyVGrid` centers
each card in its row, a plugin with a screenshot drags its shorter neighbors
into the vertical middle and leaves large dead gaps between cards. The badge row
is a non-wrapping run of fixed-size chips, so at the grid's narrow columns it
overflows and squeezes the trailing action column instead — truncating "Install"
to "In…" and wrapping "View source". The Installed tab already solves all of
this with clean, uniform, full-width rows; Discover is the last surface that
does not match.

## What Changes

- Replace the Discover card grid with a grouped, full-width **row list** that
  mirrors the Installed tab's `Form` + `.formStyle(.grouped)` presentation, one
  plugin per row.
- Give each row a consistent shape: category tile · title · author/description ·
  ranked badge row, with a trailing action area (Install, or Installed +
  provenance + Update/Reinstall) and a "View source" link.
- In "All Categories", group rows under native **category section headers** that
  include each category's count; a single selected category stays a flat list.
- Render a declared screenshot as a **fixed-size thumbnail** (fills a fixed frame,
  tap to enlarge) so it can never change a row's height; keep the existing
  enlarge sheet.
- Keep Discover's search, sort, store/category filters, notice banner,
  install-trust sheet, and lazy header/freshness loading behavior unchanged.
- Remove the now-unused adaptive grid, grid card, category-header, and
  grid-band preview views; keep the model's preview-image host policy intact.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `library-session-integrity`: the "Discover card actions remain readable"
  requirement becomes row-based, and a new requirement pins Discover's uniform
  row presentation (same-height rows regardless of screenshots) and fixed-size
  screenshot thumbnails.

## Impact

- `Sources/VeeUI/PluginBrowserView.swift`: `DiscoverContentView.detail` switches
  from `LazyVGrid` to a grouped `Form`; `PluginCard`/`CategorySectionHeader`/
  `SkeletonPluginCard`/`PluginPreviewPhaseView` are replaced by a row view, a
  native section header, a skeleton row, and a fixed-size thumbnail view.
- `Tests/VeeUITests/PluginPreviewPhaseViewTests.swift`: retargeted from the
  120pt grid band to the fixed thumbnail frame.
- No changes to `PluginBrowserModel`'s API, to `VeeCatalog`, to the plugin
  format, or to any dependency. Existing model-level tests (search stability,
  preview-image host policy) are unaffected and stay green.
