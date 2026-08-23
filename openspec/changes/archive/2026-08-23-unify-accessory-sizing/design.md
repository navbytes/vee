## Context

See `proposal.md` — Why. The constraints that shape the approach:

- **A row carries exactly one display graphic.** `MenuTree.accessory` resolves
  progress → sparkline → chart and returns one, so per-accessory size parameters
  distinguish cases that cannot co-occur. This is what makes the collapse safe;
  it was not obviously safe before `menu-surface-model` landed.
- **Defaults genuinely differ** — sparkline 90×20, gauge 120×6, pie/donut a 24pt
  circle, stacked bar 110×12 — and live in `VeePluginFormat` precisely so the
  AppKit and SwiftUI renderers cannot disagree.
- **Three SDKs and a golden fixture set** (`plugins/fixtures/`) are compared
  byte-for-byte, so any name change must land in all four together or the
  conformance tests fail. That is a feature: it makes drift a test failure.
- **The docs are generated.** `docs/api/params.json` is authored; the tables are
  produced by `build_reference.py`, with `--check` guarding staleness.
- **`trackcolor=` sets a precedent** for keeping a superseded spelling working,
  already in `LineParser`.

## Goals / Non-Goals

**Goals:**

- One width/height pair for every inline accessory, including `slider=`.
- No published plugin changes what it draws.
- One place a renderer reads a size from, per accessory kind.

**Non-Goals:**

- Changing any default, any geometry, or how `full` is computed.
- Sizing anything that is not an inline accessory. `size=` (font) and `length=`
  (truncation) stay exactly as they are; not colliding with them is half the
  reason for the chosen name.
- A general layout system. This is one width and one height.

## Decisions

### D1 — `accessoryw=` / `accessoryh=`, not `width=` / `height=`

The name pairs with `accessory=leading|trailing`, which already exists, so
placement and sizing share a vocabulary.

*Alternative considered — `width=`/`height=`.* Shorter and the first instinct.
Rejected because a row already carries `size=` (font size) and `length=` (text
truncation): a bare `width=` sitting beside them invites "width of the row?",
and a generic name is hard to reclaim if something else ever needs it. The
ambiguity is permanent; the extra nine characters are typed once.

### D2 — Fan out at parse time, don't restructure the params

`accessoryw=`/`accessoryh=` are parsed once and then applied to whichever of
`ProgressParams` / `SparklineStyle` / `ChartParams` the row actually built.
Those types keep their existing `width`/`height`/`isFullWidth` fields and their
`effectiveWidth`/`inlineSize` accessors.

*Alternative considered — a single `LineParams.accessorySize` that every
renderer reads.* Cleaner on paper, but it moves per-kind clamping and the
circle's "either dimension sizes both" rule out of the types that own them, and
touches every geometry call site for no user-visible gain. The fan-out keeps the
diff in the parser, where the change actually is.

### D3 — Old spellings stay, with a deprecation diagnostic

Each of the six emits a `warning` naming its replacement. `trackcolor=` already
works this way, so this is the codebase's existing answer to the question rather
than a new policy.

The user's instruction was that a rename is acceptable because few plugins use
these. That justifies changing the *canonical* name; it does not by itself
justify silently changing what an existing plugin renders, and the alias costs
six `case` labels. Deleting them later is a one-line-per-name revert.

Where both are present the new parameter wins, so migration needs no flag day.

### D4 — Defaults stay per-accessory

`accessoryw=` overrides the accessory's own default rather than introducing a
shared one. There is no width that suits a 6pt-tall gauge and a 24pt circle,
and inventing one would change every unsized plugin's appearance — the exact
thing this change is not for.

Consequence for the docs: the generated parameter table cannot print a single
`default` for `accessoryw=`. It prints "the accessory's own default" and links
to the per-kind table, which `chart-matrix.md` already is.

### D5 — `accessoryh=` is ignored for controls

A slider's height is its control size, not a free measurement, and a toggle has
no meaningful height. Width applies to controls; height applies to the
accessories with a real one. Ignoring is deliberate and silent — an author who
sets a height on a slider has expressed nothing harmful, and a diagnostic for it
would be noise.

### D6 — `full` semantics untouched

Still "the row's leftover width", still computed by
`ProgressBarLayout.stretchedWidth`, still refused on `pie=`/`donut=` in
`ChartParams` so all three renderers inherit the refusal. The only change is the
name of the parameter that carries it.

## Risks / Trade-offs

- **A doc or example missed** → The realistic failure, since the surface is 39
  files. Mitigated by generating the tables from `params.json` rather than
  editing them, running `build_reference.py --check`, and grepping for every old
  spelling as an explicit final task.
- **SDK drift** → The golden fixtures compare all three byte-for-byte, so this
  fails a test rather than shipping. Fixture updates must be reviewed as
  intent, not regenerated blindly.
- **Two names for one thing, indefinitely** → The deprecation path's cost.
  Accepted; the alternative is breaking published plugins for a cosmetic gain.
  Revisit removing the aliases at the next major version.
- **`accessoryw=` on a row with no accessory is silent** → Consistent with how
  `progressw=` on a row with no `progress=` already behaves, and the linter is
  where an unused parameter should be reported if it ever should be.

## Migration Plan

1. Parse and fan out the new parameters; add the deprecation diagnostics. Every
   existing test stays green — this step changes no output.
2. Wire `accessoryw=` into the slider (the one genuinely new capability).
3. JSON output: the new fields plus deprecation of the old.
4. `params.json`, regenerate the partials, then the prose pages, the schema, and
   the LLM-facing text.
5. All three SDKs, their examples, the vendored `EmbeddedSDK`, and the golden
   fixtures together.
6. Grep for every old spelling and confirm each remaining hit is deliberate
   (deprecation handling, tests asserting the alias still works, changelog).

Steps 1–3 are independently revertible. Step 5 is the one that must land atomically.
