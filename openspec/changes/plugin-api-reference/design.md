# Design

## Decision 1 — `params.json` is authored, not generated from Swift

The alternative was a `vee api --json` command making the Swift parser the sole
source of truth. It is the better end state and it is deferred, because the
switch in `LineParser.mapParams` carries no metadata beyond the key: there is no
type, no default, no group, and no prose to emit. Producing the reference from
Swift means first writing that metadata into forty parser cases, which is a
change to the parser's shape in service of documentation.

Authoring the file first costs one hand-maintained list — which
`check_params.py` already guards, and will continue to — and proves what fields
the reference actually needs before any of them are carved into Swift. The
migration stays open: `params.json`'s schema is what a future `vee api --json`
would emit.

The parity check is what makes the hand-maintained list safe, and #98 made that
argument considerably stronger: `check_params.py` now holds *six* surfaces in
agreement — the parser, the linter, and each of the three SDKs separately —
because fifteen parameters had gone missing from all three SDKs at once while
the old three-way triangle passed. A seventh hand-maintained list is not a new
risk in that design; it is the one surface in it that a human is supposed to
write, and it is the only one that can carry a type, a default, or a sentence.

This change points the documentation surface at structured data instead of a
Markdown table, which makes the check simpler, not more elaborate.

## Decision 2 — Constants are verified, not just names

`check_params.py` today proves that the docs *mention* `chartw`. It cannot prove
the docs are right that the default is 24 points and the range is 8–200. Those
numbers live in `ChartParams.swift` as `static let`s and in
`plugin-authoring.md` as English, and nothing connects them.

The check gains a small table of documented constants — Swift symbol to
`params.json` path — and compares them. Scope is deliberately the constants the
docs actually state: `ChartParams.maxSegments`, `sizeLimit`,
`defaultCircleSide`, `defaultBarWidth`, `defaultBarHeight`, and the widget
sparkline's 256-point cap. Not every constant in the module; only the ones a
reader is told about, because only those can mislead.

This reuses the regex-against-Swift-source approach `check_params.py` already
takes for the parser switch. That approach is unlovely and it is the established
one in this repo; inventing a second mechanism for the same job would be worse
than extending the first.

## Decision 3 — The Charts page is an index, not a rewrite

`plugin-authoring.md`'s `## Rich inline charts` and `### Share charts` sections
are good writing and they stay where they are. The failure is that nothing lists
the chart kinds side by side, so a reader has to already know a kind's name to
find its prose.

`charts.md` is therefore a routing page built around one generated matrix — six
chart kinds down, three entry paths across (text protocol, JSON menu output,
widget card) — plus the knobs, limits, and popover behavior per kind, each row
linking into the section that explains it. It adds one navigable page and moves
no prose, so no existing anchor breaks.

The matrix is generated from `params.json` rather than typed, because it is
exactly the cross-product that goes stale: `sparkline` is spelled three ways
across the three entry paths, `chartw=full` applies to `stackedbar` alone, and
pie/donut take no width and height independently — a circle's one declared
dimension sizes both.

## Decision 4 — Generated Markdown partials, not a generated site section

`build_reference.py` writes Markdown into `docs/_content/_generated/`, and pages
include those partials. It does not emit HTML and knows nothing about the site
template.

This survives the Starlight migration proposed separately: a Markdown partial is
input to any renderer, so the generator is written once and does not need
porting. Had the tables been emitted as HTML by `build_guide.py`, migrating
would mean rewriting them as an Astro integration.

## Decision 5 — SDK READMEs shrink rather than disappear

Each per-language README keeps what is genuinely per-language — requirements,
layout, hello world, how to run its tests — and drops `## API` and
`## Widget cards`, which restate `sdk.md`'s cross-language table in one
language's spelling. Three copies of the same method list is where the drift
risk is; three copies of `npm test` versus `go test ./...` is not.

Deleting the READMEs entirely was rejected: `plugins/typescript/` is a directory
someone lands in from GitHub, and an empty directory with a pointer elsewhere is
worse than a short page that orients them.

## Decision 6 — Deprecation is a field, not a footnote

#98 introduced the format's first deprecations: `trackcolor=` superseded by
`progresstrackcolor=`, both parsed, with removal scheduled for the next major
version. There will be more, and a reference that renders a superseded
parameter identically to a current one teaches new authors the old spelling.

So `deprecated` and `replacedBy` are fields on the parameter record, and the
generated table marks a deprecated row and names its replacement. This also
gives the deprecation exactly one home: `vee lint` warns at authoring time,
`LineParameterKeys` keeps parsing it, and the reference says so — rather than a
prose aside in one page that the next reorganisation loses.

## Risks

- **`params.json` becomes a fourth surface to forget.** Mitigated by the parity
  check, which fails CI on any disagreement — the same guard that has held the
  existing three surfaces together since #93.
- **Regex-scraping Swift constants is brittle to formatting.** A reformat of
  `ChartParams.swift` could break the check. It fails loudly rather than
  silently passing, which is the correct direction for a guard, and the scraped
  declarations are `public static let` lines that SwiftLint keeps stable.
- **The link checker may be noisy on external URLs.** Scope it to repository-
  relative and same-site links, which are the ones this project breaks; external
  link rot is a different problem with a different cadence.
