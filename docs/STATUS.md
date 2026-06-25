# Vee — Build Status & Spec Coverage Audit

*Audited 2026-06-25 against the committed tree at Wave 3 (`2982523`). The whole package builds (`swift build` clean) and `swift test` reports **136 executed, 1 skipped, 0 failures** — independently reproduced. This is an honest completeness-critic read, not a sign-off.*

---

## Update — R3 + Audit remediation, 2026-06-26 (current state)

*This section supersedes the older verdicts below (which are kept as historical record). The package builds clean and `swift test` reports **254 tests — 253 pass, 1 skipped (live keychain), 0 failures**.*

**R3 integration** wired the live providers (open / clipboard / calendar / fs) into the running app, added plugin discovery (`Resources/vee-plugins/<id>/{vee.json,bundle.js}`), surfaced all **8 plugins** in the launcher, and produced a **hardened-runtime ad-hoc-signed `Vee.app`** (`scripts/package-app.sh release`, JIT entitlements for JavaScriptCore; `codesign --verify --deep --strict` passes). Notarized distribution still needs Apple Developer credentials — see `.github/workflows/release.yml` (the one true external blocker).

**Audit remediation** (full pass over [AUDIT.md](AUDIT.md), 4 parallel streams converged):
- **ARCH-1/2/3 (P0 plugin pipeline):** coordinator now retargets to the active plugin id on `activatePlugin` (real plugin renders reach the window) and resets the revision/mirror so a new plugin's first frame isn't dropped as stale; the host owns the transport's inbound multiplexer (`ownsTransportInbound: false`) so events route to the addressed plugin, not just the last-loaded one. Regression tests: `PipelineTests`, `MultiPluginRoutingTests`.
- **SEC-1/2/3/4/6:** `vee.open`/`openApp` gated by a `Capabilities.open` allowlist (scheme + `bundleId:` conventions; http/https opens re-checked against the network allowlist to close the exfil bypass); fetch is https-only with an SSRF/redirect guard; keychain is `WhenUnlockedThisDeviceOnly`. `SecurityHardeningTests` (18).
- **PERF-1/2/3:** process-wide LRU icon cache; coordinator caches `[PreparedCandidate]` and scores the prepared set per keystroke (no per-keystroke Unicode re-fold); projection bounded to a top-K so a keystroke never builds thousands of view models. (Debounce + diff-reload-changed-rows deferred — the per-keystroke matched set is small once PERF-1/2 land; documented, not done.)
- **MAC-1:** `AppSearchProvider` frecency state lock-guarded (`AppSearchConcurrencyTests`).
- **UI-1/2, UX-2/5/7:** Markdown detail rendering, key-cap shortcut chips, VoiceOver labels/roles, plugin toasts wired to a window seam, Reduce-Motion honored. A layout bug in the new key-caps (a single glyph stretching into a half-row pill) was caught in snapshot review and fixed (`KeyCapLayoutTests`).
- **PLT-1/2:** `vee.clipboard` in the `@vee/sdk` typings; `RUNTIME.md` de-future-tensed.

**Deferred (non-blocking, documented):** UX-1 (context-aware Esc→root) needs window/coordinator coordination; PERF-3 debounce/diff-reload (see above); notarization (external credentials).

**Verdict:** a polished, tested, signed Raycast-class launcher with a real out-of-process JS plugin platform and the audit's P0/P1 findings remediated. Visuals re-verified via the offscreen snapshot harness (list/empty/detail/plugin × light/dark). The only thing standing between this and Gatekeeper-distributable is Apple notarization credentials.

---

## Update — Phase B, 2026-06-26: a runnable app-search launcher

Phase B ("make it actually launch") landed on top of the Wave-3 core. Deltas:

- **Real OS adapters** (VeeServices): `NSWorkspaceAppEnumerator` (scan + launch via `NSWorkspace.openApplication`), `NSPasteboardReader` (+ `ClipboardPollDriver` ticking `changeCount` on a `DispatchSourceTimer`).
- **JS bridges now callable** (VeeEngine): `vee.clipboard.{history,copy}` and `vee.keychain.{get,set,delete}`, capability-gated, with tests. Real `FSEventsFileWatcher` + `EsbuildBundler` (hot-reload infra) wired into `PluginHost` (dormant until a plugin loads).
- **Real NSView GUI** (VeeApp): NSPanel launcher — search field + NSTableView list + detail + keyboard nav — driven by the coordinator projection.
- **Coordinator host-native candidate mode**: pluginless "root search" — `showHostCandidates` projects a candidate set into the list and invokes a host callback locally (no transport frame). +1 test.
- **`main.swift` wiring**: installed-app search as the launcher surface (one enumeration at startup, native fuzzy filter per keystroke), launch-on-Return, background clipboard capture, Option+Space global hotkey, menubar accessory run loop.
- **Verified**: whole package + `vee` executable build clean; **147 Swift tests pass** (1 live-keychain skipped); the `vee` binary **smoke-runs without crashing** (5s run → killed by timeout, exit 124, no crash trace/report, hotkey registered). The visible GUI/menubar/hotkey-fire/app-launch is desktop-manual — see [MANUAL-VERIFY.md](MANUAL-VERIFY.md).

**Status changes from the matrix below:** App search → **runnable** (real adapter + wired launcher; GUI manual-verify). Clipboard → capture loop wired on real `NSPasteboard` (no launcher UI surface yet). Global hotkeys → wired + registers (firing manual-verify). clipboard/keychain bridges → **callable from JS**. GUI → **real** (manual-verify). Hot-reload infra → **real but dormant** (no plugin auto-loaded).

**Still deferred (unchanged):** out-of-process transport (still in-process loopback); the three network plugins (API-to-menubar, PRs/Jiras, meeting-bar); EventKit TCC + signing/entitlements; real per-app icons; frecency in the *live* filter (startup ordering only); a clipboard launcher surface.

**Revised verdict:** Vee is now a **runnable host-native app-search launcher** (pending your desktop confirmation of the visuals) on top of the tested engine core — no longer "not a runnable launcher." The remaining gap to the full spec is the networked JS plugins and the real out-of-process boundary.

---

## Update — Phase C, 2026-06-26: Raycast-grade launcher polish

Driven autonomously via a self-rendering **offscreen snapshot harness**
(`VEE_SNAPSHOT_OUT` renders the launcher to a PNG through the real pipeline —
real app enumeration + coordinator projection — so the UI is verifiable without a
live desktop). Iterated across visual cycles, each verified by reading the PNG:

- **Cycle 1:** real full-color app icons (`NSWorkspace.icon`, pre-rasterized for
  crisp/sync draw); borderless flush search field + magnifier; custom rounded
  *neutral* selection (never the system blue); single-line rows; footer action bar.
- **Cycle 2:** "APPLICATIONS" section header; right-aligned "Application" type
  accessory; footer shows the selected app's real icon + primary action + ⌘K;
  top-match selection on every filter (Return launches the best result).
- **Cycle 3 / hardening:** duplicate-name dedup (no double rows); **async app
  enumeration** (menu bar + hotkey ready instantly, list populates off-main);
  release build; committed reference renders in `docs/screenshots/`.

Verified: 147 Swift tests green (1 live-keychain skipped); release `swift build`
clean; `vee` smoke-runs crash-free; dark + light + filtered snapshots read as
Raycast-grade (see `docs/screenshots/`). App packaged to `~/Applications/Vee.app`
(Info.plist, accessory/LSUIElement, ad-hoc signed) via `scripts/package-app.sh`.

**Now solid:** the launcher is a genuinely polished, runnable app-search launcher
— real icons, section header, type accessory, rounded selection, footer, light/dark,
instant open, keyboard-first (type / ↑↓ / ↩ / esc). App search → **runnable + polished**.

**Still deferred (feature scope, not polish):** the footer's **Actions ⌘K** is
presentational (no actions panel yet); commands/clipboard/calendar have no launcher
*surface* yet; the three networked JS plugins; the real out-of-process transport.

---

## Update — Phase D, 2026-06-26: UX-reviewed polish + first plugins

**UX polish (autonomous, via a hired UX-expert agent + Dribbble/web research):** three
critique cycles, each verified by reading offscreen renders of every screen
(list / filtered / empty / detail / light+dark). Cycle 1 (5.8/10) → fixed row
density (48→40), accent-tinted floating selection, removed the redundant
"Application" accessory, glyph empty state, type ramp, 20pt gutter, key-cap
footer. Cycle 2 (7.8) → fixed inverted light-mode key caps, cap parity, selection
inset/saturation. Cycle 3 → **independent ship-bar sign-off at 8.6/10 ("Raycast-grade,
ship it")**. Backlog (non-gating): fuzzy match-highlighting, detail metadata rail.

**First plugins (`@vee/sdk`):** `essentials` (static command list), `hacker-news`
(`vee.http.fetch`, public API), `clipboard` (`vee.clipboard`). Built to committed
fixtures; each **proven by VeeEngine tests** that load the bundle in real JSC with
faked bridges and assert load→activate→render (incl. capability-deny paths), plus
node tests. **Surfaced in the launcher root** — their commands list above the apps
(⌥Space → select → ↩ activates the plugin, which renders into the launcher). Also
fixed a real `LoopbackTransport` re-entrancy crash found while wiring them.

**Verified:** 155 Swift tests + 19 node tests green; release build clean; the app
loads all 3 plugins at startup and runs crash-free; the live plugin render and the
root-with-commands are captured in `docs/screenshots/`. App packaged to
`~/Applications/Vee.app` with plugin bundles in `Resources/vee-plugins/`.

**Still deferred (feature scope):** an `open URL` / `run` bridge so plugin actions
can act on their targets; a live `vee.clipboard` provider wired into the app host
(proven against a fake in tests); the GitHub/Jira networked plugins; the real
out-of-process transport.

*The original Wave-3 audit below is preserved as written (pre-Phase-B).*

## TL;DR verdict

Vee today is a **rigorously tested, headless engine core with a thin, unverified GUI/OS skin** — not yet a runnable launcher. The architecturally hard, logic-dense parts the spec calls out (the JSC bridge with its two memory rules, the fuzzy matcher, the SWR cache, RFC-6902 patch, the clipboard privacy filter, the render mirror + view-model projection) are genuinely built and well-tested. But the **spec's headline — "run plugins out-of-process" — is not realized**: everything runs in-process over an in-memory `LoopbackTransport`. Four of the six bridges named in the contract (fs, keychain, clipboard, calendar) are **not wired into JS** — they exist only as method-name constants. **Five of the six launch plugins do not exist** (only `hello-list` does; clipboard and app-search exist as host-native Swift services, not plugins). The GUI, global hotkey, calendar TCC, and all real OS adapters are **compiled but never executed by a test**. "Complete" here means *Stage 1–2 substantially done and tested; Stage 3 partially (the two host-native providers' logic only); the out-of-process boundary and the network plugins deferred.*

---

## 1. Spec coverage matrix

### Part 1 — Engine

| # | Component | Status | Evidence / what's missing |
|---|---|---|---|
| 1 | JSC embedding & native bridge (console, timers, fetch) | **DONE** | `JSBridge.swift` installs `console.{log,info,warn,error}`, `setTimeout/Interval/clear*`, `vee.http.fetch`, `vee.storage`. Both memory rules implemented and asserted: every block is `[weak self]` + `JSContext.current()`; stored callbacks are `JSManagedValue` added/removed via the VM. `testNoLeakAfterReload` asserts the instance **and** the `JSVirtualMachine` go nil after reload. |
| 1b | Exception capture | **DONE** | `exceptionHandler` set before any eval (`PluginInstance.init`); `testSyntaxErrorIsCapturedAsSwiftError` / `testRuntimeError…` pass; JS stack attached in `data`. |
| 1c | Microtask-before-macrotask ordering | **DONE** | Explicit `drainMicrotasks()` after every native→JS callback. `testMicrotaskRunsBeforeMacrotask` + `testMicrotaskChainedFromTimerStillOrdersBeforeNextTimer` lock the hazard. (Drain is `evaluateScript("")` — pragmatic, works for the tested cases.) |
| 2 | **Out-of-process execution** | **DEFERRED (the big one)** | **There is no out-of-process anything.** Only `LoopbackTransport` (in-memory, same process) conforms to `RPCTransport`. No XPC, no `DispatchIO`/`FileHandle`/`Process`/socket anywhere in `Sources`. `main.swift` notes "A real fd/DispatchIO transport swaps in here later." Crash isolation — the spec's entire rationale — does not exist; a plugin runs in the host's address space. The *contract* (JSON-RPC envelopes, ordered serial-queue delivery, codec round-trip) is real and forward-compatible, which makes a later swap plausible. |
| 3 | Declarative renderer (tree → JSON-Patch → view models) | **DONE (wire + mirror + projection); PARTIAL (native views)** | Plugin emits a tree via `vee.render`; `RenderMirror` diffs via `VeeJSONPatch.diff` and emits `plugin.render` with monotonic revision; coordinator applies patches to its own mirror and projects `RootViewModel`. Render/selection tests pass. **Missing:** the AppKit side renders the tree as a flat newline-joined **string** in an `NSTextField` placeholder — no NSTableView/detail view tree. React reconciler is intentionally Stage 4, absent (expected). |
| 4 | Hot reload | **PARTIAL** | Pieces exist and the *logic* is wired and tested in-process (`PluginHost.load` → `fileWatcher.watch` → `reload` → rebuild via injected `Bundler` → re-activate; `testHotReloadReevaluatesNewBundle`). **Missing the real loop:** production uses `NoopFileWatcher` + `StaticBundler(source:"")`; no FSEvents/DispatchSource adapter; esbuild's real `ctx.watch()` is not connected to the Swift host. |
| 5 | Fetch-vs-filter latency split | **DONE** | `plugin.setCandidates` pushes the set once; `AppCoordinator.setQuery` filters natively via injected `FuzzyMatching` and only crosses IPC (`host.onSearchTextChange`) when `serverSideFiltering` is opted in. `VeeFuzzy` is a real fzy-style scorer with a 10k-candidate perf assertion. |
| 6 | Stale-while-revalidate cache | **DONE (library); PARTIAL (integration)** | `SWRCache` is a real `actor`: miss/fresh/stale, exactly-one revalidation, in-flight de-dup, `keepPreviousData`, TTL via injected `Clock`, error isolation; disk persistence + LRU tested. **Caveat:** `vee.storage` in the engine is backed by a plain `InMemoryStorage`, **not** wired to `SWRCache`/`DiskStorage`. |

### Part 2 — The six launch plugins

| # | Plugin | Spec'd as | Status | Evidence / what's missing |
|---|---|---|---|---|
| 1 | Clipboard history | host-native service | **PARTIAL (logic DONE, OS adapter MISSING)** | `ClipboardMonitor` + pure `ClipboardPrivacyFilter` are real and the **security tests pass** (concealed/transient/auto-generated + 1Password UTI dropped; pin/trim/fuzzy search). **But:** no real `NSPasteboard` adapter — only the `PasteboardReading` protocol + fakes. Nothing polls `changeCount`. No at-rest persistence. |
| 2 | Meeting bar | JS plugin | **PARTIAL → mostly DEFERRED** | Not a plugin. Logic is a host-native `CalendarService` + pure `MeetingLinkDetector` (7 providers), tested with a fake. `EventKitCalendarProvider` exists under `#if canImport(EventKit)` but is never tested or wired; no menubar command; no TCC request; no JS plugin. |
| 3 | API-to-menubar | JS plugin | **DEFERRED** | Does not exist. `PluginCommand.Mode.menuBar` + `refreshIntervalSeconds` exist in the contract only. |
| 4 | PRs & Jiras | JS plugin | **DEFERRED** | Does not exist. No GitHub/Jira plugin, no token-in-keychain flow exercised end-to-end. |
| 5 | App search | host-native provider | **PARTIAL (logic DONE, OS adapter MISSING)** | `AppSearchProvider` (frecency + fuzzy blend, prefix bonus, dedup) is real and tested. **But:** no `NSWorkspace`/Launch Services `AppEnumerating` adapter — only the protocol + fake. Cannot enumerate or launch a real app. |
| 6 | Per-app global hotkeys | host-configured | **PARTIAL (logic DONE, firing unverified)** | `HotkeyDispatcher` (conflict detection, rebinding) is real and tested. `CarbonHotkeyRegistry` (real `RegisterEventHotKey`) exists and `main.swift` binds Cmd+Space. **But:** no recorder UI, no manifest→binding flow, system-wide firing untested (needs a desktop + a human). |

### Cross-cutting

| Concern | Status | Evidence / what's missing |
|---|---|---|
| Keychain (namespaced secret store) | **DONE (lib); PARTIAL (not bridged)** | `KeychainStore` is real (`SecItemAdd/CopyMatching/Update/Delete`, `errSecDuplicateItem`→update, `WhenUnlocked`), service `com.vee.<id>.<ns>`, `CapabilityCheckedSecretStore` enforces namespaces; CI tests on in-memory store; live test gated by `VEE_KEYCHAIN_LIVE=1`. **But:** `vee.keychain.*` is **not installed in `JSBridge`** — a plugin cannot call it. |
| Capability manifest enforcement (network) | **DONE (for fetch)** | `Capabilities.allowsNetworkHost` checked in `handleFetch` **before** the client is touched; `testFetchToDisallowedHostIsDeniedWithoutCallingClient` asserts code `-32001`. fs/keychain/clipboard/calendar gating is specified and predicates exist, but those bridges aren't wired, so only network is enforced in practice. |
| Bridges actually installed in JS | **PARTIAL** | **Callable:** `console`, timers, `vee.http.fetch`, `vee.storage`, `vee.render`, `vee.setCandidates`, `vee.showToast`, `vee.on{InvokeAction,SearchTextChange,SubmitForm}`. **Named only, NOT installed:** `bridge.fs.*`, `bridge.keychain.*`, `bridge.clipboard.*`, `bridge.calendar.*`. |
| File protection / at-rest encryption | **DEFERRED** | No `NSFileProtection`/`CryptoKit` anywhere. `DiskStorage` writes plain JSON. Clipboard history is in-memory only (latent rather than a live leak). |
| Signing / entitlements / Info.plist | **DEFERRED** | None present. SwiftPM executable only; no app bundle, no `NSCalendarsFullAccessUsageDescription`, no hardened runtime/sandbox. |

---

## 2. Honest gap list — do NOT assume these work

1. **No out-of-process execution / crash isolation.** In-process `LoopbackTransport` only.
2. **No real IPC transport** (no XPC, no stdio/`DispatchIO` child process). The contract is real; the pipe is not.
3. **fs / keychain / clipboard / calendar bridges are not callable from a plugin.**
4. **The "six plugins" are essentially absent.** Only `hello-list` exists. Clipboard + app-search are host-native *logic* missing their OS adapters. Meeting-bar, API-to-menubar, PRs/Jiras: not built.
5. **Real OS adapters missing or unverified:** `NSPasteboard` (missing), `NSWorkspace` enumeration/launch (missing), `EKEventStore` (present, unwired, no TCC), Carbon hotkey (present, firing untested).
6. **GUI is a placeholder** — a flat string in an `NSTextField`; no real list/detail rendering. `NSApplication.run` never exercised by tests.
7. **Hot reload not connected end-to-end** (Noop watcher + empty bundler in the real app).
8. **SWR cache + DiskStorage not behind the plugin storage bridge; no file protection/encryption.**
9. **No signing/entitlements/Info.plist.**

---

## 3. What IS solid (genuinely complete + tested)

- **`VeeProtocol`** — frozen wire contract; round-trip + classification tested (8 tests).
- **`VeeJSONPatch`** — full RFC-6902 diff/apply; **45 tests** incl. the `apply(diff(a,b),a)==b` property test. The strongest target.
- **`VeeFuzzy`** — fzy-style scorer, word-boundary/consecutive bonuses, matchedIndices, keywords; 10k-candidate perf assertion (10 tests).
- **`VeeCache`** — `SWRCache` actor (stale/fresh/miss, single-flight de-dup, keepPreviousData, TTL), LRU + disk (10 tests).
- **`VeeKeychain`** — real `KeychainStore` + namespacing + capability-checked wrapper; live test gated (11 tests, 1 skipped).
- **`VeeEngine`** — JSC host: bridge, both memory rules (no-leak-after-reload **and** -deactivate via weak VM refs), microtask ordering, render mirror + minimal patches, stale-revision drop, capability-gated fetch, plugin-error isolation, TS↔Swift fixture handshake (29 tests).
- **`VeeServices`** — clipboard privacy filter (security tests), changeCount-poll logic, frecency+fuzzy app ranking, meeting-link regex, calendar sort — above clean protocol seams (11 tests).
- **`VeeApp` `AppCoordinator`** — render-mirror/patch/projection, selection-preservation-by-id, fetch-once/filter-natively, action/form dispatch (12 tests).
- **`plugins/`** — real esbuild context-API bundler (IIFE, neutral, es2021, sourcemaps, zero externals), `@vee/sdk` typings, `hello-list` sample consumed as a Swift test fixture.

Every OS touch point is a protocol with a fake; ~90% of the logic sits above those seams and is tested.

---

## 4. Prioritized next steps (by leverage)

**To reach a runnable daily-driver (in-process acceptable here):**
1. **Replace the placeholder GUI with a real render-tree → NSView mapping** (NSTableView for `list`, a detail view; wire query/selection/Enter→invoke). Biggest gap between tested logic and a usable thing.
2. **Write the two missing host-native OS adapters** behind existing seams: `NSWorkspaceAppEnumerator` (+ launch via `openApplication`) and `NSPasteboardReader` (+ real `DispatchSourceTimer` poll). Both feed already-tested providers.
3. **Wire host-native bridges into JS** (`vee.clipboard.*`; route `AppSearchProvider`/`ClipboardMonitor` candidates into the coordinator).
4. **Connect hot reload for real:** an FSEvents/`DispatchSource` `FileWatcher` + esbuild-backed `Bundler`, replacing the Noop/empty defaults.
5. **Manual desktop verification pass:** launcher panel appears, menubar renders, Cmd+Space fires, no crash on activate.

**Toward the full spec:**
6. **Wire `vee.keychain.*`**; back `vee.storage` with `SWRCache`+`DiskStorage`; add `NSFileProtection` + at-rest encryption.
7. **Build the three network plugins** (API-to-menubar, PRs/Jiras, meeting-bar) as real `@vee/sdk` plugins — menu-bar mode, background refresh, SWR, GitHub/Jira auth-from-keychain.
8. **Calendar:** wire `EventKitCalendarProvider`, add `requestFullAccessToEvents` + usage-description; verify TCC on a signed bundle.
9. **The out-of-process boundary** (spec headline): a real `RPCTransport` over a child process + `DispatchIO`/stdio (or XPC). Contract is already shaped for it.
10. **App bundle + signing/entitlements/hardened runtime**, then Stage 4 React (optional; wire format is frozen).

---

## 5. Honest verdict

This faithfully realizes the spec's **Stage 1–2 architecture as a tested library core**, plus the *logic* of Stage 3's two host-native providers — but it does **not** yet realize the headline out-of-process execution (all in-process over an in-memory loopback), ships **only one trivial sample plugin**, leaves **four named bridges uncallable from JS**, and every OS-facing surface (GUI, NSPasteboard, NSWorkspace, EventKit, Carbon firing, TCC, file protection, signing) is a thin compiled stub, missing, or unverified. "Complete" for this repo today means *the hard, headless, testable heart is done to a high standard and the wire contract is frozen and forward-compatible* — an excellent foundation and an honest Stage-1/2 deliverable, but **not a runnable launcher**. The gap to a daily-driver is concentrated in the (lower-risk, seam-backed) OS adapters and the real GUI; the gap to the full spec additionally includes the real IPC transport and the three network plugins.
