# Proposal: retire-plugin-sdks

## Why

The three official SDKs (Go/Python/TypeScript, ~2,750 lines kept byte-identical
via golden fixtures) solve a dev-time problem — type safety and IntelliSense —
with a runtime mechanism: an importable library the app must deliver. Every
complication since has been that mismatch leaking, not a bug streak: install
vendoring (#141), import-path injection with source-sniffing and a Node
resolver hook (#142), the don't-run-the-SDK discovery filter, lint learning to
fail plugins that cannot run (#137). An SDK-importing plugin is no longer "any
executable" — it dies under bare `python3 plugin.py` and only runs inside
Vee's injected environment, which breaks the product's founding principle.

Every stdout-contract ecosystem in the lineage (BitBar, xbar, SwiftBar, Argos,
Alfred, GitHub Actions) ships zero official runtime SDKs: the app owns the
format, docs, lint, and examples; typed wrappers are community-owned. The
maintenance tax lands on a solo maintainer: a new format parameter touches
8–10 files across four synchronized implementations, plus npm and Go release
channels and a catalog-side `sync-sdk.sh`.

The ecosystem is at its lifetime minimum — every SDK-importing plugin is
first-party, no third-party plugins exist, npm is at 0.2.x. This gets strictly
more expensive to unwind every month.

## What Changes

- **Delete the runtime machinery**: `SDKProvisioner`, `EmbeddedSDK`, the SDK
  branch of `EnvironmentBuilder` (PYTHONPATH/NODE_OPTIONS injection, import
  sniffing, the Node resolver), the `vee sdk` CLI command, and
  `Scaffold.vendoredSDK()`. The installer and runtime never learn about SDKs
  again. The `vee.py`/`vee.ts` discovery filter stays (existing user folders
  still contain siblings).
- **Delete the SDK trees**: `plugins/go`, `plugins/python`,
  `plugins/typescript`, their CI jobs, and release-workflow npm
  stamping/publish and Go module tagging. `plugins/fixtures/` stays as
  parser-conformance goldens (Swift round-trip tests parse them);
  `plugins/showcase/` stays.
- **Typed authoring without a dependency**: `vee new` templates emit
  self-contained plugins that build the recommended JSON output directly, with
  types inlined (TS `interface` block, Python `TypedDict` block) so editor
  autocomplete survives with nothing to vendor or resolve. A drift test keeps
  template types honest against the published JSON Schema.
- **Lint tombstone**: an SDK import with no sibling SDK file is an error
  ("cannot run — the SDK is retired, see the migration guide"); with a sibling
  it is a warning (works forever by plain language rules, but frozen). LLMs
  trained on 2025–26 docs will emit `from vee import` for years; this makes
  the failure actionable.
- **Docs become the SDK**: the SDK guide becomes a migration guide; the
  authoring docs lead with JSON output + published schema; `AGENTS.md` and
  `llms.txt` carry the parameter reference, schema, and worked examples for
  LLM-assisted authoring.
- **Catalog ports to raw JSON** (vee-plugins): all SDK-importing plugins
  rewritten to build dicts/objects and print JSON; sibling `vee.py`/`vee.ts`
  copies and `sync-sdk.sh` deleted; rendered output verified unchanged.
- **Published artifacts wind down, not break**: `@navbytes/vee` gets
  npm-deprecated (stays installable forever; bundled plugins keep working);
  Go module tags are immutable and stay; no new versions of either.

## Capabilities

### New Capabilities

- `plugin-authoring`: the dependency-free authoring contract — any executable
  printing the format, typed scaffolds with inlined types, the retired-SDK
  lint rules, and the LLM-facing authoring surface.

### Modified Capabilities

- `item-surface-visibility`: "every published SDK" leaves the
  every-authoring-format-agrees requirement (formats: line + JSON + schema).
- `widget-vocabulary`: same removal from the new-vocabulary-reaches-every-
  format requirement.

## Impact

- `Sources/VeeRuntime` (SDKProvisioner, EnvironmentBuilder), `Sources/VeeCore`
  (EmbeddedSDK), `Sources/VeeCLI` (Scaffold, `vee sdk`, Linter),
  `Tests/VeeRuntimeTests` (provisioning tests).
- `plugins/go|python|typescript` deleted; `.github/workflows/ci.yml` and
  `release.yml` SDK jobs removed.
- `docs/_content` (sdk.md → migration, plugin-authoring.md, debugging.md,
  writing-plugins-with-an-llm.md), repo `README.md`, new `AGENTS.md`/
  `docs/llms.txt`.
- vee-plugins: every `.py`/`.ts` plugin, `demo/`, `scripts/sync-sdk.sh`,
  `README.md`, `CONTRIBUTING.md`.
- Release ops (manual, post-merge): `npm deprecate @navbytes/vee`.

## Non-goals

- No new codegen toolchain (schema→types pipelines) — inlined template types
  plus a drift test are the whole mechanism.
- Not "never SDK": a future surface that runs author code inside Vee's own
  runtime (widget callbacks, say) earns a real SDK there.
- No breaking change to the format itself; xbar/SwiftBar compatibility is
  untouched.
