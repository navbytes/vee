## Why

A row's inline graphic is sized by one of three parameter pairs depending on
which graphic it is: `progressw=`/`progressh=`, `sparklinew=`/`sparklineh=`, or
`chartw=`/`charth=`. Six names for one concept, and a seventh and eighth would
follow the next accessory type.

They are also not discoverable from each other: a plugin author who learned
`progressw=full` has no reason to guess that a stacked bar wants `chartw=full`,
and `stackedbar=` being sized by a parameter named `chart*` is a papercut every
author hits once.

The redundancy became strictly unnecessary with `menu-surface-model`: a row
resolves to **exactly one** display graphic (`MenuTree.accessory`, precedence
progress → sparkline → chart). There is never more than one thing on a row to
size, so per-accessory names distinguish between cases that cannot co-occur.

A live `slider=` cannot be sized at all today — its width is a hard-coded
constant — which is the same gap arriving again for a fourth accessory type.

## What Changes

- **Add `accessoryw=` / `accessoryh=`**, sizing whichever accessory the row
  resolves to. Named to pair with the existing `accessory=leading|trailing`
  placement parameter, so placement and sizing read as one family — and to stay
  unambiguous beside `size=` (font size) and `length=` (text truncation).
- **`accessoryw=` newly applies to `slider=`**, replacing a hard-coded width.
- **The six old spellings keep working**, each emitting a deprecation
  diagnostic naming its replacement. This follows the `trackcolor=` precedent
  already in the parser; it costs a few lines and avoids silently changing what
  published plugins render.
- **JSON output gains `accessoryWidth` / `accessoryHeight`**, with
  `progressWidth`, `sparklineWidth`, `chartWidth` and their height counterparts
  deprecated the same way.
- **Defaults stay per-accessory.** There is no single sensible default — a
  sparkline is 90×20, a gauge 120×6, a pie a 24pt circle, a stacked bar 110×12 —
  so `accessoryw=` means "override this accessory's own default", not "adopt a
  shared one".
- **`full` keeps its existing meaning and its existing refusal.** It stretches
  to the row's leftover width, and is still rejected on `pie=`/`donut=` with a
  diagnostic, because a circle can only fill width by growing the row.

Not in scope: changing any default, any geometry, or how `full` is computed.

## Capabilities

### New Capabilities

- `accessory-sizing`: one parameter pair sizes whichever inline accessory a row
  carries — gauge, sparkline, chart, or control — with per-accessory defaults
  and a documented deprecation path off the per-family names.

## Impact

**Plugin format** — the user-visible surface:
- `docs/api/params.json` is the source of truth; `docs/scripts/build_reference.py`
  regenerates `docs/_content/_generated/params-table.md` and `chart-matrix.md`.
- Prose pages: `charts.md`, `plugin-authoring.md`, `json-output.md`, `sdk.md`,
  `migrating-from-swiftbar.md`.
- `docs/schemas/json-output.schema.json`.
- `context7.json` rules and `docs/_content/writing-plugins-with-an-llm.md` — the
  text an LLM authoring a plugin reads.

**SDKs** — all three expose these as typed options, and their examples use them:
- `plugins/typescript/vee.ts` + `examples/`, `plugins/python/vee.py` +
  `examples/` + `README.md`, `plugins/go/vee.go`.
- `Sources/VeeCLI/EmbeddedSDK.swift` vendors the SDK text `vee sdk` emits.
- `plugins/fixtures/controls.txt` is golden output compared across all three, so
  it changes in lockstep or the SDK conformance tests fail.
- `plugins/showcase/` plugins that size an accessory.

**Parser and renderers:**
- `LineParser`, `LineParameterKeys`, `JSONOutputParser`, `LineParams`,
  `ChartParams`.
- `ProgressMenuItemView`, `SparklineMenuItemView`, `CategoryChartMenuItemView`,
  `MenuBuilder`, `VeeUI/MenuRowAccessory`.

**Risk:** the golden fixtures make SDK drift a test failure rather than a
surprise, and the deprecation path means no published plugin changes behaviour.
The realistic failure mode is a doc or example missed rather than a runtime
break — hence regenerating rather than hand-editing every table, and
`build_reference.py --check` in CI.
