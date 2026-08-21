## Why

A large share of people writing Vee plugins will do it with an LLM's help, and
Vee's docs are currently shaped only for humans reading a browser. The raw
material is already published and nothing points at it: `docs/_content/*.md` is
served live at `/_content/<page>.md` as `text/markdown`, and the JSON Schemas at
`/schemas/*.json` as `application/json` — both verified against the live site.
Nothing advertises either, so a model asked about the plugin format lands on
`/guide/<page>.html` and parses navigation chrome, code-block markup, and a
search bundle to reach three sentences of prose.

The cost of that is not just wasted tokens. A model that scrapes one HTML page
sees one page; the plugin format spans thirteen. Reconstructing it from partial
scrapes is exactly how a plugin ends up using a parameter that does not exist.

The fix is small because the content already exists in the right form. What is
missing is a front door: the conventional entry point agents look for, and
guessable URLs for the Markdown behind each page.

## What Changes

- Generate `/llms.txt` — a Markdown index following the llmstxt.org convention:
  what Vee is, and every guide page as a linked, one-line-described entry, using
  the descriptions already in `PAGES[]`.
- Generate `/llms-full.txt` — every guide concatenated, so the complete plugin
  format is one fetch rather than thirteen crawls.
- Mirror each guide's Markdown at `/guide/<slug>.md`, beside its `.html`, so
  swapping the extension works and `_content/` stops being the only path. Add
  `<link rel="alternate" type="text/markdown">` to each page's head.
- Link the published JSON Schemas from `llms.txt`, so a model writing a widget
  card or JSON menu reads the contract instead of inferring it from prose.
- Add a short guide page on writing Vee plugins with an LLM: the schema URLs,
  and the `vee lint` verification loop that turns a plausible plugin into a
  correct one.
- All generated artifacts are emitted by `build_guide.py` and covered by its
  `--check`, so they cannot fall behind the content the way the search index
  could before the guard added in #94.

**Deliberately not in this change:** `vee lint --format json`. It is the right
way for an agent to consume lint findings and it is worth doing, but it is a
Swift change to the CLI's output contract rather than a docs change, and it
deserves its own proposal rather than riding along in this one.

## Capabilities

### Modified Capabilities

- `plugin-docs-integrity`: gains requirements covering the machine-readable
  discovery artifacts — that they exist at conventional locations, that the
  Markdown behind every page is reachable at a guessable URL, and that both are
  generated and verified rather than hand-maintained.

## Impact

- **`docs/scripts/build_guide.py`** — emits `llms.txt`, `llms-full.txt`, and the
  per-page `.md` mirrors; `--check` extends to cover them. The head template
  gains one `<link rel="alternate">`.
- **`docs/_content/`** — one new page on LLM-assisted authoring, which means a
  new `PAGES[]` entry, sidebar and card-grid entries, and the sitemap.
- **No Swift changes.** No change to any parser, the CLI, or the SDKs.
- **External, outside the repo:** Cloudflare's AI Crawl Control on the
  `navbytes.io` zone must not be blocking the crawlers this change is meant to
  serve. Verifying that is a dashboard action, not a code change.
