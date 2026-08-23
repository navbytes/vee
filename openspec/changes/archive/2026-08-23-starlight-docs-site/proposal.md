## Why

The docs site is served with no build step at deploy time, so every rendered
byte is committed. `docs/_content` is 176K of source; `docs/guide` is 492K of
generated HTML and Markdown mirrors, `llms-full.txt` is another 148K of the same
prose, and `docs/pagefind` is 828K of committed search index. Roughly 1.4MB of
build output tracked in git to publish 176K of writing, and every content edit
churns all of it in the diff.

That choice has costs beyond repository size:

- `build_guide.py` is 562 lines of hand-rolled Markdown renderer — headings,
  lists, tables, fences, inline emphasis — maintained by this project, for this
  project.
- `check_search_index.py` is 100 lines whose entire job is catching a stale
  committed index. It exists only because the index is committed.
- The Markdown subset is deliberately limited, so a page needing anything
  outside it must have the renderer extended first.
- There is no dark mode: `prefers-color-scheme` appears zero times in either
  stylesheet.
- Page URLs carry `.html`.

Starlight replaces the renderer, the search index, the staleness guard, and the
theming, and a build step in CI replaces the committed output.

**The tradeoff this change asks for explicitly:** the project's stated policy is
zero third-party dependencies, and `build_guide.py` says so in its own docstring.
Starlight is a dependency. The claim here is that the policy protects the shipped
product — the app, the parsers, the three SDKs a plugin author runs — and that a
docs build tool confined to `docs-site/`, never linked into a binary and never
executed by a user, is different in kind. That is a judgement call, and if the
policy is meant to cover the repository rather than the product, this change
should be rejected in favour of extending `build_guide.py`.

## What Changes

- Add `docs-site/`: an Astro + Starlight project whose content collection is the
  existing `docs/_content/*.md`. The prose does not move and is not rewritten.
- Keep the marketing surfaces hand-authored. `docs/index.html` (40K of bespoke
  layout, hero animation, and screenshot sections) and `docs/compare/*.html` are
  copied through unchanged; Starlight owns `/guide/` only.
- Build and deploy from CI to GitHub Pages, keeping the `vee.navbytes.io`
  origin and the existing `CNAME`.
- Stop committing generated output: `docs/guide/`, `docs/pagefind/`,
  `docs/sitemap.xml`, `llms.txt`, and `llms-full.txt` become build artifacts.
- Delete `build_guide.py` and `check_search_index.py`.
- Preserve every machine-readable guarantee the docs already make — the
  per-page Markdown mirror and its `<link rel="alternate">`, `llms.txt`,
  `llms-full.txt`, the JSON Schemas at `/schemas/`, canonical and social
  metadata, and the sitemap — via a small Astro integration, since Starlight
  provides none of them.
- Redirect every existing `/guide/<slug>.html` URL to its new location, because
  those URLs are published in `llms.txt`, in the README, and in whatever has
  already crawled the site.
- Gain dark mode, which Starlight provides.

**Deliberately not in this change:** rebuilding the landing or comparison pages
in Astro, and any rewriting of guide prose. Both are separable, and bundling
either would make a migration that should be verifiable page-for-page into one
that is not.

**Sequencing:** this change should land after `plugin-api-reference`. That
change's generator emits Markdown partials rather than HTML precisely so it
survives this migration untouched; running them in the other order means
building the generator twice.

## Capabilities

### New Capabilities

- `docs-site-delivery`: how the documentation site is built, published, and
  verified — that published output is not committed, that URLs survive, and that
  the machine-readable forms are preserved across a change of renderer.

### Modified Capabilities

- `plugin-docs-integrity`: its generation-and-verification requirement is
  reworded to describe the guarantee rather than `build_guide.py --check`, which
  this change deletes. The guarantee itself does not weaken.

## Impact

- **`docs-site/`** (new) — Astro + Starlight, the first third-party dependency
  in the repository. Confined to docs; not linked into the app or any SDK.
- **`docs/guide/`, `docs/pagefind/`** — deleted from version control.
- **`docs/scripts/build_guide.py`, `check_search_index.py`** — deleted (662
  lines).
- **`docs/scripts/check_params.py`, `check_schemas.py`, `build_reference.py`** —
  unchanged; they read `docs/_content` and `docs/api`, not the rendered site.
- **`.github/workflows/`** — a new Pages deploy workflow; `lint.yml`'s docs job
  loses the guide-freshness and search-index steps and gains a docs build. Every
  other guard survives untouched, including the six-surface parameter parity and
  `scripts/embed_sdk.py --check` from #98: none of them read the rendered site.
- **`CONTRIBUTING.md`** — the authoring loop changes from "regenerate and commit"
  to "run the dev server".
- **Repository settings, outside the repo:** the Pages source must change from
  branch `/docs` to GitHub Actions. Until that flip, the deploy workflow has no
  effect.
- **No Swift changes.** No parser, CLI, or SDK changes.
