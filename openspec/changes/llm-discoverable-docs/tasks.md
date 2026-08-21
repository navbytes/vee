## 1. Markdown mirrors

- [x] 1.1 Emit `docs/guide/<slug>.md` for every page in `PAGES[]` from its `docs/_content/<slug>.md` source, as part of the normal `build_guide.py` run
- [x] 1.2 Extend `--check` to fail when any mirror is missing or differs from its source
- [x] 1.3 Add `<link rel="alternate" type="text/markdown" href="./<slug>.md">` to the page template's head, and to the hand-written `guide/index.html`
- [x] 1.4 Confirm the mirrors keep their `.md` cross-links (correct for a Markdown reader) rather than being rewritten to `.html` the way the rendered pages are

## 2. `llms.txt`

- [x] 2.1 Emit `docs/llms.txt`: an H1 for Vee, a blockquote summary, and a linked entry per guide page using its existing `PAGES[]` description
- [x] 2.2 Link the two published JSON Schemas and the plugin SDK sources from a resources section
- [x] 2.3 Point every link at the Markdown mirror rather than the HTML page, since the audience is a client that wants source
- [x] 2.4 Cover `llms.txt` with `--check`

## 3. `llms-full.txt`

- [x] 3.1 Emit `docs/llms-full.txt`: every guide's Markdown concatenated in `PAGES[]` order, each preceded by a delimiter naming the page and its canonical URL
- [x] 3.2 Prepend a short header stating what the document is, the site it came from, and where the schemas live
- [x] 3.3 Cover `llms-full.txt` with `--check`, and report its size on build so growth stays visible

## 4. The LLM authoring guide

- [x] 4.1 Write `docs/_content/writing-plugins-with-an-llm.md`: what to hand a model (the schema URLs, `llms-full.txt`), and the `vee lint` verification loop
- [x] 4.2 Add its `PAGES[]` entry, sidebar entry, and card in `guide/index.html`, renumbering the cards
- [x] 4.3 Cross-link it from `plugin-authoring.md` and `sdk.md`
- [x] 4.4 Note honestly what a model still gets wrong about the format, so the page is useful rather than promotional

## 5. Verification

- [x] 5.1 `build_guide.py --check` passes, and fails when a mirror, `llms.txt`, or `llms-full.txt` is deleted or edited by hand
- [x] 5.2 All four docs guards pass together (`build_guide --check`, `check_params`, `check_schemas`, `check_search_index`)
- [x] 5.3 Serve the site locally and confirm `/guide/<slug>.md`, `/llms.txt`, and `/llms-full.txt` all return their expected content
- [x] 5.4 Confirm `llms-full.txt` contains text from every page in `PAGES[]`, including the newest one
- [x] 5.5 Fetch `/llms.txt` and follow every link in it, confirming each resolves
- [ ] 5.6 After deploy: verify the same three paths on `vee.navbytes.io`, served with sensible content types

## 6. External (not code)

- [ ] 6.1 Check Cloudflare's AI Crawl Control on the `navbytes.io` zone is not blocking the crawlers this change exists to serve
- [ ] 6.2 Enable *Enforce HTTPS* in the repo's Pages settings — currently the old `navbytes.github.io/vee` paths 301 to `http://`, not `https://`
