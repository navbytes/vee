# Docs mirror — Cloudflare Pages

Status: **Implemented** · Owner: TBD · Surface: `.github/workflows/docs.yml`

The documentation site has exactly one reachable hostname. GitHub Pages serves
it from `docs/`, and because `docs/CNAME` sets a custom domain, GitHub redirects
the project URL to it:

```
$ curl -sSI https://navbytes.github.io/vee/ | head -3
HTTP/2 301
location: https://vee.navbytes.io/
```

So a network that blocks `navbytes.io` blocks the documentation outright, with
no fallback — the `github.io` URL lands the reader right back at the blocked
host. That is the gap this mirror closes: the `mirror` job in the Docs workflow
publishes the same build to Cloudflare Pages at **`vee-docs.pages.dev`**, on a
domain those networks generally do allow.

## What it is, and what it is not

It is a **mirror**, not a second home. Every page carries a canonical URL
pointing at `vee.navbytes.io` — Astro emits it from `site` in
`docs-site/astro.config.mjs`, and the hand-authored pages under `docs/` set it
literally — so search engines keep indexing the primary and the mirror does not
compete with it for ranking. `docs/robots.txt` likewise advertises only the
primary sitemap.

The mirror publishes the **same bytes**, not a second build. The `deploy` job
uploads `docs-site/dist` as an artifact and `mirror` downloads it. Two builds of
one commit should be identical, but "should be" is not worth relying on when the
whole point is to be the same site at a second URL.

## Setup

The job is inert until both secrets exist. Without them it logs why and exits
zero, so forks and pre-setup pushes do not turn a green docs deploy red — the
same treatment the Context7 refresh gets in the same workflow.

1. **Create the Pages project.** In the Cloudflare dashboard: Workers & Pages →
   Create → Pages → *Upload assets*. Name it **`vee-docs`** — the workflow
   passes `--project-name=vee-docs`, so the names have to agree. Upload anything
   to complete creation; the first real deploy replaces it.

   It must be a **direct-upload** project, not a Git-connected one. A
   Git-connected project builds from the repo itself, which would fight the
   workflow for control of the same deployments.

2. **Confirm the production branch is `main`.** Pages → `vee-docs` → Settings →
   Builds & deployments. The workflow deploys with `--branch=main`; that is what
   makes the upload a production deployment serving the stable
   `vee-docs.pages.dev` hostname. A branch that is not the production branch
   lands as a preview at a per-deployment subdomain, which would defeat the
   point of having a second fixed URL.

3. **Create an API token.** My Profile → API Tokens → Create Token, using the
   **Edit Cloudflare Workers** template, or a custom token with
   `Account → Cloudflare Pages → Edit`. Scope it to the one account. It needs no
   zone permissions and no access to any other resource.

4. **Set two repository secrets** (Settings → Secrets and variables → Actions):

   | Secret | Where to find it |
   | --- | --- |
   | `CLOUDFLARE_API_TOKEN` | the token from step 3 |
   | `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard → Workers & Pages → Account ID |

5. **Trigger a deploy.** Push a docs change, or run the Docs workflow manually
   from the Actions tab (`workflow_dispatch`). The `mirror` job logs the
   deployment URL.

## Verifying

```sh
curl -sSI https://vee-docs.pages.dev/ | head -1
curl -sS  https://vee-docs.pages.dev/ | grep -o '<link rel="canonical"[^>]*>'
```

The first should be `200`, the second should name `vee.navbytes.io` — a mirror
that canonicalises to itself is the failure mode worth checking for.

## Cost and blast radius

Cloudflare Pages' free tier covers this comfortably: 500 builds/month, and this
job does no build at all — it uploads a directory. The mirror cannot affect the
primary site. It runs `needs: deploy`, so it only ever publishes bytes that
already deployed successfully to GitHub Pages, and its failure leaves the
primary untouched.

## Rolling it back

Delete the two secrets and the job skips itself, logging why; nothing else in
the workflow depends on it. Delete the Pages project to take the hostname down.
