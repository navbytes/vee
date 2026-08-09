# HANDOFF — fix/parser-hardening (unit u1)

Branch: `fix/parser-hardening`
Worktree: `/Users/naveen/repos/vee/.claude/worktrees/agent-a925ddf986f3916c2`
Build/test: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, isolated build path `/private/tmp/claude-501/-Users-naveen-repos-vee/8623f419-ec5b-4d5c-9bc1-b148844004e8/scratchpad/build-u1`

## Fix 1 — unbounded recursion → SIGSEGV (CRITICAL)

`Sources/VeePluginFormat/OutputParser.swift`

- Capped `convert`/`convertItem` at `maxDepth = 64` (mirrors `JSONOutputParser`), dropping deeper submenu/alternate nodes and emitting `"submenu depth exceeded; truncated"` — exactly what DECISION D1 asked for.
- **Deviation / extra fix required**: capping the conversion step alone was **not sufficient**. I verified this empirically — after the convert/convertItem-only fix, the regression test still crashed with SIGSEGV (signal 11). Root cause: `buildTree` links `BuildItem` (a `class`) instances into a chain via `children: [BuildEntry]`, one nested inside the next, with no depth bound. Even though `convert`/`convertItem` no longer recurse past depth 64, the *underlying* 20000-deep `BuildItem` object graph still gets built, and when it's released (ARC dropping `root` at the end of `buildTree`), Swift recursively deinitializes it one level at a time — a second, independent stack-overflow path the ticket's prescribed fix doesn't cover.
  Fix: also clamp the depth computed during tree *construction* (`let depth = min(rawDepth, openItems.count, maxDepth)`), so the `BuildItem` graph itself never nests past 64 levels — deeper lines become siblings at depth 64 instead of children. This emits the same `"submenu depth exceeded; truncated"` diagnostic (deduped via a local flag, since a 20000-line pathological input would otherwise re-trigger it on every remaining line). The existing "submenu depth jumped; clamped to N" diagnostic/behavior for depth *jumps* (unrelated cause) is untouched and still covered by its own test.
  Both caps are kept: the buildTree-level one is the actual fix for the crash; the convert/convertItem one is what D1 asked for and is a harmless, low-cost second guard (effectively unreachable once the tree-level cap is in place, but protects against any future code path that builds a `BuildEntry` tree some other way).
- Regression test: `OutputParserTests.testDeeplyNestedSubmenuDoesNotCrash` (20000 progressively-deeper `--` lines). Confirmed it crashes the test process (signal 11) on unfixed code and on the convert-only fix; passes after the full fix. Runtime ~26s in isolation — inherent to constructing/scanning genuinely dash-encoded depth at that scale (`classify`'s leading-dash count is O(line length)), not a regression from this change.

## Fix 2 — `\|`/`\n`/`\\` escaping (MAJOR)

`Sources/VeePluginFormat/LineParser.swift`:
- `splitTextAndParams` now scans char-by-char for the first *unescaped* `|` (an escaped `\|` no longer splits text from params), unescaping `\|`→`|`, `\n`→newline, `\\`→`\` in the text as it scans.
- `parseParams`'s quoted-value scanner extends its existing `\"` handling with the same three escapes via a shared `unescape(_:)` helper. Bare (unquoted) values are untouched (out of scope per D4's "item text and quoted values").
- No new stored properties added to `LineParams` — all logic lives in the tokenizer functions, per the CRITICAL SAFETY note (nt lesson X20HD3).

SDKs (`plugins/src/vee.ts`, `plugins/python/vee.py`, `plugins/go/vee.go`): added a shared `escapeText`/`_escape_text`/`escapeText` helper (escapes `\`→`\\`, `|`→`\|`, newline→`\n`, backslash first to avoid double-escaping). `item()`/`title()` now always escape the text argument. `quote()`/`_quote()`/`quote()` now also escapes values before quoting, and quotes whenever a value contains whitespace, `|`, **or backslash** (added backslash to the quoting trigger — a bare/unquoted value is never unescaped by the parser, so anything needing an escape must go through the quoted path).

No existing fixture needed regeneration — verified no existing example's text/param values contain `|`, backslash, or newline.

Regression tests (same original text/expected escaped line hardcoded identically in all four, proving cross-language parity):
- Swift: `LineParserEdgeCaseTests.testEscapedPipeAndNewlineRoundTripsThroughOutputParser` (+ lower-level `testEscapedPipeInTextIsNotTreatedAsDelimiter`, `testEscapedNewlineInTextUnescapesToRealNewline`, `testEscapedBackslashInTextUnescapesToSingleBackslash`, `testUnrecognizedBackslashSequenceIsLeftLiteral`, `testQuotedParamValueUnescapesPipeNewlineAndBackslash`).
- TS: `plugins/test/escaping.test.ts` (new file).
- Python: `plugins/python/test/test_escaping.py` (new file).
- Go: `plugins/go/vee_test.go` (new file — first test file directly under `plugins/go/`, `package vee`, so it can exercise `Menu`/`Section` like the others; per the task's file scope this had to be a flat `plugins/go/*_test.go`, not nested under `examples/`).

I could not literally pipe SDK stdout into the Swift parser (no cross-process harness exists in this repo). Instead the same hardcoded escaped-line literal is asserted independently in all 4 test suites: the 3 SDK tests assert their `escapeText`/`quote` output equals it byte-for-byte, and the Swift test asserts `OutputParser.parse` turns that exact literal back into the original text. Together they prove the round trip transitively.

## Fix 3 — silent-drop diagnostics (MINOR)

- **3a href/abouturl**: `LineParser.mapParams` (`href=`) and `HeaderParser.parse` (`<xbar.abouturl>`) now emit `"href= has a missing or unsafe url; dropped"` / `"abouturl has a missing or unsafe url; dropped"` on the same `URLScheme.isSafeToOpen` gate WidgetCardParser already uses. `HeaderParser.parse` had no diagnostics channel at all, so I added `public var diagnostics: [ParseDiagnostic] = []` to `HeaderMetadata` (purely additive, default `[]`, doesn't change `HeaderParser.parse`'s signature — kept it source-compatible with its 5 existing external call sites in `VeePreferences`/`VeeApp`/`VeeUI`, none of which I'm allowed to touch).
  Tests: `LineParserEdgeCaseTests.testUnsafeHrefSchemeEmitsDiagnosticAndDrops`/`testSafeHrefEmitsNoDiagnostic`; `HeaderParserTests.testAboutURLUnsafeSchemeEmitsDiagnostic`.
- **3b duplicate params**: `mapParams` tracks seen keys and emits `"duplicate parameter 'k'"` on a repeat (still last-wins, now signaled). Applies uniformly to every key including `paramN`/unknown keys.
  Tests: `testDuplicateParameterEmitsDiagnostic`, `testDistinctParametersEmitNoDuplicateDiagnostic`.
- **3c image validation**: `image=`/`templateImage=` now go through `validatedImage`, which requires `Data(base64Encoded:options:.ignoreUnknownCharacters)` (same lenient decode `SymbolImageFactory` uses) to succeed and decode to ≤2MiB; failure emits a diagnostic and drops the value instead of forwarding a payload the renderer would silently fail to draw.
  Tests: `testInvalidBase64ImageEmitsDiagnosticAndDrops`, `testOversizedBase64TemplateImageEmitsDiagnosticAndDrops`, `testValidBase64ImageIsKeptWithNoDiagnostic`.

## Fix 4 — docs (MINOR)

`docs/_content/plugin-authoring.md`: fixed the `ansi` parameter table row and the "ANSI color" section to state ANSI is interpreted **by default** (`ansi=false` disables), matching the test-pinned parser behavior. Added a short note under "Line parameters" documenting the new `\|`/`\n`/`\\` escaping and that the bundled SDKs handle it automatically.

## Verification

- `swift test --filter VeePluginFormatTests` — 195 tests, 0 failures.
- `cd plugins && npm test` — 10 tests (6 drift + 4 new), 0 failures.
- `cd plugins/python && python3 -m unittest discover -s test` — 5 tests (1 drift + 4 new), 0 failures.
- `cd plugins/go && go test ./...` — all packages ok (including new `plugins/go/vee_test.go`).
- Full `swift build` (whole package) succeeds; spot-checked `VeeRuntimeTests`/`VeeCLITests` (directly downstream of `VeePluginFormat`) also green.
