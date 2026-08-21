## 1. Domain

- [x] 1.1 Add `docs/CNAME` containing `vee.navbytes.io`
- [x] 1.2 (DNS half) Created the `CNAME` record `vee.navbytes.io` -> `navbytes.github.io`, DNS only, in the Cloudflare navbytes.io zone; verified resolving via 1.1.1.1 and 8.8.8.8 through to the GitHub Pages anycast IPs. **Still open:** *Enforce HTTPS* in the repo's Pages settings, which cannot be set until `docs/CNAME` is pushed (if DNS is proxied through Cloudflare, set SSL mode to Full (strict) — Flexible redirect-loops against Pages)
- [ ] 1.3 Verify `https://vee.navbytes.io/guide/plugin-authoring.html` resolves and that the old `navbytes.github.io/vee` paths still redirect

## 2. Page extractions (before any new content — design D3)

- [x] 2.1 Create `docs/_content/widgets.md` by moving the Widgets section out of `plugin-authoring.md` verbatim; add its `PAGES[]` entry in `build_guide.py` with nav label, title, and description
- [x] 2.2 Create `docs/_content/debugging.md` by moving the `vee dev` / `vee lint` / `vee show` / `vee render` workflow content out of `cli-and-urls.md`, leaving that page as the CLI reference; add its `PAGES[]` entry
- [x] 2.3 Add the Debug console, execution timeouts (`<vee.timeout>` and the 30s default), and exit-code behavior to `debugging.md`, cross-linking `troubleshooting.md` for user-facing symptoms
- [x] 2.4 Sweep all 25 inbound references to `plugin-authoring.md` — the 16 deep anchors first (`#line-parameters` ×4, `#widgets` ×3, `#environment-variables-vee-injects` ×3, `#searchable-filter-panel` ×2, `#filenames-and-refresh-intervals` ×2, `#streaming`, `#share-charts-pie-donut-stackedbar`) — across `docs/_content/`, `README.md`, `CONTRIBUTING.md`, `examples/README.md`, `plugins/README.md`
- [x] 2.5 Grep the repo for every `.md#` cross-reference and confirm each anchor still resolves to a heading that exists on its target page (a stale anchor renders as a working link to the wrong page — design D6)
- [x] 2.6 Run `python3 docs/scripts/build_guide.py`, commit the regenerated HTML, and confirm `--check` passes
- [x] 2.7 Add the two new pages to the card grid and sidebar in `docs/guide/index.html`

## 3. The widget layout node tree (gap G1)

- [x] 3.1 Document the `nodes` payload in `widgets.md`: the node tree's relationship to the five templates, and when to reach for it
- [x] 3.2 Document every node type — `vstack`, `hstack`, `zstack`, `grid`, `text`, `image`, `gauge`, `sparkline`, `spacer`, `divider` — verified against `Sources/VeeWidgetShared/WidgetNode.swift`
- [x] 3.3 Document the layout fields (`align`, `spacing`, `columns`, `min_length`, `families`) and the `style`/`font` objects (`tint`, `padding`, `line_limit`, `monospaced_digit`, `min_scale`, `fill`; `size`, `point_size`, `weight`, `design`), including the JSON key names that differ from the SDK field names
- [x] 3.4 Document `families` per-widget-size targeting with a worked example
- [x] 3.5 Add a complete worked example in all three SDKs (TypeScript, Python, Go), verified by running each against a real widget
- [x] 3.6 Fold the relevant parts of `docs/design/widget-surface-contract.md` into the guide and leave the design doc as the design record, not the reference

## 4. Remaining content gaps

- [x] 4.1 Add `enterprise-store` to `PAGES[]` with title/description and a sidebar entry (gap G2)
- [x] 4.2 Resolve the open question in `design.md`: publish `roadmap.md` to the guide, or move it to `docs/design/` — then do it
- [x] 4.3 Add an xbar / SwiftBar / Vee compatibility matrix to `migrating-from-swiftbar.md`, marking Vee-only parameters and tags, derived from `LineParser` and the `SwiftBarParams` provenance comments (gap G4)
- [x] 4.4 Add a "Publishing your plugin" section covering catalog submission, the trust-declaration honesty bar, and self-hosted stores, linking the now-published store page (gap G5)
- [x] 4.5 Add widget-card documentation to `plugins/python/README.md` and `plugins/go/README.md`, bringing both to TypeScript parity (gap G6)
- [x] 4.6 Add a parse-diagnostics reference to `troubleshooting.md`: each warning/error the Debug console can show and its fix (gap G7)
- [x] 4.7 Regenerate the guide HTML and confirm `--check` passes

## 5. Machine-checked contract (spec: plugin-docs-integrity)

- [x] 5.1 Export the recognised parameter-key set from `VeePluginFormat` and derive `Linter.knownParams` from it, deleting the hand-maintained mirror and its "Hand-maintained, not derived" comment (design D5)
- [x] 5.2 Add a stdlib drift-guard script in the shape of `build_guide.py --check` that compares the parser's key set, the linter's set, and the parameter rows in the authoring reference, failing with the offending parameter and the surface that is missing it
- [x] 5.3 Add a declared exception list for deliberately undocumented parameters, so an intentional omission is visible in review
- [x] 5.4 Write the JSON Schema for the widget-card payload (`vee_widget: 1`) under `docs/`, covering every field `WidgetCardParser` reads — including the node tree — with `additionalProperties` left open to mirror the parser's permissiveness (design D7)
- [x] 5.5 Write the JSON Schema for the JSON menu-output format (`{"vee": 1}`) under `docs/`, covering every field `JSONOutputParser` reads
- [x] 5.6 Add fixture validation: every SDK golden fixture payload validates against its schema, discovered by glob rather than enumerated, wired into the existing test suite
- [x] 5.7 Add the drift-guard and schema-validation steps to the `docs` job in `.github/workflows/lint.yml`
- [x] 5.8 Document the schemas' stable URLs and show a `$schema` reference in `widgets.md` and `json-output.md` so authors get editor validation
- [x] 5.9 Verify the guards actually fail: temporarily remove a documented parameter row, break a fixture field, and confirm each check fails with a useful message

## 6. Site features

- [x] 6.0 Fix `build_guide.py`'s table splitter to honor the `\|` escape — it split on every pipe, shattering rows on json-output, cli-and-urls, and widgets (already shipping broken). Verified: only the five pages containing escaped pipes changed

- [x] 6.1 Add Pagefind indexing over `docs/` as a build-time step, document it in `CONTRIBUTING.md` beside the `build_guide.py` instructions, and commit the generated index (design D2)
- [x] 6.2 Add the search UI to the guide layout and `app.js` — `/` to focus, keyboard navigation, Escape to dismiss — matching the existing hand-written styling
- [~] 6.3 ~~Add dark mode~~ **DROPPED — premise was wrong.** The site is already dark-native by design (`color-scheme: dark` on `:root`, a complete dark token set, and a stylesheet header reading "Cinematic dark, lit from within — Dark-native design system"). The 0 `prefers-color-scheme` hits meant dark-only, not light-only. Adding a light theme would be a large change against an explicit design stance; raise it as its own proposal if wanted
- [x] 6.4 Add a sticky in-page table of contents to guide pages, generated from the headings `build_guide.py` already parses and slugs
- [x] 6.5 Add copy buttons to code blocks in `app.js`
- [x] 6.6 Emit `sitemap.xml` and `robots.txt` from `build_guide.py` using each page's existing title/description metadata
- [x] 6.7 Confirm the site still works with JavaScript disabled — content, navigation, and anchors — and that search degrades rather than breaking

## 7. Verification

- [x] 7.1 `python3 docs/scripts/build_guide.py --check` passes and the committed HTML matches `docs/_content`
- [x] 7.2 The full test suite passes, including the new fixture-schema validation and the existing SDK drift guard
- [x] 7.3 Every page in `PAGES[]` is reachable from the sidebar, the card grid, and the prev/next pager
- [x] 7.4 Search returns results for terms that only appear in the new content (e.g. a node type name, a compatibility-matrix entry)
- [x] 7.5 Read the rendered `widgets.md` end to end and build a working node-tree widget from it alone, without reading the Swift source
