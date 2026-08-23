## 1. The authored contract

Nothing user-visible changes here. The acceptance bar is that `params.json`
round-trips: every key the parser recognises appears exactly once, and every key
in the file is one the parser recognises.

- [x] 1.1 Write `docs/api/params.json`. One record per menu-line parameter —
      52 of them as of #98: `key`, `aliases` (e.g. `md`/`markdown`,
      `shell`/`bash`), `type`, `grammar` (the value's shape, e.g.
      `min,max,value`), `default`, `group` (`rendering` / `behavior` /
      `images` / `symbols` / `charts` / `controls`), `appliesTo`, `summary`,
      and `section` (the anchor that explains it). Seed the prose from
      `plugin-authoring.md`'s existing table so no wording is lost.
- [x] 1.1a Carry deprecation as data: `deprecated` and `replacedBy`. #98
      deprecated `trackcolor=` in favour of `progresstrackcolor=` and scheduled
      its removal for the next major version, and `vee lint` already surfaces
      it. The reference must be able to say so without a prose aside, and the
      generated table must render a deprecated parameter differently from a
      current one.
- [x] 1.2 Record the documented constants alongside: `chart.maxSegments`,
      `chart.sizeLimit`, `chart.defaults` per kind, and the widget sparkline's
      point cap — each with the Swift symbol it mirrors.
- [x] 1.3 Record the chart matrix input: for each of the six kinds
      (`sparkline`, `progress`, `pie`, `donut`, `stackedbar`, widget `gauge`),
      its spelling in each of the three entry paths, which knobs apply, and
      whether it opens a popover on click. `chartw=full` is `stackedbar`-only;
      pie and donut take one dimension that sizes both.
- [x] 1.3a Include the knobs #98 added, and mind that they do not follow the
      `chart*` naming: the sparkline gained `sparklinew`, `sparklineh`, and
      `sparklinecolor` (with `sparklinew=full`), while the share charts keep
      `chartw`/`charth`, and `progress` uses `progressw`/`progressh`/
      `progresstrackcolor`. Three sizing vocabularies for one accessory slot is
      precisely what the matrix has to make visible rather than hide.

## 2. The generator

- [x] 2.1 Add `docs/scripts/build_reference.py`, standard library only, matching
      `build_guide.py`'s conventions. Emits Markdown partials into
      `docs/_content/_generated/`. Supports `--check`, exiting non-zero when a
      partial is stale, for CI.
- [x] 2.2 Emit `params-table.md` — the full parameter table, grouped, replacing
      the hand-written table in `plugin-authoring.md`.
- [x] 2.3 Emit `chart-matrix.md` — six kinds by three entry paths, with knobs,
      limits, and popover behavior.
- [x] 2.4 Teach `build_guide.py` to expand a partial include directive when
      rendering `_content`, so the partials land in the published pages and in
      `llms-full.txt` without a second mechanism.

## 3. The Charts page

- [x] 3.1 Add `docs/_content/charts.md`: what a chart is on each surface, the
      generated matrix, then per-kind detail linking into the existing prose in
      `plugin-authoring.md` and `widgets.md`. Move no prose — link to it.
- [x] 3.2 Add its `PAGES[]` entry in `build_guide.py` (nav label, title, and the
      SEO description that also becomes its `llms.txt` line), the sidebar, and
      the guide index card grid.
      NOTE: `docs/guide/index.html` is hand-written (no Markdown source) and
      hand-maintains a card number per page mirroring `PAGES` order, so
      inserting Charts shifted eleven of them. Renumbered programmatically from
      `sourced_pages()` rather than by hand. That mirror is itself the kind of
      duplication this change is about; `starlight-docs-site` removes it by
      generating the index from the sidebar config.
- [x] 3.3 Cross-link both ways: `plugin-authoring.md`'s chart sections and
      `widgets.md`'s gauge/sparkline nodes point at `charts.md`.

## 4. Guards

The point of the change. Each of these fails CI on a drift that ships silently
today.

- [x] 4.1 Repoint `check_params.py`'s *documentation* surface at `params.json`;
      delete its Markdown-table scraper. #98 took this script from three
      surfaces to six — `parser_keys`, `public_keys`, and one `sdk_keys` per
      SDK via `SDK_SOURCES`. Only `doc_keys` changes. Leave `SDK_SOURCES`, the
      `EXCEPTIONS` mechanism, and its `paramN` entry alone, and confirm the
      six-way report still names which surface is missing which key.
- [x] 4.2 Add the constants check: scrape the `public static let` declarations
      named in 1.2 from `ChartParams.swift` and compare against `params.json`,
      failing with the symbol, both values, and the file each came from.
      NOTE: the first version read the whole file for `static let defaultWidth`
      and matched `ProgressParams`' 120 when asked for `SparklineStyle`'s 90 —
      the check reporting a drift that did not exist, and one that would have
      passed a real drift. `swift_constant` now scopes to the declaring type
      before matching. The guard caught its own bug on first run.
- [x] 4.3 Add `docs/scripts/check_links.py` — resolve every repository-relative
      and same-site link in `docs/_content/**` and the root Markdown files,
      failing on a target that does not exist. External URLs are out of scope.
      NOTE: reach is narrower than "the four broken links" implies. It catches
      `plugin-authoring.md`'s GitHub link (5.2). It cannot catch 5.4, because
      `llms.txt` is generated output and is not scanned — the fix belongs at
      its source anyway — nor 5.3, because `CONTRIBUTING.md:207` mentions
      `plugins/examples/` as inline code in prose, not as a link. Prose
      mentioning a path is out of scope: matching every backticked string
      against the filesystem would flag every illustrative example.
      NOTE: `slugify` is imported from `build_guide` rather than
      reimplemented. The first version reimplemented it, collapsed whitespace
      runs where `build_guide` emits one hyphen per whitespace character, and
      reported three anchor breaks that did not exist.
- [x] 4.4 Wire `build_reference.py --check` and `check_links.py` into
      `lint.yml`'s `docs` job, each with the comment convention the existing
      steps use — what drifts, and what shipped because it was unguarded. The
      job now also carries `scripts/embed_sdk.py --check` from #98; keep the
      ordering cheapest-first so a fast failure is the common one.

## 5. Fix what is already broken

- [x] 5.1 `docs/_content/json-output.md` — fixed incidentally by #98, which
      rewrote that paragraph for `JSONMenu`. No action; listed so the set is
      accounted for.
- [x] 5.2 `docs/_content/plugin-authoring.md:721` — `tree/main/examples` is now
      `tree/main/plugins/showcase`.
- [x] 5.3 `CONTRIBUTING.md:207` — `plugins/examples/` is now
      `plugins/typescript/examples/`; while there, describe the current
      `plugins/` layout (`typescript` / `python` / `go` / `showcase` /
      `fixtures`).
- [x] 5.4 `docs/llms.txt`'s example-plugins link is generated from
      `build_guide.py`'s footer — fix it at the source, not in the output.
- [x] 5.5 Confirm `check_links.py` from 4.3 fails on each of these before the
      fix and passes after.

## 6. Deduplicate the SDK docs

- [x] 6.1 Cut `## API` and `## Widget cards` from
      `plugins/typescript/README.md`, `plugins/python/README.md`, and
      `plugins/go/README.md`; each gains one line pointing at the cross-language
      table in the published SDK guide. #98 grew all three (+49/+57/+57) and
      `sdk.md` with them (+137), so there is more duplication to remove than
      when this was planned, not less.
- [x] 6.1a Keep the genuinely per-language material #98 added: how each SDK
      reaches a plugin (`vee sdk ts|py` writing the file beside it, versus Go's
      `go get github.com/navbytes/vee/plugins/go`), and Python's
      camelCase-to-snake_case and tuple-to-mapping deprecations. Those differ
      per language and do not belong in a cross-language table.
- [x] 6.2 Keep per-language content: requirements, layout, hello world, tests.
- [x] 6.3 Verify `sdk.md`'s cross-language table covers every method the three
      cut sections named, adding any it was missing.

## 7. Discoverability fixes

      NOTE: it did not. `JSONMenu`, added in #98, appeared only in
      `json-output.md` and in the per-language READMEs this task cuts —
      cutting them first would have lost it from the SDK reference entirely.
      Added to `sdk.md` as a fourth type before the cut landed. The `Node.*`
      layout builders were already covered.
- [x] 7.1 `build_guide.py:404` — collect `h3` as well as `h2` into the "On this
      page" nav, nested under their parent. `### Share charts` must appear.
- [x] 7.2 Regenerate the site and the search index; confirm searching "pie",
      "donut", and "chart options" reaches `charts.md`.

## 8. Verify

- [x] 8.1 Full `lint.yml` docs job green: guide freshness, params parity,
      constants, schemas, links, search index.
- [x] 8.2 Break one thing per guard on purpose — change `maxSegments` in Swift,
      add a parser case, break a link — and confirm each fails with a message
      naming the file and the disagreement.
- [x] 8.3 Answer the question that started this from the published site alone:
      what chart kinds exist, and what options does each take.
