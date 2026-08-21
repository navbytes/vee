## Context

See `proposal.md` — Why. Three constraints shape every decision below.

**The zero-dependency policy is stated three times in the repo** and is part of the
product's pitch: the Swift app has *"zero third-party dependencies"*, the SDKs are
*"zero-dependency"*, and `build_guide.py`'s own docstring says *"Pure standard library
(no third-party deps, matching the project policy)"*. Documentation tooling is not
exempt by default.

**The docs pipeline has no deploy-time build.** GitHub Pages serves `docs/` straight
from the default branch (`.nojekyll`, no Pages workflow), so `docs/guide/*.html` is
generated output that is committed. `build_guide.py --check` runs in CI precisely
because the HTML once drifted two releases behind the Markdown. Anything added here
must preserve that property: the committed tree is what ships.

**Cross-reference anchors are load-bearing and fail silently.** `link_href` rewrites
`foo.md#bar` to `foo.html#bar`, and `slugify` deliberately matches GitHub's slugger so
a link resolves both on GitHub and on the rendered site. A moved heading therefore
produces a *working* link to the wrong page, not a visible break. There are 25 inbound
references to `plugin-authoring.md`, 16 of them deep anchors.

## Goals / Non-Goals

**Goals:**

- Close the documented-surface gaps without changing the documentation stack.
- Make the parameter and payload contracts machine-checked, so the class of drift that
  hid the widget node tree cannot recur silently.
- Add search, dark mode, and a custom domain within the existing generator.

**Non-Goals:**

- Restructuring `plugin-authoring.md` beyond two extractions.
- Any change to `LineParser`, `WidgetCardParser`, or `JSONOutputParser` *behavior*.
  Schemas describe what those already accept; they do not redefine it.
- Versioned documentation, i18n, or per-PR preview deploys.

## Decisions

### D1 — Stay on GitHub Pages with the stdlib generator; take the domain via `CNAME`

The domain and the stack are independent axes. `vee.navbytes.io` is a `docs/CNAME`
file plus a DNS record; it requires neither a new host nor a new framework.

*Alternatives considered.* **Cloudflare Pages** with the same static files: buys
per-PR previews, edge redirects, and analytics, but GH Pages is already CDN-fronted so
the performance delta is ≈ 0, and it adds a second deploy path. Because the files stay
static, this remains a drop-in later at no migration cost — the door is left open
rather than walked through. **A docs framework** (Starlight, VitePress, Docusaurus,
MkDocs Material — all open source, all competent): rejected because it would become the
largest dependency footprint in the repo for the part that ships no product, would
require rebuilding ~90 KB of hand-written CSS and a hand-built landing page, and — the
deciding argument — writes none of the missing content. The gap being closed here is
content, not presentation.

### D2 — Pagefind for search, not a framework's built-in

Search is the site's one genuinely missing feature over an 819-line reference page.
Pagefind indexes *already-built* static HTML and emits a chunked index plus a small
client bundle, so it attaches to the current output with no change to `build_guide.py`
and no change to the stylesheets.

It is a **build-time binary**, invoked alongside the generator; nothing third-party
enters the served page's runtime beyond the search bundle itself, and no package
manifest or lockfile enters the repo. This is the narrowest way to satisfy the need
without D1's rejected alternatives.

*Alternative considered.* A hand-rolled index emitted by `build_guide.py` (which
already parses every heading and slugifies every anchor, so the index is nearly a
by-product) plus ~120 lines of vanilla JS. Viable and fully stdlib, but it reimplements
tokenising, ranking, and excerpting — the one place where writing it ourselves costs
more than it saves. Revisit if Pagefind's binary ever becomes awkward to pin in CI.

### D3 — Extract `widgets.md` *before* writing the node-tree reference

The widget node tree is ~300 lines of new content and the Widgets section is moving.
Writing the content into `plugin-authoring.md` first and extracting afterwards means
writing it twice. The extraction is therefore sequenced ahead of the content work,
which inverts the natural "fix the facts first" order deliberately.

### D4 — Two extractions only

`widgets.md` (a distinct output surface, not a menu feature) and `debugging.md` (the
workflow question that currently has no home, split across a CLI reference and a
user-facing troubleshooting page). The remaining ~450 lines are one coherent topic —
what you can put on a menu line — and splitting further multiplies the anchor sweep in
D6 for diminishing returns.

### D5 — Collapse the parameter list from three copies to two, then guard the last one

`Linter.swift` already does `import VeePluginFormat`, so its hand-maintained
`knownParams` set — whose own comment concedes *"Hand-maintained, not derived"* — can
be derived from a set the format module exports. That removes one copy by construction
rather than policing it.

The documented table cannot be derived (it is prose with descriptions), so it stays
guarded by a check: a stdlib script in the shape of `build_guide.py --check`, parsing
the parser's recognised keys and the reference table's rows and failing CI on a
mismatch, with an explicit exception list for deliberate omissions.

*Alternative considered.* Generating the docs table from the parser. Rejected: the
table's value is its per-parameter prose, which cannot be generated, and a
half-generated table invites edits that the next build silently discards.

*Why not just the guard.* A three-way check would have caught the drift, but leaving a
hand-maintained mirror in place and adding a policeman is more machinery than removing
the mirror. The guard still checks all sets, so a future re-introduced copy is caught.

### D6 — Sweep anchors by grep, not by eye

Because a stale anchor renders as a working link (see Context), the extraction tasks
treat the link sweep as part of the extraction, enumerated against the 16 known deep
anchors, with a follow-up grep for any `.md#` reference resolving to a heading that no
longer exists on the target page.

### D7 — Schemas ship inside `docs/`, versioned by the payload's existing marker

Both payloads already carry a version field (`vee_widget: 1`, `vee: 1`). The schemas
key their version to that marker rather than introducing a second version axis, and
live under `docs/` so the existing Pages deploy serves them at a stable URL with no new
infrastructure — which is what makes editor `$schema` references work for plugin
authors.

Validation reuses the SDK golden fixtures that already exist and are already
round-tripped through the Swift parsers, so the schemas are checked against payloads
three independent implementations agree on, rather than against hand-written samples.

## Risks / Trade-offs

- **The anchor sweep misses a link → a reader lands on the wrong page with no error
  signal.** → D6 makes the sweep part of each extraction task, and a repo-wide grep for
  `.md#` references with no matching heading runs after both extractions land. Worth
  adding to the guard script if it proves fiddly.
- **Pagefind pins a third-party binary into CI, softening the zero-dependency stance.**
  → It is build-time only and produces committed static output; if it becomes a burden,
  D2's stdlib fallback is a known, scoped alternative rather than a rewrite.
- **The schemas over-constrain and reject payloads Vee actually accepts.** → Both
  parsers are deliberately permissive (unknown keys ignored, invalid values degraded
  with a diagnostic rather than a crash). The schemas must mirror that permissiveness —
  `additionalProperties` stays open — or authors get editor errors for payloads that
  work. Fixture validation catches the common case; the loose-by-design stance is the
  guard for the rest.
- **Extracting ~370 lines out of `plugin-authoring.md` costs its SEO standing on
  queries that currently land there.** → The page keeps its slug, its title, and the
  parameter reference that most inbound search targets; the new pages get their own
  `PAGES[]` metadata, and `sitemap.xml` (new here) helps them get indexed at all.
- **Shipping a `roadmap` page invites "when does X ship" expectations.** → See Open
  Questions; the decision is deliberately deferred, not defaulted.

## Migration Plan

No runtime migration — nothing deployed changes behavior. Two ordering constraints:

1. `docs/CNAME` and the DNS record can land first and independently; every existing URL
   path is preserved, and GitHub Pages continues to serve the old
   `navbytes.github.io/vee` host as a redirect.
2. D3's extraction precedes the widget content; D5's linter collapse precedes the drift
   guard, so the guard is written against two sets rather than three.

Rollback for any step is a revert: the site is committed static output, and the CI
additions are independent jobs.

## Open Questions

- **Does `roadmap.md` get published to the guide, or move to `docs/design/`?** It is
  435 lines of forward-looking content currently rendered nowhere, and either answer is
  one task line. Deferrable: it changes no spec, no approach, and no other task.
