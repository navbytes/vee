# HANDOFF — search-panel/native-menu parity + title sanitization + deep-link gating

Branch: `fix/panel-parity`. Worktree: `/Users/naveen/repos/vee/.claude/worktrees/agent-ae23eb3f288b939ad`.

## Fix 1 — [MAJOR] submenu-parent action fires only in the panel (D2)

`Sources/VeeSearch/MenuFlattener.swift`: `walk` used to emit `.action` for
any actionable item regardless of whether it also had a submenu.
`MenuBuilder.makeItem` (Sources/VeeMenu/MenuBuilder.swift:95-101, unedited —
it's already correct/the reference) wires EITHER a submenu OR an action,
never both, so such an item is inert-on-click natively.

New `entry(for:path:)` helper: `.action` iff enabled, actionable, **and**
`item.submenu.isEmpty`. A submenu-having item now always emits `.info`
(searchable, non-activating); its children still recurse in exactly as
before. Comment preserved per brief: "a destructive `shell=` on a
submenu-parent that never fires in the menu bar must not fire from the
panel."

`testClickableParentEmittedAndRecursed` rewritten to assert the new parity
behavior (was asserting the reversed PR #80 behavior) — fails against the
old code, passes now. Also added a direct assertion that
`MenuFlattener.flatten` (the `.action`-only view `MenuSearch` ranks against)
excludes the parent entirely.

## Fix 2 — [MAJOR] `alternate=true` invisible to the panel (D3)

Same file. `OutputParser` attaches `alternate=true` as `MenuItem.alternate`
(a property, via `alternateStorage`), not a `MenuNode` child, so the old
submenu-only walk never saw it. `walk` now also flattens `item.alternate`
(when present) right after the item's own subtree, as a peer at the item's
own breadcrumb level (mirrors `MenuBuilder.fill` adding it as the next
sibling `NSMenuItem`), through the same `entry(for:path:)` helper — so an
alternate with its own submenu is correctly non-activating too (D2 applies
uniformly). Alternate's own children (if any) descend under the alternate's
own text as their breadcrumb segment.

Tests: `testAlternateItemFlattenedAsSearchableActivatableRow` (regression —
alternate now appears in both `flattenEntries` and the `.action`-only
`flatten`) and `testAlternateWithSubmenuIsInfoNotActionButChildrenDescend`
(D2 × D3 interaction).

Not handled (deliberately, out of scope — nonsensical combo, no test
requires it, mirrors how `VeeMenuTests` treats the native side too):
`alternate=true header=true` together. `MenuBuilder` already has a pinned
"degrades gracefully" test for its own side (`VeeMenuTests.swift:216`); the
flattener doesn't special-case it and just treats the alternate as a plain
row.

## Fix 3 — [MAJOR] unsanitized plugin text corrupts the menu bar (D6)

`Sources/VeeApp/StatusItemController.swift`. Added
`sanitizedTitleText(_:)` (`nonisolated static`, pure `String -> String`) and
a `sanitizedTitle(_:NSAttributedString)` wrapper, applied at the single
choke point every `attributedTitle` setter reads from: `frames =
presentation.frames.map(Self.sanitizedTitle)` in `render(_:)`. Every
setter (standalone button, compact row, cycling frame, dim/undim) draws
from `frames`/`compactBaseTitle`, so one edit covers all of them.

Sanitizer: repairs UTF-8 via `String(decoding:as:)` (a no-op in practice —
Swift strings are always valid Unicode — but enforces the requirement
explicitly), strips true Unicode-category-Cc control characters (checked via
`Unicode.Scalar.Properties.generalCategory`, **not**
`CharacterSet.controlCharacters`, which turned out to also cover category Cf
— see pitfall below), keeps ordinary whitespace/newlines, and caps at
`maxTitleLength` (60) with a trailing "…". A title that needed no change is
returned untouched (ANSI styling preserved); one that needed
stripping/capping falls back to its first run's attributes uniformly
(ponytail: losing per-run styling on an already-malformed/hostile title is
an acceptable trade — noted in code).

**Pitfall caught by a test, fixed before landing:** `CharacterSet.
controlCharacters` covers Cc *and* Cf. Cf holds RTL/LTR marks and the ZWJ
that joins compound emoji — a first draft using that set stripped RTL marks
and would have broken ZWJ-joined emoji (e.g. family emoji). Switched to
checking `scalar.properties.generalCategory != .control` (precisely Cc)
instead, keeping whitespace/newlines as an explicit carve-out.

Tests (new file `Tests/VeeAppTests/StatusItemTitleSanitizerTests.swift`):
pure-function tests for NUL/control stripping, RTL/whitespace/emoji
preservation, ZWJ-in-compound-emoji preservation, 10k-char capping with
ellipsis; plus two integration tests that go through a real
`StatusItemController.render(_:)` in compact mode
(`CompactMenuBarController(attachesStatusItem: false)`, same
`NSApplication`-free pattern `SearchAllPluginsAggregatorTests` already uses)
and read the rendered `NSMenuItem.attributedTitle` back.

## Fix 4 — [SHOULD-FIX] base64 `image=`/`templateImage=` not shown in panel

`Sources/VeeApp/MenuSearchPanel.swift`. Added `SearchRowIcon.decodedImage(for:)`
(new top-level `enum`, internal access) which defers to `sfimage=` first
(unchanged fast path via `Image(systemName:)`) and otherwise decodes through
`SymbolImageFactory.image(for:)` — the exact cached path `MenuBuilder`'s
native rows already use — rendered via `Image(nsImage:).resizable()`,
`.renderingMode(.template)` when the source is a `templateImage=` (so it
tints with row selection like an SF Symbol) or `.original` for a plain
`image=`. The `.info`-row "only show an icon if declared" behavior now
covers base64 images too, not just `sfimage=`.

Did not half-do this — fully wired, not a ponytail note — because
`SymbolImageFactory` already does all the actual decode/caching work and is
already unit-tested (`VeeMenuTests.SymbolImageCacheTests`); this fix is thin
glue. New `Tests/VeeAppTests/SearchRowIconTests.swift` covers the
precedence/wiring this fix adds (sfimage wins, templateImage → `isTemplate
== true`, plain image → `false`, neither → nil) without re-testing decode
correctness.

## Fix 5 — [MINOR] ungated state-changing deep links (D8) — PARTIAL, see NEEDS

`Sources/VeeApp/URLActionRouter.swift`. Added, entirely within this file:

- `needsConfirmation(_:)` — true for `.disablePlugin`, `.togglePlugin`
  (toggling an enabled plugin off is the identical bypass, so it's gated the
  same as disable — a deliberate reading of "state-changing" slightly beyond
  the ticket's two literal examples; flagged here for ratification), and
  `.notify` **iff** it carries an `href` (title/body-only notify stays
  frictionless).
- `confirmationPrompt(for:)` — human-readable message/info per gated case.
- `confirm: (String, String) -> Bool` — `nonisolated(unsafe) static var`
  seam, defaults to `defaultConfirm` (a real blocking `NSAlert` via
  `MainActor.assumeIsolated`, mirroring `AppController.confirmInstall`'s
  existing `addplugin` gate); tests substitute a canned answer.
- `routeGated(_:) -> URLAction` — parses, then blocks on `confirm` for a
  gated action, returning `.unknown` on decline (which the existing
  `AppController.perform(_:)` switch already no-ops on).

`parse(_:)` itself is **completely unchanged** — it had to stay that way:
the existing, unmodifiable `Tests/VeeAppTests/URLActionRouterTests.swift`
asserts `parse("swiftbar://disableplugin?...")` /
`parse("swiftbar://notify?...&href=...")` deterministically, with no
confirmation involved, for every gated case this fix targets. Gating inside
`parse` itself would either break those tests or make the default answer
meaningless — so the gate lives in a new, additional `routeGated(_:)`
instead, fully built and tested, but **not yet reachable from the running
app**.

**NEEDS — one-line integration gap, requires touching AppController.swift
(out of my scope):** `Sources/VeeApp/AppController.swift:205` —
`public func application(_ application: NSApplication, open urls: [URL]) {
for url in urls { perform(URLActionRouter.parse(url)) } }` — still calls
`parse` directly. Someone owning that file needs to change it to
`perform(URLActionRouter.routeGated(url))`. Until then, the gating logic is
built/tested/ready but inert in production — deep links behave exactly as
before. I stopped short of this per the brief's explicit instruction rather
than edit AppController.swift.

Tests: new `Tests/VeeAppTests/URLActionRouterGatingTests.swift` — disable/
toggle proceed only when confirmed, href-notify proceeds only when
confirmed, href-less notify and enable/refresh never prompt (asserted via a
`confirm` stub that `XCTFail`s if invoked), `addplugin` passes through
ungated here (it has its own gate downstream), and a direct
`needsConfirmation` coverage sweep. Every test save/restores
`URLActionRouter.confirm` in `setUp`/`tearDown`.

## Verification

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter VeeSearchTests --build-path <iso>   # 49/49 pass
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter VeeMenuTests   --build-path <iso>   # 61/61 pass
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter VeeAppTests    --build-path <iso>   # 151/151 pass
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test                          --build-path <iso>   # full repo, 0 failures
```
(`<iso>` = `/private/tmp/claude-501/-Users-naveen-repos-vee/8623f419-ec5b-4d5c-9bc1-b148844004e8/scratchpad/build-u3`)

No fixed sleeps added anywhere; all new tests are synchronous/pure or read
state back immediately after a synchronous call — nothing timing-sensitive
was introduced. No test calls `NSApplication.shared`.

## Files changed

- `Sources/VeeSearch/MenuFlattener.swift` (fixes 1, 2)
- `Sources/VeeApp/StatusItemController.swift` (fix 3)
- `Sources/VeeApp/MenuSearchPanel.swift` (fix 4)
- `Sources/VeeApp/URLActionRouter.swift` (fix 5, partial)
- `Tests/VeeSearchTests/MenuFlattenerTests.swift` (fixes 1, 2 tests)
- `Tests/VeeAppTests/StatusItemTitleSanitizerTests.swift` (new, fix 3 tests)
- `Tests/VeeAppTests/SearchRowIconTests.swift` (new, fix 4 tests)
- `Tests/VeeAppTests/URLActionRouterGatingTests.swift` (new, fix 5 tests)

Not touched: `Sources/VeeMenu/MenuBuilder.swift` (read/verified as the
correct reference implementation, no bug found in it), `AppController.swift`,
`PluginCoordinator.swift`, any `VeeRuntime`/`VeePluginFormat` file, and the
existing `Tests/VeeAppTests/URLActionRouterTests.swift` (all left exactly as
found).
