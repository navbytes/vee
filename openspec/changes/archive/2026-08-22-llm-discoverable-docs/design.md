## Context

See `proposal.md` — Why. Three facts about the existing setup shape the approach,
all verified against the live site rather than assumed.

**The content already exists in the right form.** `docs/` is the Pages root and
`.nojekyll` is present, so every file in it is served as-is. `docs/_content/*.md`
therefore already returns `200 text/markdown`. This change is almost entirely
about addressing and advertising, not about producing anything new.

**`build_guide.py` is the only generator, and `--check` is the only guard.** It
already emits the guide HTML, `sitemap.xml`, and `robots.txt`, and fails CI when
any is stale. Anything generated here belongs in the same place for the same
reason — #94 exists because the Pagefind index was generated somewhere else and
went unguarded.

**`PAGES[]` already carries a one-line description per page**, written as SEO
metadata. The index document needs exactly that, so it needs no new prose and
cannot drift from what the pages claim about themselves.

## Goals / Non-Goals

**Goals:**

- A client can obtain the complete plugin format in one request.
- The Markdown behind any page is reachable by transforming that page's URL.
- Every artifact is generated and `--check`-guarded.

**Non-Goals:**

- Changing any prose for the benefit of models. The pages are written for people
  and stay that way; this is about delivery, not tone.
- A Vee MCP server or editor plugin. Worth doing, different size of project.
- `vee lint --format json` — see the proposal's exclusion note.

## Decisions

### D1 — Mirror the Markdown into `guide/` rather than redirecting to `_content/`

`/guide/widgets.md` sits beside `/guide/widgets.html`, so extension-swapping is
the whole rule. `_content/` stays reachable but stops being the only path; it is
an implementation detail of the build, not an address anyone should learn.

*Alternative considered.* Serving `_content/` as the canonical Markdown location
and advertising that. Rejected: the path is unguessable, its name describes the
repository layout rather than the resource, and it leaves the natural URL empty.

*Cost, stated plainly.* The Markdown is committed twice — once as source, once as
a mirror. That is the same bargain `docs/guide/*.html` already takes (generated
output committed because Pages has no build step), and `--check` covers the copy,
so the duplication cannot rot.

### D2 — `llms.txt` and `llms-full.txt` at the site root

The llmstxt.org convention puts both at the origin root, which is where a client
looks without being told. `llms.txt` is the index; `llms-full.txt` is the whole
corpus. Emitting both from `build_guide.py` costs one loop over `PAGES[]` each.

`llms-full.txt` is roughly 150 KB of Markdown, which is one comfortable request
and well inside a modern context window. If it ever stops being that, the index
still works on its own, so the failure mode is graceful.

### D3 — The index links the schemas, not just the prose

A model writing a widget card gets a better answer from
`widget-card.schema.json` than from any paragraph: the schema encodes every enum,
clamp, and optionality, and CI already proves it matches what the parser accepts.
Naming both schemas in `llms.txt` puts the machine-readable contract one hop from
the entry point.

### D4 — Guard by regeneration, like every other artifact

`--check` re-renders each artifact and compares, exactly as it already does for
the HTML, the sitemap, and robots. No new mechanism, no new failure mode to
reason about, and a new page is picked up by construction because everything
derives from `PAGES[]`.

## Risks / Trade-offs

- **`llms-full.txt` grows without bound as the guide grows.** → It is generated,
  so its size is always visible in a diff; the index remains independently
  useful, and splitting it later is a generator change, not a URL change.
- **A model reads the Markdown mirror and misses that the site has more** (the
  schemas, the compare pages). → `llms.txt` is the mitigation: it names
  everything, and it is the document the convention points clients at first.
- **The convention may not settle where it is today.** → Both artifacts are
  generated text at fixed paths. If the convention moves, the cost is renaming an
  output, not rewriting content.
- **Publishing a page whose Markdown links relative paths that only resolve in
  the rendered site.** → `link_href` rewrites `foo.md#bar` to `foo.html#bar` only
  in the HTML; the Markdown mirrors keep their original `.md` links, which is
  correct for a Markdown reader and matches what `_content/` already serves.
