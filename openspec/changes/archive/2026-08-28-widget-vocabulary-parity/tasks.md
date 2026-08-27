# Tasks: widget-vocabulary-parity

## 1. Schema and parser

- [x] 1.1 `WidgetNode`: add the `chart` leaf (`kind`, `values`, optional
  `labels`, optional `colors`) with wire-order `CodingKeys`
- [x] 1.2 `WidgetCardItem`: add optional `url` and `shortcut`
- [x] 1.3 `WidgetCardParser`: clamp chart values (drop non-finite, cap segment
  count), unknown kind → diagnostic + drop the leaf while the card survives;
  sanitize item `url`/`shortcut` — unit tests for each degradation

## 2. Rendering

- [x] 2.1 Widget chart view (Swift Charts: pie/donut via sectors, stacked bar)
  in `WidgetExtension`, wired as a `WidgetNodeView` case, honoring `families`
  subtraction and `style`
- [x] 2.2 Tappable `list`/`board` rows: `Link` for `url`, App-Intent button via
  the existing `WidgetActionRequest` path for `shortcut`; undeclared items stay
  inert

## 3. Parity guard

- [x] 3.1 `WidgetParity` in `VeePluginFormat`: exhaustive dispositions
  (`.supported` / `.excluded(reason:)`) over every `MenuAccessory` case and the
  dispatchable action kinds — a new case must fail compilation until answered
- [x] 3.2 `docs/design/surface-parity.md`: feature × surface ledger with a
  generated dispositions table; unit test regenerates the table from
  `WidgetParity` and fails when the file is stale (fixture-drift pattern)
- [x] 3.3 Repo `CLAUDE.md` (new): the always-on rule — touching `LineParams`,
  `MenuAccessory`, `WidgetNode`, or `WidgetCard` requires updating
  `WidgetParity` and the ledger

## 4. Authoring surface

- [x] 4.1 TypeScript SDK: `chart` node builder and item `url`/`shortcut`, plus
  a fixture example for each
- [x] 4.2 Python SDK: same additions
- [x] 4.3 Go SDK: same additions
- [x] 4.4 JSON card schema and docs-site widget page updated, exclusions noted
  with reasons

## 5. Verify

- [ ] 5.1 SPM tests green (parser, parity, fixtures); build, sign, and run the
  widget extension on this Mac per the recorded extension-build lesson; visual
  QA of charts at all three families, item taps, and malformed-chart
  degradation
  - Done headlessly: `swift build`, `swift test` (1187 XCTest, 0 failures),
    `swiftlint lint --strict` (0 violations), CI's `xcodebuild … CODE_SIGNING_
    ALLOWED=NO build`, an ad-hoc **signed** build whose `.appex` passes
    `codesign --verify --deep --strict` with unchanged entitlements, all three
    SDK suites, `check_params.py`, `check_schemas.py`, `check_links.py`,
    `build_reference.py --check`, `embed_sdk.py --check`.
  - **Remaining — needs a human at the machine.** Per lesson `J1Q1GZ`, widget,
    gallery and Control Center surfaces are drawn by system processes that
    cannot be screenshotted by an agent, and placed widgets must be removed and
    re-added to pick up a new extension binary. So: install this build over
    `/Applications/Vee.app` (back up the existing 0.2.0 first), `lsregister -f`,
    re-add the tile, and eyeball (a) a `chart` leaf at small/medium/large —
    pie, donut and stacked bar, legend present on medium/large and absent on
    small, palette colors in both light and dark appearance; (b) tapping a
    `list` row with `url` and a `board` cell with `shortcut`; (c) a malformed
    chart (unknown `kind`, non-finite/negative values, >8 segments) degrading
    without taking the card down.
