## Context

See `proposal.md` - Why for the visual failure this addresses. The relevant
current state:

- `DiscoverContentView.detail` (`Sources/VeeUI/PluginBrowserView.swift:921`)
  renders three `LazyVGrid` branches (skeleton, sectioned, flat) using one
  adaptive column spec, and every branch draws `PluginCard`.
- `PluginCard` (line 1136) is grid-shaped: a header `HStack` (tile + text +
  fixed-size action column) over an optional full-width 120pt screenshot band
  (`PluginPreviewPhaseView`).
- The Installed tab (`LibraryView.swift:195`) already presents plugins as
  `Form { Section { ManagerRow } }.formStyle(.grouped)` rows
  (`PluginManagerView.swift:231`), which is the layout Discover should match.
- `PluginBrowserModel` already exposes everything a row needs
  (`title/summary/author/storeName/trustLevel/freshness/lastUpdatedDate/
  isInstalled/updateStatus/provenanceStatus/sourceURL/previewImageURL`) and
  drives lazy per-entry loading through `loadHeader`/`loadLastUpdated`.
- Constraint: search and sort must not depend on how much of the list has been
  loaded (pinned by `CatalogSearchStabilityTests` and enforced by the model's
  `sortKey`); the row list must keep driving the same lazy loads rather than
  forcing headers eagerly.

## Goals / Non-Goals

**Goals:**

- Discover renders as uniform, full-width rows that are the same height whether
  or not an entry declares a screenshot.
- Install/Update/Reinstall and View source are never truncated or wrapped.
- Discover matches the Installed tab's grouped-list look and native section
  headers.
- Screenshots stay available as a fixed-size thumbnail that opens the existing
  enlarge sheet.
- Search, sort, store/category filters, notice banner, install-trust sheet, and
  lazy header/freshness loading behave exactly as before.

**Non-Goals:**

- No change to `PluginBrowserModel`'s API, to `VeeCatalog`, to search/sort
  semantics, or to the preview-image host policy.
- No change to the install trust flow or the (dead-but-compiling) standalone
  `PluginBrowserView` beyond it continuing to compile.
- No new dependencies; the layout uses only SwiftUI already in the target.

## Decisions

**1. Use a grouped `Form`, not `List`.**
`Form { Section { ... } }.formStyle(.grouped)` is exactly what
`InstalledPluginsList` uses, so the two library tabs become the same surface.
A `List` with `.inset`/`.sidebar` styling would look close but diverge from the
sibling tab for no benefit. `ManagerRow` already proves interactive controls
(`Menu`, `Toggle`, `NavigationLink`) work inside a grouped Form row.

**2. Replace `PluginCard` with a single `PluginCatalogRow`, mirroring
`ManagerRow`'s structure.**
Leading `PluginTile`; a text `VStack` (title, optional store chip, author,
description, ranked badge row); a trailing area with the screenshot thumbnail,
the primary action (Install, or Installed/provenance + Update/Reinstall), and a
"View source" link. Because the row is full width, the badge row and the action
controls no longer compete for the same ~300pt, which is what squeezed the
action column before. The existing badge ranking (deprecated → trust → surface →
freshness) is preserved unchanged.

**3. Screenshots become a fixed-size thumbnail, replacing the 120pt band.**
A new `PluginThumbnail` draws every `AsyncImagePhase` at one fixed frame
(`.fill` + clipped + rounded) and is the tap target for the existing
`PluginScreenshotSheet`. The thumbnail height is chosen below the height of the
text block, and the row is given a fixed minimum height, so a row with an image
and a row without are identical in height. Alternative — dropping screenshots
from Discover — was rejected: it removes a shipped feature (`<xbar.image>`) to
fix a layout bug.

**4. Category grouping uses native `Section` headers.**
In All Categories, each category is a `Section` whose header shows the category
name and its entry count; a single selected category stays one flat `Section`.
`CategorySectionHeader` is deleted. This keeps the grouping/sort-within-section
logic on the model (`sectionedEntries`) and removes custom header chrome.

**5. Keep the existing lazy loading and skeleton.**
Each row keeps `.task { await model.loadHeader(for: entry) }`; the sort and
search `.task(id:)` sweeps are unchanged. The loading state becomes a
`SkeletonPluginRow` shaped like a real row, inside a `Section`, replacing the
grid-shaped `SkeletonPluginCard`. The metadata block reserves a minimum height
(the old card used `.frame(minHeight: 84)`) so a row does not grow under the
cursor as its header lands.

**6. Build order.** Do the view swap and helpers in one file for cohesion
(`PluginBrowserView.swift`), then retarget the preview test, then run the gate
and update the changelog.

## Risks / Trade-offs

- **Interactive controls inside a Form row.** A thumbnail button plus a link
  plus an install button in one row can fight row-level selection. → Mirror
  `ManagerRow`, which already embeds a `Menu`/`Toggle`/link in a Form row; use
  `.buttonStyle(.plain)` for the thumbnail and an explicit `.contentShape`.
- **Losing the large screenshot band** reduces visual richness. → Accepted; the
  thumbnail still opens the full-size sheet, and rows read more cleanly.
- **Header arrives after first paint** and can change a row's height. → Reserve
  a minimum height for the metadata block, as the card did.
- **One image fetch per visible row.** → Unchanged from today: `AsyncImage` in a
  lazy container, shared `URLSession` cache, no eager fetch.
- **Emphasized install button in a Form row.** A `.borderedProminent` button
  inside a grouped Form can be visually heavy. → Keep `.controlSize(.small)` and
  verify against a rendered row; fall back to `.bordered` if it overwhelms the
  row.
