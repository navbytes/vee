## Why

The docs cannot answer "what charts does Vee support, and what options does each
one take". Building the answer took reading four source files —
`ChartParams.swift`, `JSONOutputParser.swift`, `widget-card.schema.json`, and
`LineParameterKeys.swift` — because the information is written down five times
and indexed zero times:

- `plugin-authoring.md`'s flat parameter table, where `pie` sits between
  `progress` and `accessory` as one row among forty
- its `## Rich inline charts` prose section
- its `### Share charts` subsection, which the generated "On this page" nav
  does not list at all: `build_guide.py:404` collects `h2` only
- `widgets.md`, describing a *different* chart vocabulary (`gauge` nodes,
  `sparkline` nodes, the `trend` template) with no cross-reference either way
- the SDKs' own doc comments

A reader wanting "the chart options" has no page to land on. There is no list of
the chart kinds anywhere in the published docs.

The numbers are worse than the prose. `ChartParams.swift` fixes `maxSegments =
8`, `sizeLimit = 8...200`, and defaults of `24` / `110×12`, and the fold-into-
"Other" rule that keeps a folded total honest. Those reach the reader only as
hand-typed prose in one table cell — nothing fails when Swift changes and the
sentence does not. That is the same failure `check_params.py` was built to stop
for parameter *names*, left unguarded for parameter *values*.

The `plugins/` reorganisation in `f7367b0` has already demonstrated the gap: it
broke four documented links and CI reported nothing, because no check looks at
links. #98 touched `json-output.md` for other reasons and repaired one of them
incidentally; three are still broken on `main` today — `llms.txt:36`,
`plugin-authoring.md:721`, and `CONTRIBUTING.md:207`. A defect that survives a
1,500-line pass over the same files is not one review catches.

## What Changes

- Add `docs/api/params.json`: one authored record per menu-line parameter — key,
  aliases, type, value grammar, default, group, what it applies to, a one-line
  summary, and the section that explains it. Chart constants
  (`maxSegments`, `sizeLimit`, the per-kind defaults) are recorded as data
  beside the parameters that carry them.
- Add `docs/scripts/build_reference.py`, emitting Markdown partials from that
  file: the parameter table `plugin-authoring.md` writes by hand today, and the
  chart matrix that does not exist today.
- Add a `Charts` guide page — the one index for every chart surface across all
  three entry paths (text protocol, JSON menu output, widget card), listing the
  six chart kinds with their value grammar, applicable knobs, limits, and
  click-to-popover behavior.
- Repoint `check_params.py`'s *documentation* surface at `params.json` instead
  of scraping a Markdown table with a regex, and add a check of the recorded
  chart constants against `ChartParams.swift`. #98 grew that script from three
  surfaces to six — parser, linter, and each of the three SDKs separately — and
  all of those stay exactly as they are. Only the surface that reads prose
  changes, and numeric drift starts failing CI.
- Collect `h3` headings into the generated "On this page" nav, so subsections
  like `### Share charts` are reachable.
- Fix the four links `f7367b0` broke, and add a link check to `lint.yml` so the
  next reorganisation cannot ship the same way.
- Cut the duplicated `## API` and `## Widget cards` sections from the three
  per-language SDK READMEs, leaving install, layout, and a link to the one
  cross-language table in `sdk.md`.

**Deliberately not in this change:** generating `params.json` from Swift via a
`vee api --json` command. That is the right end state — it would retire
`LineParameterKeys` and the last regex scraper — but it means adding type,
default, and grouping metadata to some forty parser cases, which is a Swift
change deserving its own proposal. This change proves the schema first.

Also not in this change: TypeDoc / pdoc / `pkg.go.dev`. The three SDKs are
byte-identical by design — #98 made that structural by checking each one as its
own surface — so one cross-language table serves better than three generated
sites that would each describe a third of the same contract. Note that #98 gave
`plugins/go/go.mod` the real module path `github.com/navbytes/vee/plugins/go`,
so `pkg.go.dev` will serve the Go SDK automatically on the next tag. That is
free and worth linking to; it is not a reason to generate the other two.

## Capabilities

### Modified Capabilities

- `plugin-docs-integrity`: gains requirements covering a machine-readable
  parameter reference as the generated source of the published table, the
  verification of documented constants against the implementation that defines
  them, and the reachability of documented links.

## Impact

- **`docs/api/params.json`** (new) — the authored contract.
- **`docs/scripts/build_reference.py`** (new) — the generator.
- **`docs/scripts/check_params.py`** — its documentation surface reads
  `params.json`; gains the constants check. The Markdown-table scraper is
  deleted; the parser, linter, and three SDK surfaces #98 added are untouched.
- **`docs/scripts/build_guide.py`** — one new `PAGES[]` entry; `toc()` collects
  `h3`.
- **`docs/_content/`** — new `charts.md`; `plugin-authoring.md`'s table becomes
  generated; `sdk.md` keeps the cross-language table.
- **`plugins/{typescript,python,go}/README.md`** — lose their duplicated API
  sections.
- **`.github/workflows/lint.yml`** — one new link-check step, joining the guards
  #98 left at six.
- **No Swift changes.** No parser, CLI, or SDK behavior changes.
