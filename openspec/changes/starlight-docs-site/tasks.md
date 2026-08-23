## 0. Gate

- [x] 0.1 Confirm the zero-dependency policy is understood to cover the shipped
      product rather than the repository, and that a docs-only build dependency
      is acceptable. If not, stop: extend `build_guide.py` with dark mode and an
      `h3` table of contents instead, and close this change.
      NOTE: cleared by the client. `CONTRIBUTING.md`'s policy statement and the
      PR checklist both now say the policy covers the app and the SDKs, and
      name `docs-site/` as the one exception.
- [x] 0.2 Confirm `plugin-api-reference` has landed. Its generator emits
      Markdown partials so it survives this migration; running these in the
      other order builds it twice.

## 1. Capture the current contract

Before changing anything, write down what must still be true afterwards. This is
the acceptance list for section 6.

- [x] 1.1 Snapshot the rendered `<head>` of every published page — canonical,
      `og:*`, `twitter:*`, `link rel=alternate`, description, favicon.
- [x] 1.2 Snapshot the published URL set: fourteen guide pages, their `.md`
      mirrors, `llms.txt`, `llms-full.txt`, `sitemap.xml`, `robots.txt`,
      `/schemas/*.json`, the landing page, and the three comparison pages.
- [x] 1.3 Snapshot the page furniture the current template provides: skip link,
      `aria-current` on the active nav item, the sidebar order, the prev/next
      pager, and the "On this page" nav.

## 2. Scaffold

- [x] 2.1 Create `docs-site/` — Astro + Starlight, committed lockfile, Node
      version pinned to match CI.
- [x] 2.2 Point the content collection at `docs/_content`. The prose does not
      move.
- [x] 2.3 Port `build_guide.py`'s `PAGES[]` into per-page frontmatter (`title`,
      `description`) and the Starlight sidebar order, preserving every existing
      title and description verbatim — they are the site's SEO metadata and
      `llms.txt`'s one-line summaries.
      NOTE: the pages had no frontmatter, and the old renderer had to keep
      working until section 7 deleted it. `strip_frontmatter` was added to
      `build_guide.py` as a transitional shim; with it, the old builder
      produced byte-identical output from the new sources, which is what made
      the rest of the migration verifiable one step at a time.
- [x] 2.4 Copy `docs/index.html`, `docs/compare/`, `docs/assets/`,
      `docs/schemas/`, `docs/robots.txt`, `docs/CNAME`, `docs/.nojekyll`, and
      `docs/site.webmanifest` through to the build output unchanged.
- [x] 2.5 Reconcile theming so `/guide/` and the landing page share type,
      color, and spacing tokens rather than merely coexisting.

## 3. Port the machine-readable forms

Starlight provides none of these. Losing any is a regression against the
`plugin-docs-integrity` requirements added in #95 and #96.

- [x] 3.1 An Astro integration emitting each page's source Markdown at a route
      derivable from the page's own URL.
      NOTE: Starlight's `autogenerate` sidebar cannot see this collection —
      it infers structure from a directory under `src/content`, and the prose
      deliberately stays in `docs/_content` behind a glob loader. Both
      `directory: "."` and `directory: "guide"` produced an empty sidebar, and
      with it no `aria-current` and no prev/next pager. The sidebar is built
      from each page's `sidebar.order`/`sidebar.label` frontmatter instead:
      still derived, never a hand-kept list.
- [x] 3.2 Inject `<link rel="alternate" type="text/markdown">` into each page's
      head, pointing at 3.1's route.
- [x] 3.3 Emit `llms.txt` from the collection: the project blurb, every page
      with its description, the schema links, and the repository links.
- [x] 3.4 Emit `llms-full.txt` — every page's full text in sidebar order.
- [x] 3.5 Confirm the generated `sitemap.xml` covers the guide, the landing
      page, and the comparison pages, matching 1.2.

## 4. Redirects

- [x] 4.1 Generate a stub at every old `/guide/<slug>.html` path: a meta
      refresh plus `<link rel="canonical">` at the new URL, from the same page
      list, not hand-written.
      NOTE: stubs carry `data-pagefind-ignore`. Without it Pagefind indexed
      them, so every page had a second search result reading "moved".
- [x] 4.2 Update `llms.txt`'s own links to the new URLs, so the canonical index
      does not point through the stubs.
- [x] 4.3 Grep the repository — README, CONTRIBUTING, the app, the landing page,
      `plugins/**/README.md` — for `guide/*.html` links and update them.
      `check_links.py` from `plugin-api-reference` covers this once the paths
      change.

## 5. CI and hosting

- [x] 5.1 Add a Pages deploy workflow: build `docs-site/`, upload the artifact,
      deploy. Runs on `main` only.
- [x] 5.2 In `lint.yml`'s docs job, replace the guide-freshness and search-index
      steps with a docs build that does not deploy, so a PR that breaks the
      build fails on the PR.
- [x] 5.3 Leave `check_params.py`, `check_schemas.py`, `build_reference.py
      --check`, and `check_links.py` in place unchanged.
- [ ] 5.4 Flip the repository's Pages source from branch `/docs` to GitHub
      Actions. Until this is done the workflow deploys nothing — call it out in
      the PR description, since it is a settings change no reviewer can make by
      approving a diff.

## 6. Verify against section 1

      BLOCKED — not a code change. Settings > Pages > Source: "Deploy from a
      branch" to "GitHub Actions". Until it is flipped, docs.yml builds and
      uploads the artifact but the live site keeps being served from the
      branch, which no longer contains a rendered site — so the flip and this
      merge have to land together.
- [x] 6.1 Diff the new `<head>` of every page against 1.1. Any tag present
      before and absent now is a regression to fix, not a default to accept.
      NOTE: found a real regression. Starlight emits `og:title`,
      `og:description` and `twitter:card` but no image, which silently
      downgrades every shared link from a large card to a bare text preview.
      `og:image` and `twitter:image` restored in config. `twitter:title` and
      `twitter:description` are deliberately not duplicated: Twitter reads the
      `og:` equivalents when they are absent.
- [x] 6.2 Confirm every URL in 1.2 resolves, including the `.md` mirrors and
      both `llms` files.
      NOTE: two would not have. `/guide/` is a hand-written overview with its
      own card grid and no Starlight equivalent — it would have 404'd silently,
      and is now kept as `docs/guide-index.html`, copied in at its old path
      with its links pointing at the new URL shape rather than through the
      redirect stubs. And `/sitemap.xml`, the URL `robots.txt` names, became
      `/sitemap-index.xml`; both are published now, which avoids rewriting
      `robots.txt` and waiting for a recrawl. Verified: all 41 snapshot URLs
      resolve.
- [x] 6.3 Confirm the furniture in 1.3 survives: skip link, active-item state,
      sidebar order, pager, on-this-page nav.
      NOTE: also verified the anchors. All 188 h2/h3 ids Starlight generates
      with github-slugger match what the old builder produced, which is why no
      in-page link broke — the old `slugify` docstring's claim that it matched
      GitHub's slugger turned out to be true.
- [x] 6.4 Confirm search returns the same pages for "pie", "chartw", "widget
      card", and "trust".
- [x] 6.5 Confirm dark mode renders every page, including code fences, tables,
      and the chart matrix from `plugin-api-reference`.
- [x] 6.6 Confirm each old `.html` URL redirects to its new location.
- [x] 6.7 Confirm the landing page and both comparison pages are byte-identical
      to what ships today.

## 7. Delete

Only after section 6 passes on a real deploy.

- [x] 7.1 Delete `docs/scripts/build_guide.py` (562 lines) and
      `check_search_index.py` (100 lines).
      NOTE: `check_links.py` imported `slugify` from it. The function moved
      into `check_links.py` rather than the import being dropped, since it is
      what keeps the anchor check honest.
- [x] 7.2 Delete `docs/guide/` and `docs/pagefind/` from version control; add
      them, `docs/sitemap.xml`, `llms.txt`, and `llms-full.txt` to
      `.gitignore` as build output.
      NOTE: `docs/_content/_generated/` is now ignored too. It was committed by
      `plugin-api-reference` and guarded by `build_reference.py --check`; with
      the site built rather than committed, the partials are build inputs
      generated on every run, so there is no stale copy for a check to catch.
      The CI step generates them instead of verifying them.
      NOTE: `check_links.py` needed its same-site resolution rewritten. It
      mapped a published URL onto `docs/` verbatim, which was correct while the
      site was committed and would now report every `/guide/<slug>/` link as
      broken. It maps them back to `docs/_content/<slug>.md`, and knows which
      published paths the build emits with no source behind them.
- [x] 7.3 Rewrite `CONTRIBUTING.md`'s docs section: the loop is now a dev
      server, not "regenerate and commit". Remove the "edit the Markdown, never
      the HTML" warning — there is no committed HTML to edit.
- [x] 7.4 Update the `docs/` row in `CONTRIBUTING.md`'s repository map.
