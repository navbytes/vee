## 1. Discover row list

- [x] 1.1 Add an internal `PluginCatalogRow` mirroring the Installed row's structure: category tile, title, optional store chip, author, description, ranked badge row, and a trailing area with the primary action (Install, or Installed/provenance + Update/Reinstall) plus a View source link
- [x] 1.2 Reserve a minimum height for the row's metadata block so a row does not grow under the cursor when its lazily-fetched header lands
- [x] 1.3 Replace the three `LazyVGrid` branches in `DiscoverContentView.detail` with grouped `Form` sections drawing the row; delete `PluginCard`, `gridColumns`, and `CategorySectionHeader`
- [x] 1.4 Add a row-shaped `SkeletonPluginRow` for the loading state and delete `SkeletonPluginCard`; keep the per-row `loadHeader`/`loadLastUpdated` tasks and the sort/search sweeps unchanged

## 2. Screenshot thumbnail

- [x] 2.1 Add `PluginThumbnail`, rendering every `AsyncImagePhase` at one fixed frame (filled, clipped, rounded) and opening the existing `PluginScreenshotSheet` on tap
- [x] 2.2 Place the thumbnail in the row only when `previewImageURL(for:)` is non-nil, sized below the metadata block so rows with and without a screenshot are equal height; delete `PluginPreviewPhaseView`

## 3. Category grouping and states

- [x] 3.1 In All Categories, group rows into `Section`s whose header shows the category name and its count, replacing `CategorySectionHeader`
- [x] 3.2 Keep the single-category, empty, error, and loading states intact and visually consistent with the Installed tab

## 4. Tests

- [x] 4.1 Retarget `PluginPreviewPhaseViewTests` to the thumbnail: every phase renders at the declared fixed width and height
- [x] 4.2 Add a regression test that renders `PluginCatalogRow` at a fixed width with and without a declared preview image and asserts the two heights are equal, and that the row is at least the thumbnail height
- [x] 4.3 Confirm the existing model-level suites (`CatalogSearchStabilityTests`, `PluginPreviewImageTests`, `PluginBrowserModelTests`) pass unchanged

## 5. Verification and review

- [x] 5.1 Run `swift build && swift test && swiftlint lint --strict`
- [x] 5.2 Add an `[Unreleased]` changelog entry for the Discover row-list redesign
- [x] 5.3 Visually verify Discover at the Library window's default and minimum widths, with and without screenshots, and with one and multiple stores
