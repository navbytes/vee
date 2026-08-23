## 1. The authored contract

Nothing user-visible changes here. The acceptance bar is that `params.json`
round-trips: every key the parser recognises appears exactly once, and every key
in the file is one the parser recognises.

- [ ] 1.1 Write `docs/api/params.json`. One record per menu-line parameter:
      `key`, `aliases` (e.g. `md`/`markdown`, `shell`/`bash`), `type`, `grammar`
      (the value's shape, e.g. `min,max,value`), `default`, `group`
      (`rendering` / `behavior` / `images` / `symbols` / `charts` / `controls`),
      `appliesTo`, `summary`, and `section` (the anchor that explains it).
      Seed the prose from `plugin-authoring.md`'s existing table so no wording
      is lost.
- [ ] 1.2 Record the documented constants alongside: `chart.maxSegments`,
      `chart.sizeLimit`, `chart.defaults` per kind, and the widget sparkline's
      point cap — each with the Swift symbol it mirrors.
- [ ] 1.3 Record the chart matrix input: for each of the six kinds
      (`sparkline`, `progress`, `pie`, `donut`, `stackedbar`, widget `gauge`),
      its spelling in each of the three entry paths, which knobs apply, and
      whether it opens a popover on click. `chartw=full` is `stackedbar`-only;
      pie and donut take one dimension that sizes both.

## 2. The generator

- [ ] 2.1 Add `docs/scripts/build_reference.py`, standard library only, matching
      `build_guide.py`'s conventions. Emits Markdown partials into
      `docs/_content/_generated/`. Supports `--check`, exiting non-zero when a
      partial is stale, for CI.
- [ ] 2.2 Emit `params-table.md` — the full parameter table, grouped, replacing
      the hand-written table in `plugin-authoring.md`.
- [ ] 2.3 Emit `chart-matrix.md` — six kinds by three entry paths, with knobs,
      limits, and popover behavior.
- [ ] 2.4 Teach `build_guide.py` to expand a partial include directive when
      rendering `_content`, so the partials land in the published pages and in
      `llms-full.txt` without a second mechanism.

## 3. The Charts page

- [ ] 3.1 Add `docs/_content/charts.md`: what a chart is on each surface, the
      generated matrix, then per-kind detail linking into the existing prose in
      `plugin-authoring.md` and `widgets.md`. Move no prose — link to it.
- [ ] 3.2 Add its `PAGES[]` entry in `build_guide.py` (nav label, title, and the
      SEO description that also becomes its `llms.txt` line), the sidebar, and
      the guide index card grid.
- [ ] 3.3 Cross-link both ways: `plugin-authoring.md`'s chart sections and
      `widgets.md`'s gauge/sparkline nodes point at `charts.md`.

## 4. Guards

The point of the change. Each of these fails CI on a drift that ships silently
today.

- [ ] 4.1 Repoint `check_params.py`'s third surface at `params.json`; delete its
      Markdown-table scraper. The parser and linter scrapers are unchanged, as
      is the `EXCEPTIONS` mechanism and its `paramN` entry.
- [ ] 4.2 Add the constants check: scrape the `public static let` declarations
      named in 1.2 from `ChartParams.swift` and compare against `params.json`,
      failing with the symbol, both values, and the file each came from.
- [ ] 4.3 Add `docs/scripts/check_links.py` — resolve every repository-relative
      and same-site link in `docs/_content/**` and the root Markdown files,
      failing on a target that does not exist. External URLs are out of scope.
- [ ] 4.4 Wire `build_reference.py --check` and `check_links.py` into
      `lint.yml`'s `docs` job, each with the comment convention the existing
      four steps use — what drifts, and what shipped because it was unguarded.

## 5. Fix what is already broken

- [ ] 5.1 `docs/_content/json-output.md:143` — `plugins/examples/json-demo.ts`
      is now `plugins/typescript/examples/json-demo.ts`.
- [ ] 5.2 `docs/_content/plugin-authoring.md:704` — `tree/main/examples` is now
      `tree/main/plugins/showcase`.
- [ ] 5.3 `CONTRIBUTING.md:207` — `plugins/examples/` is now
      `plugins/typescript/examples/`; while there, describe the current
      `plugins/` layout (`typescript` / `python` / `go` / `showcase` /
      `fixtures`).
- [ ] 5.4 `docs/llms.txt`'s example-plugins link is generated from
      `build_guide.py`'s footer — fix it at the source, not in the output.
- [ ] 5.5 Confirm `check_links.py` from 4.3 fails on each of these before the
      fix and passes after.

## 6. Deduplicate the SDK docs

- [ ] 6.1 Cut `## API` and `## Widget cards` from
      `plugins/typescript/README.md`, `plugins/python/README.md`, and
      `plugins/go/README.md`; each gains one line pointing at the cross-language
      table in the published SDK guide.
- [ ] 6.2 Keep per-language content: requirements, layout, hello world, tests.
- [ ] 6.3 Verify `sdk.md`'s cross-language table covers every method the three
      cut sections named, adding any it was missing.

## 7. Discoverability fixes

- [ ] 7.1 `build_guide.py:404` — collect `h3` as well as `h2` into the "On this
      page" nav, nested under their parent. `### Share charts` must appear.
- [ ] 7.2 Regenerate the site and the search index; confirm searching "pie",
      "donut", and "chart options" reaches `charts.md`.

## 8. Verify

- [ ] 8.1 Full `lint.yml` docs job green: guide freshness, params parity,
      constants, schemas, links, search index.
- [ ] 8.2 Break one thing per guard on purpose — change `maxSegments` in Swift,
      add a parser case, break a link — and confirm each fails with a message
      naming the file and the disagreement.
- [ ] 8.3 Answer the question that started this from the published site alone:
      what chart kinds exist, and what options does each take.
