# Design: retire-plugin-sdks

## Decisions

### Kill, not types-only, not keep-but-fix

Three strategies were argued and adversarially judged (maintenance, author
experience, ecosystem/trust lenses):

1. **Kill** — the format is the SDK; docs/schema/lint/templates carry
   ergonomics. Won on maintenance (recurring cost → ~zero) and ecosystem
   (breaks the fewest, at the ecosystem's lifetime minimum).
2. **Types-only artifacts** generated from the JSON Schema. Rejected: it
   re-imports a smaller drift problem — an npm+pip codegen toolchain inside a
   Swift repo, a per-release npm publish, and a types-only `@navbytes/vee` 2.0
   that crashes anyone runtime-importing latest. Its good ideas (schema as
   contract, AGENTS.md/llms.txt, lint tombstone) are folded into this change.
3. **Keep SDKs, vendor as sibling files at write time.** Rejected: keeps the
   whole 8–10-files-per-feature tax and its own exit plan was "demote the
   SDKs later" — paying two migrations against a larger ecosystem.

### One change, not a two-release deprecation window

A deprecation release would keep provisioning alive to protect SDK-importing
plugins that lack a sibling copy. That population is: plugins installed from
Discover since 0.6.2 (days old) plus unknown external authors of a 0.6.x app.
Meanwhile a sibling `vee.py`/`./vee.ts` keeps working **forever** with zero app
support — Python resolves the script directory before anything else, and a
relative TS import names a file — so `vee new`-scaffolded and repo-vendored
plugins don't break at all. The only breakage is the no-sibling import, lint
names it with the fix, and the debugging guide covers the error row. Carrying
dead provisioning code for a release protects almost nobody and costs a second
change.

### What survives, and why

- `plugins/fixtures/*.txt` — no longer an SDK contract; they stay as
  parser-conformance goldens for `FixtureRoundTripTests`. Do not relocate
  (paths are referenced); do rewrite `plugins/README.md`.
- `plugins/showcase/` — plain-shell teaching examples; now the front door.
- Discovery filter for `vee.ts`/`vee.py` filenames — existing user plugin
  folders contain siblings written by `vee new`/`vee sdk`; they must not be
  discovered as plugins. Tiny, keep.
- `WidgetParity`, the ledger, and `docs/schemas/*.json` — they guard the app
  and the format, not the SDKs. The JSON Schema is now the single typed
  contract; submit it to SchemaStore.
- ECMA-262 float formatting in the *parser* stays; the requirement that three
  other implementations reproduce it byte-identically ceases to exist.

### Typed templates instead of typed packages

`vee new` emits one self-contained file per language: build a literal (typed
via an inlined `interface`/`TypedDict` block covering the JSON output
vocabulary the template actually uses, not the whole schema), `json.dumps` /
`JSON.stringify` it, done. Autocomplete comes from the editor's own type
checker; nothing is imported, versioned, or provisioned. A unit test in
VeeCLITests asserts the template type blocks stay consistent with
`docs/schemas/json-output.schema.json` key names (same drift-guard pattern as
the parameter table) — cheap string-level check, not codegen.

### Lint tombstone semantics

Detection per language on the plugin's own source:
- Python: `import vee` / `from vee import` at top level.
- TS/JS: import/require of `@navbytes/vee`, `./vee.ts`, `./vee.js`, `./vee`.

Sibling present (a `vee.py`/`vee.ts` beside the plugin): **warning** — runs
fine by language rules, but the copy is frozen; migration guide linked.
No sibling: **error** — the plugin cannot run anywhere; message names the two
ways out (port to JSON output, or copy a frozen SDK sibling from an old
checkout). Never auto-rewrites user source.

## Risks

- Builder chaining is genuinely lost; typed dicts give key-completion only.
  Accepted — it is what every surviving stdout ecosystem offers.
- Out-of-catalog plugins relying on central provisioning break with no
  telemetry. Mitigated by lint error + debugging-guide section + MIGRATION
  doc; population believed ~zero (app is 0.6.x, provisioning shipped in
  0.6.2).
- LLMs will hallucinate `from vee import` for years — the lint tombstone is
  permanent by design.
- Catalog port could regress rendered output — gated by before/after render
  diffs per plugin.
