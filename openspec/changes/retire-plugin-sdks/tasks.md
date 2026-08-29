# Tasks: retire-plugin-sdks

## 1. Runtime and core deletion (vee)

- [x] 1.1 Delete `Sources/VeeRuntime/SDKProvisioner.swift` and the SDK branch
  of `Sources/VeeRuntime/EnvironmentBuilder.swift` (injection, import
  sniffing); delete `Sources/VeeCore/EmbeddedSDK.swift` and the Node resolver
  source it embeds
- [x] 1.2 Remove `SDKProvisioner.provision()` call from
  `Sources/VeeApp/PluginsDirectory.swift` and `sdkDirectory` from the runtime
  context; keep the `vee.ts`/`vee.py` discovery filename filter in
  `PluginDiscovery` (existing sibling copies must not run as plugins)
- [x] 1.3 Delete `Tests/VeeRuntimeTests/SDKProvisioningTests.swift`; keep
  `PluginDiscoveryVendoredSDKTests` (filter still exists)

## 2. CLI (vee)

- [x] 2.1 Delete the `vee sdk` command and `Scaffold.vendoredSDK()`; `vee new`
  no longer writes a sibling SDK file
- [x] 2.2 Rewrite `vee new` templates (TS, Python; shell/other untouched) to
  build the JSON output format directly with an inlined type block
  (TS `interface`, Python `TypedDict`) and print it — no imports beyond
  stdlib; `vee render` must accept each template's output
- [x] 2.3 Add the template↔schema drift test in VeeCLITests: type-block keys
  ⊆ `docs/schemas/json-output.schema.json` properties
- [x] 2.4 Linter: retired-SDK rules per design.md — error when an SDK import
  has no sibling file, warning when a sibling exists; unit tests for both,
  plus the no-import case staying silent

## 3. SDK trees and pipelines (vee)

- [x] 3.1 Delete `plugins/go`, `plugins/python`, `plugins/typescript`; keep
  `plugins/fixtures/` (parser goldens) and `plugins/showcase/`; rewrite
  `plugins/README.md` for the new layout
- [x] 3.2 `.github/workflows/ci.yml`: remove the three SDK test jobs;
  `release.yml`: remove npm version stamping, `@navbytes/vee` publish, and
  the `plugins/go/*` tag step
- [x] 3.3 Verify `swift build && swift test && swiftlint lint --strict` passes
  with the trees gone (fixture round-trip and parity tests intact)

## 4. Docs (vee)

- [x] 4.1 Replace `docs/_content/sdk.md` with a migration guide: why retired,
  sibling copies keep working, no-sibling imports fail, how to port to JSON
  output (before/after example), npm/Go artifact status
- [x] 4.2 `plugin-authoring.md` + `getting-started.md`: lead with JSON output
  + `$schema` autocomplete; remove SDK references repo-wide (`README.md`,
  `debugging.md` "No module named 'vee'" section now points at the migration
  guide)
- [x] 4.3 Add `AGENTS.md` (repo root) and `docs/llms.txt`: parameter
  reference, schema URL, 2–3 complete example plugins; update
  `writing-plugins-with-an-llm.md` to stop mentioning SDKs
- [x] 4.4 Note SchemaStore submission as a follow-up in the migration guide
  (the PR itself is manual, post-merge)

## 5. Catalog port (vee-plugins)

- [ ] 5.1 Port every SDK-importing plugin (14 + `demo/controls-sdk.*`) to
  build a dict/object and print JSON directly; capture each plugin's rendered
  stdout before and after and diff (allowing only whitespace/key-order-neutral
  differences); plugins needing credentials/network: verify structure by
  running with stubbed env where feasible
- [ ] 5.2 Delete all sibling `vee.py`/`vee.ts` copies, `scripts/sync-sdk.sh`,
  and `demo/controls-sdk.*` (keep `controls-raw.*`, rename if clearer);
  update `demo/README.md`
- [ ] 5.3 Update `README.md`/`CONTRIBUTING.md`: plugins are dependency-free
  executables; no SDK files may be committed (add a CI/build-catalog check if
  one line suffices)

## 6. Release note

- [x] 6.1 `CHANGELOG.md` entry: breaking-change framing, migration guide
  link, the manual post-merge ops (`npm deprecate @navbytes/vee`, no new Go
  tags)
