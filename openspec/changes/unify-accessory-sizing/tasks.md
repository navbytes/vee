## 1. Parse the new pair (no output change)

- [x] 1.1 Add `accessoryw` / `accessoryh` to `LineParameterKeys`.
- [x] 1.2 Parse them in `LineParser`, reusing the existing `full` handling, and
      fan the values out to whichever of `ProgressParams` / `SparklineStyle` /
      `ChartParams` the row builds (design D2).
- [x] 1.3 Emit a deprecation diagnostic for each of `progressw`, `progressh`,
      `sparklinew`, `sparklineh`, `chartw`, `charth`, naming its replacement.
      Follow the `trackcolor=` precedent already in the file.
- [x] 1.4 Where a row declares both, the new parameter wins.
- [x] 1.5 Tests: each accessory kind sized by the new pair; `full` on each;
      `full` still refused on `pie=`/`donut=`; old spellings still work and warn;
      new-wins-over-old; an accessory width on a row with no accessory is inert.
- [x] 1.6 Confirm the existing suite is green — this step changes no rendering.

## 2. Size a control

- [ ] 2.1 Apply `accessoryw=` to the inline `slider=` in `VeeUI/MenuRowAccessory`,
      replacing the hard-coded `sliderWidth`, defaulting to today's value.
- [ ] 2.2 `accessoryh=` is ignored for controls (design D5) — no diagnostic.
- [ ] 2.3 Tests: a sized slider; an unsized slider keeps today's width.

## 3. Structured output

- [ ] 3.1 Accept `accessoryWidth` / `accessoryHeight` in `JSONOutputParser`.
- [ ] 3.2 Deprecate `progressWidth`/`progressHeight`, `sparklineWidth`/
      `sparklineHeight`, `chartWidth`/`chartHeight` with the same diagnostics.
- [ ] 3.3 Update `docs/schemas/json-output.schema.json`.
- [ ] 3.4 Tests mirroring 1.5 through the JSON path.

## 4. Documentation

- [ ] 4.1 Update `docs/api/params.json`: add the new pair, mark the six old ones
      deprecated. `accessoryw=` has no single default — state "the accessory's
      own default" and point at the chart matrix (design D4).
- [ ] 4.2 Regenerate with `python3 docs/scripts/build_reference.py`, then verify
      `--check` passes.
- [ ] 4.3 Prose pages: `charts.md`, `plugin-authoring.md`, `json-output.md`,
      `sdk.md`, `migrating-from-swiftbar.md`.
- [ ] 4.4 LLM-facing text: `docs/_content/writing-plugins-with-an-llm.md` and the
      `rules` in `context7.json` — the text a model authoring a plugin reads.
- [ ] 4.5 `ARCHITECTURE.md` where it names the sizing parameters.
- [ ] 4.6 `CHANGELOG.md`: the new pair, the deprecations, and that nothing
      published changes what it draws.

## 5. SDKs, examples and fixtures (must land together)

- [ ] 5.1 `plugins/typescript/vee.ts` — new options, old ones deprecated.
- [ ] 5.2 `plugins/python/vee.py` and `plugins/python/README.md`.
- [ ] 5.3 `plugins/go/vee.go`.
- [ ] 5.4 `Sources/VeeCLI/EmbeddedSDK.swift` — the vendored copy `vee sdk` emits;
      it must match the SDK files exactly.
- [ ] 5.5 SDK examples: `plugins/typescript/examples/`, `plugins/python/examples/`.
- [ ] 5.6 `plugins/showcase/` plugins that size an accessory.
- [ ] 5.7 `plugins/fixtures/controls.txt` and any other golden output. Review the
      diff as intent — these are compared byte-for-byte across all three SDKs.
- [ ] 5.8 Confirm the SDK conformance tests pass for all three.

## 6. Verification

- [ ] 6.1 `swift test` green; `swiftlint --strict` clean.
- [ ] 6.2 `python3 docs/scripts/build_reference.py --check` passes; run
      `check_params.py` if it applies.
- [ ] 6.3 Grep every old spelling (text and JSON, all casings) and confirm each
      remaining hit is deliberate: deprecation handling, tests asserting the
      alias, changelog, migration docs.
- [ ] 6.4 `vee lint` on a plugin using the old spellings reports the deprecation
      and nothing else.
- [ ] 6.5 By hand: a plugin using the new pair renders identically in the menu
      bar and a detached window, for gauge, sparkline, stacked bar and slider —
      including `full`. Needs a real session.

## 7. Resolved

- [x] 7.1 ~~The reported `chartw=full` stacked-bar bug~~ — **not a bug.**
      `chartw=full` works; the row had been sized with `progressw=full`, which
      a `stackedbar=` silently ignores. The shared geometry, the model flag and
      the parsing were all verified correct (`FullWidthAccessoryTests`), which
      is why nothing turned up. Nothing in the stretch path changes.

      This is the failure this whole change exists to prevent, and it argues for
      one addition beyond a rename notice — see 1.7.

- [x] 1.7 A sizing parameter aimed at an accessory the row does not carry is
      silently ignored today, which is exactly how the report above happened.
      When a deprecated parameter names a different family than the row's
      accessory (`progressw=` on a `stackedbar=` row), say so in the diagnostic
      rather than only naming the replacement. A row with no accessory at all
      stays silent — that is a plugin mid-edit, not a mistake.
