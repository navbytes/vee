## 0. Gate

- [ ] 0.1 Confirm the zero-dependency policy is understood to cover the shipped
      product rather than the repository, and that a docs-only build dependency
      is acceptable. If not, stop: extend `build_guide.py` with dark mode and an
      `h3` table of contents instead, and close this change.
- [ ] 0.2 Confirm `plugin-api-reference` has landed. Its generator emits
      Markdown partials so it survives this migration; running these in the
      other order builds it twice.

## 1. Capture the current contract

Before changing anything, write down what must still be true afterwards. This is
the acceptance list for section 6.

- [ ] 1.1 Snapshot the rendered `<head>` of every published page — canonical,
      `og:*`, `twitter:*`, `link rel=alternate`, description, favicon.
- [ ] 1.2 Snapshot the published URL set: fourteen guide pages, their `.md`
      mirrors, `llms.txt`, `llms-full.txt`, `sitemap.xml`, `robots.txt`,
      `/schemas/*.json`, the landing page, and the three comparison pages.
- [ ] 1.3 Snapshot the page furniture the current template provides: skip link,
      `aria-current` on the active nav item, the sidebar order, the prev/next
      pager, and the "On this page" nav.

## 2. Scaffold

- [ ] 2.1 Create `docs-site/` — Astro + Starlight, committed lockfile, Node
      version pinned to match CI.
- [ ] 2.2 Point the content collection at `docs/_content`. The prose does not
      move.
- [ ] 2.3 Port `build_guide.py`'s `PAGES[]` into per-page frontmatter (`title`,
      `description`) and the Starlight sidebar order, preserving every existing
      title and description verbatim — they are the site's SEO metadata and
      `llms.txt`'s one-line summaries.
- [ ] 2.4 Copy `docs/index.html`, `docs/compare/`, `docs/assets/`,
      `docs/schemas/`, `docs/robots.txt`, `docs/CNAME`, `docs/.nojekyll`, and
      `docs/site.webmanifest` through to the build output unchanged.
- [ ] 2.5 Reconcile theming so `/guide/` and the landing page share type,
      color, and spacing tokens rather than merely coexisting.

## 3. Port the machine-readable forms

Starlight provides none of these. Losing any is a regression against the
`plugin-docs-integrity` requirements added in #95 and #96.

- [ ] 3.1 An Astro integration emitting each page's source Markdown at a route
      derivable from the page's own URL.
- [ ] 3.2 Inject `<link rel="alternate" type="text/markdown">` into each page's
      head, pointing at 3.1's route.
- [ ] 3.3 Emit `llms.txt` from the collection: the project blurb, every page
      with its description, the schema links, and the repository links.
- [ ] 3.4 Emit `llms-full.txt` — every page's full text in sidebar order.
- [ ] 3.5 Confirm the generated `sitemap.xml` covers the guide, the landing
      page, and the comparison pages, matching 1.2.

## 4. Redirects

- [ ] 4.1 Generate a stub at every old `/guide/<slug>.html` path: a meta
      refresh plus `<link rel="canonical">` at the new URL, from the same page
      list, not hand-written.
- [ ] 4.2 Update `llms.txt`'s own links to the new URLs, so the canonical index
      does not point through the stubs.
- [ ] 4.3 Grep the repository — README, CONTRIBUTING, the app, the landing page,
      `plugins/**/README.md` — for `guide/*.html` links and update them.
      `check_links.py` from `plugin-api-reference` covers this once the paths
      change.

## 5. CI and hosting

- [ ] 5.1 Add a Pages deploy workflow: build `docs-site/`, upload the artifact,
      deploy. Runs on `main` only.
- [ ] 5.2 In `lint.yml`'s docs job, replace the guide-freshness and search-index
      steps with a docs build that does not deploy, so a PR that breaks the
      build fails on the PR.
- [ ] 5.3 Leave `check_params.py`, `check_schemas.py`, `build_reference.py
      --check`, and `check_links.py` in place unchanged.
- [ ] 5.4 Flip the repository's Pages source from branch `/docs` to GitHub
      Actions. Until this is done the workflow deploys nothing — call it out in
      the PR description, since it is a settings change no reviewer can make by
      approving a diff.

## 6. Verify against section 1

- [ ] 6.1 Diff the new `<head>` of every page against 1.1. Any tag present
      before and absent now is a regression to fix, not a default to accept.
- [ ] 6.2 Confirm every URL in 1.2 resolves, including the `.md` mirrors and
      both `llms` files.
- [ ] 6.3 Confirm the furniture in 1.3 survives: skip link, active-item state,
      sidebar order, pager, on-this-page nav.
- [ ] 6.4 Confirm search returns the same pages for "pie", "chartw", "widget
      card", and "trust".
- [ ] 6.5 Confirm dark mode renders every page, including code fences, tables,
      and the chart matrix from `plugin-api-reference`.
- [ ] 6.6 Confirm each old `.html` URL redirects to its new location.
- [ ] 6.7 Confirm the landing page and both comparison pages are byte-identical
      to what ships today.

## 7. Delete

Only after section 6 passes on a real deploy.

- [ ] 7.1 Delete `docs/scripts/build_guide.py` (562 lines) and
      `check_search_index.py` (100 lines).
- [ ] 7.2 Delete `docs/guide/` and `docs/pagefind/` from version control; add
      them, `docs/sitemap.xml`, `llms.txt`, and `llms-full.txt` to
      `.gitignore` as build output.
- [ ] 7.3 Rewrite `CONTRIBUTING.md`'s docs section: the loop is now a dev
      server, not "regenerate and commit". Remove the "edit the Markdown, never
      the HTML" warning — there is no committed HTML to edit.
- [ ] 7.4 Update the `docs/` row in `CONTRIBUTING.md`'s repository map.
