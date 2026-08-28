# Docs mirror — Cloudflare Pages

Status: **Live** · Owner: TBD · Surface: `.github/workflows/docs.yml`

The mirror is deployed and serving at <https://vee-docs.pages.dev>.

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

This was set up once against the real account; the steps below are what actually
worked, not what the dashboard suggests.

1. **Create the Pages project.** One command, with `wrangler` already
   authenticated (`wrangler login`):

   ```sh
   wrangler pages project create vee-docs --production-branch=main
   ```

   The name has to be `vee-docs` — the workflow passes
   `--project-name=vee-docs`, and the two have to agree. `--production-branch`
   is the load-bearing flag: the workflow deploys with `--branch=main`, and only
   a deployment on the *production* branch serves the stable
   `vee-docs.pages.dev` hostname. Any other branch lands as a preview at a
   per-deployment subdomain, which would defeat the point of having a second
   fixed URL.

   This creates a **direct-upload** project, which is what we want. Do not
   create a Git-connected one through the dashboard: that builds from the repo
   itself and would fight the workflow for control of the same deployments.

2. **Create an API token.** This is the one step with no CLI path — the OAuth
   token from `wrangler login` is for a local machine and is not what CI uses.
   In the dashboard: My Profile → API Tokens → Create Token, using the **Edit
   Cloudflare Workers** template, or a custom token with just
   `Account → Cloudflare Pages → Edit`.

   The narrow custom scope is enough, and is what this project runs on. It needs
   no zone permissions and — worth knowing, because tutorials often add it — no
   `Account Settings: Read` either. Wrangler only needs that to enumerate
   accounts, and the workflow passes `CLOUDFLARE_ACCOUNT_ID` explicitly.

3. **Set two repository secrets.**

   ```sh
   gh secret set CLOUDFLARE_ACCOUNT_ID --repo navbytes/vee --body "$(wrangler whoami | awk '/[0-9a-f]{32}/ {print $(NF-1)}')"
   gh secret set CLOUDFLARE_API_TOKEN  --repo navbytes/vee   # prompts; paste the token
   ```

   Omit `--body` for the token so it is read from a prompt and never lands in
   shell history. The account ID is not a credential — it is the identifier
   printed by `wrangler whoami`, and is also on the dashboard's Workers & Pages
   overview.

4. **Trigger a deploy.**

   ```sh
   gh workflow run Docs --repo navbytes/vee
   ```

   Or push any docs change. The `mirror` job logs the deployment URL.

## Verifying

```sh
curl -sSI https://vee-docs.pages.dev/ | head -1
curl -sS  https://vee-docs.pages.dev/ | grep -o '<link rel="canonical"[^>]*>'
```

The first should be `200`; the second should name **`vee.navbytes.io`**. A
mirror that canonicalises to itself is the failure mode worth checking for — it
would quietly compete with the primary for ranking, which is the one way this
can cause harm.

Confirm the deployment landed as production rather than as a preview:

```sh
wrangler pages deployment list --project-name=vee-docs
```

The `Environment` column should read `Production` and `Branch` should read
`main`. A `Preview` row means `--production-branch` was not set when the project
was created (step 1); the deploy still succeeds, but only the per-deployment
subdomain serves it and the stable hostname stays empty.

Note that the `mirror` job reports success both when it publishes and when it
skips for missing secrets — that is deliberate, but it means a green check is
not by itself proof of a deploy. Look for `Success! Uploaded N files` in the job
log, or just check the deployment list above.

## Differences from the primary

The mirror serves the same build, but Cloudflare Pages is not GitHub Pages and
two behaviours differ:

- **`.html` URLs redirect.** Cloudflare strips the extension and `308`s to the
  clean URL, where GitHub Pages serves it directly at `200`. The compare pages
  are linked as `./compare/vee-vs-xbar.html`, so on the mirror those take one
  extra hop before landing. Content and canonical are unaffected.
- **A fresh `pages.dev` hostname can resolve IPv6-only for a while.** On a
  machine without working IPv6, `curl` will report `Could not resolve host`
  while `dig` answers fine. It is a local resolution artifact, not a broken
  deploy; `curl --resolve vee-docs.pages.dev:443:<ipv4>` confirms the site is up.

## Cost and blast radius

Cloudflare Pages' free tier covers this comfortably: 500 builds/month, and this
job does no build at all — it uploads a directory. The mirror cannot affect the
primary site. It runs `needs: deploy`, so it only ever publishes bytes that
already deployed successfully to GitHub Pages, and its failure leaves the
primary untouched.

## Rolling it back

Delete the two secrets and the job skips itself, logging why; nothing else in
the workflow depends on it. Delete the Pages project to take the hostname down.
