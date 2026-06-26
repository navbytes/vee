# Vee — Re-Audit (Round 2, post-remediation)

> **REMEDIATION STATUS (2026-06-26):** Release blockers + contained findings fixed — **R2-CRIT-1** (clock deadlock + regression test), **R2-HIGH-1** (CI/release → `macos-26`), **R2-MED-1** (`open:["*"]` exfil waiver closed), **R2-HIGH-2** (per-plugin storage namespace), **R2-MED-2** (leaked timers cancelled on teardown), **R2-MED-6** (SDK `open` capability parity) — and the §6 honesty gaps reconciled (STATUS no longer claims a live OOP platform; counts refreshed). `swift test` 259 / 1 skip / 0 fail. **Still open (triaged, larger efforts):** R2-CRIT-2 (wire the OOP host into production + §5 hardening), R2-HIGH-3 (plugin authenticity/signing), R2-HIGH-4 (`⌘K`), R2-MED-3/4/5/8. See the Round-2 section in [STATUS.md](STATUS.md). Findings below are the original re-audit; check current source before acting.

*Audited 2026-06-26 against `HEAD = 5f34af3` (working tree clean). Follows the original [AUDIT.md](AUDIT.md) after the remediation pass (commits `8839108 Remediate audit P0/P1`, `7dd8e61 R2a out-of-process host`, `43ad602 R3 wire real providers`, `5f34af3 Liquid Glass / macOS 26`; **+6,937 lines across 36 files**). Build verified clean locally (macOS 26); `swift test` verified **254 executed, 1 skipped, 0 failures**; ~34 node tests pass.*

**Method:** seven parallel specialist passes, each tasked to (a) **independently verify every claimed fix against current source** — skeptically, ignoring docs/comments — and (b) **hunt for new bugs/regressions** in the new code. The orchestrator then re-read the three highest-impact new claims in source: the DispatchClock deadlock (`PluginHost.swift:244-268`), the out-of-process wiring (grep of `Sources/vee`+`Sources/VeeApp`), and the macOS-26/CI conflict — all confirmed.

---

## 1. Executive summary

**The remediation is genuine and high quality.** The original audit's headline disaster — a plugin pipeline broken in three independent places — is **fixed and locked with precise regression tests** (`PipelineTests`, `MultiPluginRoutingTests`). The security gating that was missing is now real and tested (`SecurityHardeningTests`, 18 cases that assert the provider is *never touched* on a denied call). The performance hot spots are fixed (icon LRU, cached `PreparedCandidate`, top-K projection). Most UI/UX/accessibility and macOS findings are genuinely closed. **Of ~37 targeted findings, ~24 are fully Fixed, ~9 Partial, 3 Not-fixed-but-disclosed-deferred, and 1 Regressed.** Test count tripled (84→254) and the new suites are real, not green-theater.

**But the round introduced three serious problems, two of which block a release:**

> **R2-CRIT-1 · [Critical] The production `DispatchClock` deadlocks on every one-shot timer.** A `setTimeout` (one-shot) fires its handler *on the clock's serial queue*, then calls `cancel()` which does `queue.sync` on that same queue → guaranteed deadlock (a trap under Swift's checked dispatch). Any plugin that calls `setTimeout` hangs/crashes the timer subsystem the first time it fires. The 254 tests miss it because they inject a `TestClock`; the one real-`DispatchClock` test never lets a one-shot fire. *(verified: `Sources/VeeEngine/PluginHost.swift:247,253-255,264`)* This is the original **MAC-4 reintroduced**.

> **R2-CRIT-2 · [Critical→architecture] The headline "out-of-process plugin platform" is built and tested but NOT wired into the shipping app.** `Sources/vee/main.swift` still constructs an in-process `LoopbackTransport` and loads every plugin into the launcher's own address space. `ChildProcessHost`/`StdioTransport`/`vee-plugin-host` are referenced **nowhere** outside `Tests/`. So the spec's entire rationale — *a crashing plugin can't take down the launcher* — does not hold at runtime; combined with R2-CRIT-1, a timer-using plugin will hang the launcher itself. `MANUAL-VERIFY.md` even still says "Out-of-process execution is not yet real," directly contradicting STATUS's "a real out-of-process JS plugin platform." *(verified via grep)*

> **R2-HIGH-1 · [High] The macOS-26-only pivot breaks CI/release and drops the user base.** `Package.swift` now hard-targets `.macOS(.v26)` (+ `LSMinimumSystemVersion 26.0`) purely to adopt Liquid Glass, with no `@available` fallback — so macOS 14/15 users (essentially the whole installed base in mid-2026) can't launch it. And every CI/release job `runs-on: macos-15`, whose SDK cannot build a macOS 26 target — so **CI build/test, lint, and the release pipeline all break the moment these commits are pushed**. They're currently *unpushed*, which is the only reason CI still looks green.

**Net verdict.** Code quality, security posture, and test rigor are materially better than Round 1 — the team clearly did the work and verified it. But the build is **not shippable as-is**: the clock deadlock breaks any timer-using plugin, the platform's headline guarantee is unrealized, and the release pipeline is broken by the platform pivot. None of these is hard to fix; all three are concentrated and well-understood.

---

## 2. Verification basis (confirmed first-hand by the orchestrator)

| Claim | Result |
|---|---|
| `swift build` (macOS 26, local) | ✅ clean |
| `swift test` | ✅ **254 executed, 1 skipped, 0 failures** (STATUS's "254 / 253 pass / 1 skip" is accurate) |
| DispatchClock one-shot deadlock | ✅ **confirmed** `PluginHost.swift:247` (timer on `queue`), `:253-255` (handler calls `cancel`), `:264` (`cancel` does `queue.sync`) |
| OOP host wired in app? | ✅ **No** — 0 refs to `ChildProcessHost`/`StdioTransport`/`vee-plugin-host` in `Sources/vee`+`Sources/VeeApp` |
| macOS 26 target vs CI runner | ✅ `Package.swift:31` `.macOS(.v26)`; `.github/workflows/{ci,lint,release}.yml` `runs-on: macos-15` (can't build); 3 remediation commits unpushed |

---

## 3. Fix-verification scorecard

Verdicts are independent reads of current source, not STATUS claims. **Fixed** = genuinely resolved with evidence (usually a regression test); **Partial** = improved but a gap remains; **Not-fixed** = unchanged (×=undisclosed, ⊘=disclosed-deferred); **Regressed** = the fix introduced a new defect.

### P0 (were Critical/High)
| ID | Verdict | Evidence |
|---|---|---|
| ARCH-1 coordinator drops plugin renders | ✅ **Fixed** | `pluginId` now mutable, retargeted in `activatePlugin` (`AppCoordinator.swift:298`), restored in `showRoot` (`:283`); `PipelineTests` proves a plugin render reaches the window |
| ARCH-2 only last plugin gets events | ✅ **Fixed** | `ownsTransportInbound:false` (`PluginHost.swift:124`); host owns the multiplexer (`:73`, routes by id `:226`); `MultiPluginRoutingTests` proves first-loaded plugin still receives events |
| ARCH-3 stale-revision drops first frame | ✅ **Fixed** | `lastRevision`/`mirror` reset in `activatePlugin`/`showRoot` (`AppCoordinator.swift:300-301,284-285`); `PipelineTests` |
| SEC-1 `vee.open` exfil/ungated | ⚠️ **Partial** | Gated by `Capabilities.open` (scheme + http re-checked vs network allowlist, `Manifest.swift:157-166`) — but a `open:["*"]` manifest **waives the re-check** (`:162`), re-opening exfil; non-http schemes hand data to other apps |
| SEC-2 `vee.openApp` ungated | ✅ **Fixed** | `bundleId:` allowlist, denied before provider (`JSBridge.swift:697-708`); `bundleId:*` catch-all is by-design |
| SEC-3 redirect bypass | ✅ **Fixed** | `RedirectGuard` re-applies allowlist to every 3xx (`Bridges.swift:214-240`); unit-tested against the real delegate |
| SEC-4 scheme/SSRF | ⚠️ **Partial** | https-only + userinfo-reject solid (`JSBridge.swift:401-417`); but `isBlockedNetworkHost` is a literal-string match — decimal/hex/IPv6-mapped IPs and DNS-rebinding bypass it; no DNS pinning |
| PERF-1 uncached icon raster | ✅ **Fixed** | `IconLRUCache(capacity:256)` consulted per row (`AppKitAdapters.swift:1174-1202`); multi-rep image kept (HiDPI softness fixed) |
| PERF-2 re-fold all candidates/keystroke | ✅ **Fixed** | coordinator caches `[PreparedCandidate]` (`AppCoordinator.swift:79-84`), `match(query:inPrepared:)` on hot path |
| PERF-3 whole-set filter+reload | ✅ **Fixed** (bound) / ⊘ deferred | top-K `maxProjectedRows=200` (`:107,344`); debounce + diff-reload honestly deferred |
| MAC-1 AppSearch data race | ✅ **Fixed** | `NSLock`-guarded frecency (`AppSearch.swift:104-114`); `AppSearchConcurrencyTests` (16 workers) |

### P1 (were High/Medium)
| ID | Verdict | Evidence |
|---|---|---|
| SEC-6 keychain accessibility | ✅ **Fixed** | `WhenUnlockedThisDeviceOnly` (`SecretStore.swift:193`), asserted |
| UI-1 raw markdown | ✅ **Fixed** | `AttributedString(markdown:)` into the text view (`AppKitAdapters.swift:670-715`); `UIHardeningTests` |
| UI-2 literal shortcut strings | ✅ **Fixed** | key-cap chips (`ShortcutGlyphs`/`rebuildShortcutCaps`); the "half-row pill" stretch bug fixed + `KeyCapLayoutTests` |
| UX-2 no VoiceOver | ✅ **Fixed** | row label/role/role-description, search label, decorative glyphs marked non-element (`:1151-1161`) |
| UX-5 toasts dropped | ⚠️ **Partial** | wired to a window seam (`AppCoordinator.swift:169-180`), but the banner is constrained across the glass boundary and unverified in production (snapshot path differs) |
| UX-7 Reduce Motion ignored | ✅ **Fixed** | `accessibilityDisplayShouldReduceMotion` branch in `showLauncher` (`:776-829`) |
| PLT-1 clipboard missing from SDK | ✅ **Fixed** | `VeeClipboard` + `clipboard()` in `runtime.ts:130-183`; shadow `declare`s removed |
| PLT-2 stale RUNTIME.md | ⚠️ **Partial** | bridges documented, but `open` gating still future-tensed ("is being added") and OOP framed as the live model (`RUNTIME.md:15-16,181-184`) |
| MAC-2 calendar usage-string mismatch | ✅ **Fixed** | `EventKitCalendarAdapter.requestFullAccessToEvents` wired (`Providers.swift:97-149`, `main.swift:140`) |
| MAC-3 signing/entitlements | ⚠️ **Partial** | hardened runtime + JIT entitlements + Developer-ID/notarize in `release.yml`; but notarization gated on absent secrets and the app is still **un-sandboxed** |
| DOC-2 inconsistent test counts | ⚠️ **Partial** | 254 is internally consistent; `MANUAL-VERIFY.md` still says "146 Swift + 12 node" |

### Re-checked originals & deferrals
| ID | Verdict | Note |
|---|---|---|
| MAC-4 clock deadlock | ❌ **Regressed → Critical** | see R2-CRIT-1 |
| MAC-5 assumeIsolated in hotkey CB | ✅ **Fixed** | plain C trampoline; main-actor hop moved to the app closure |
| MAC-6 esbuild pipe deadlock | ✅ **Fixed** | concurrent stdout/stderr drain (`Bridges.swift:493-505`) |
| MAC-7 blanket `.v5` mode | ⚠️ **Partial** | still `.v5` on all non-leaf targets (now under tools 6.2) |
| UX-3 empty menubar | ✅ **Fixed** | Settings/Quit items (`main.swift:181-199`) |
| UX-1 no Esc→root | ⊘ **Not-fixed (deferred)** | still a dead-end into a plugin |
| UX-4 dead ⌘K | ❌ **Not-fixed** | now a *polished* false affordance — see R2-HIGH-4 |
| UX-6 no loading state | ❌ **Not-fixed** | cold-open shows a blank pane — see R2-MED-4 |
| SEC-7 spoofable plugin id | ⚠️ **Partial** | id bound natively (good), but no plugin authenticity → token theft, see R2-HIGH-3 |
| SEC-8 full clipboard exposure | ⚠️ **Partial** | gated by a coarse bool; breadth unchanged |
| SEC-9 plaintext disk storage | ⚠️ **Partial** | `chmod 0600` not encryption; + prod shares one namespace, see R2-HIGH-2 |
| SEC-10 fs symlink TOCTOU | ⚠️ **Partial** | latent (fs unused in prod); `standardizingPath` doesn't resolve symlinks |
| ARCH-4 `JSONValue` Double-only | ❌ **Not-fixed** | integers >2^53 still lossy (`JSONValue.swift:13`) |
| ARCH-6 `deactivate` no-op | ⚠️ **Partial** | still doesn't quiesce; + leaked timers, see R2-MED-2 |
| ARCH-8 empty-string identity | ❌ **Not-fixed** | keyless items still collapse to `""` (`ViewModels.swift:205-209`) |

---

## 4. New findings (introduced or newly surfaced this round)

### R2-CRIT-1 · [Critical] `DispatchClock` deadlocks on every one-shot timer (`setTimeout`)
- **Where:** `Sources/VeeEngine/PluginHost.swift:247` (`makeTimerSource(queue: queue)`), `:253-255` (handler runs `fire()` then `self?.cancel(token)` for `!repeats`), `:263-264` (`cancel` does `queue.sync`).
- **Issue:** The one-shot timer's event handler executes *on the clock's serial `queue`*; it then calls `cancel`, which `queue.sync`s onto that same queue — a classic same-queue `sync` deadlock (and a runtime trap under Swift's checked dispatch). Reachable from any plugin: JS `setTimeout` → `JSBridge.scheduleTimer(repeats:false)` → `clock.schedule(repeats:false)`. The first time such a timer fires, the clock queue wedges/crashes, killing timers for all plugins. The 254 tests don't catch it (they use `TestClock`, which fires inline; the lone real-`DispatchClock` test never lets a one-shot elapse). This is the original **MAC-4** reintroduced — every other serial-queue site in the engine got the `DispatchSpecificKey` re-entrancy guard, but `DispatchClock` did not.
- **Fix:** Give `DispatchClock` the same `DispatchSpecificKey` inline-when-on-queue pattern used by `LoopbackTransport`/`PluginInstance`/`StdioTransport`; or drop the self-`cancel` from the handler (clear the timer entry without `queue.sync`). Add a regression test that fires a real one-shot on `DispatchClock`.

### R2-CRIT-2 · [Critical→architecture] Out-of-process host is built, signed, and bundled — but never used by the app
- **Where:** `Sources/vee/main.swift:155-169` (in-process `LoopbackTransport`); `ChildProcessHost`/`StdioTransport`/`vee-plugin-host` referenced only in `Tests/`; `scripts/package-app.sh` builds+signs the unused child binary.
- **Issue:** The spec's headline feature and its entire rationale (crash isolation) are not in effect at runtime — a plugin that crashes JSC, or hits R2-CRIT-1, takes the launcher with it. The subsystem is real and well-tested as a *library*, but it's dead weight in the product, and STATUS markets it as a shipped platform feature (see §6).
- **Fix:** Either wire `ChildProcessHost` into `main.swift` as the production plugin path (resolve the child via `Bundle.main` — see R2-MED-6 for the missing resolver — and harden the items in §5 first), or stop building/signing/bundling it and correct the docs.

### R2-HIGH-1 · [High] macOS-26-only target breaks CI/release and excludes the installed base
- **Where:** `Package.swift:31` (`.macOS(.v26)`), `packaging/Info.plist` (`LSMinimumSystemVersion 26.0`); `.github/workflows/{ci,lint,release}.yml` (`runs-on: macos-15`); no `@available` fallbacks in the app.
- **Issue:** Two problems. (1) **CI/release broken on push:** macos-15 runners ship the macOS 15 SDK and cannot build a macOS 26 deployment target — `swift build`/`swift test`/the release `package-app.sh` will all fail. GitHub has no `macos-26` hosted image yet, and `setup-xcode latest-stable` can't add an SDK the image lacks. The 3 remediation commits are unpushed, so this hasn't fired yet. (2) **Audience:** a hard 26-only floor for a cosmetic feature (Liquid Glass) drops macOS 14/15 — the bulk of Macs in mid-2026 — with no graceful degradation.
- **Fix:** Lower the deployment target to `.macOS(.v14)`/`.v15` and gate Liquid Glass behind `if #available(macOS 26, *)` with a `.sidebar` fallback (the snapshot path already has one). That restores CI on macos-15 *and* the user base. If 26-only is a deliberate preview, document it and move CI to a self-hosted 26 runner.

### R2-HIGH-2 · [High] Production collapses all plugins into one shared on-disk storage namespace
- **Where:** `Sources/vee/main.swift:144-153` passes a constant `pluginId:"plugins"` to the storage factory; `Sources/VeeEngine/DiskStorageBackend.swift:65-81`.
- **Issue:** `DiskStorageBackend` is designed for per-plugin isolation (`<root>/<pluginId>/`), but every plugin gets the same `"plugins"` folder, so any plugin's `vee.storage` reads/overwrites every other plugin's keys (cache poisoning, theft of cached data, collisions). Silently defeats the SEC-9 namespacing.
- **Fix:** Thread the real plugin id into the factory (`(pluginId) -> StorageBackend`); the backend already supports per-id subfolders.

### R2-HIGH-3 · [High] No plugin authenticity → a spoofed manifest `id` steals another plugin's (or the user's) Keychain tokens
- **Where:** `Sources/vee/PluginDiscovery.swift:56-89` (trusts `vee.json` `id` verbatim); `Sources/VeeApp/TokenStoring.swift` + `AppKitAdapters.swift:165-192` (Settings writes user tokens to `com.vee.<id>.tokens`).
- **Issue:** Keychain isolation is keyed solely on the self-declared manifest `id`. A hostile plugin dropped in the plugins dir can declare `id:"com.vee.github"` + `keychainNamespaces:["tokens"]` and read the GitHub token the user saved in Settings, then exfiltrate it. No signature, no trusted-id registry, no install consent.
- **Fix:** Require signed/notarized plugin bundles (or a manifest signature) verified before load; bind Keychain items to a verified identity, not the declared id; warn on id collisions during discovery.

### R2-HIGH-4 · [High] "Actions ⌘K" is a polished but non-functional affordance
- **Where:** `AppKitAdapters.swift:1305-1306,1357-1361` (footer cluster, in *all five* screenshots) vs `:967-976` (key routing handles only ↑↓/↩/esc — no ⌘K, no `performKeyEquivalent`).
- **Issue:** Every screen advertises a Raycast-style actions menu; pressing ⌘K does nothing. The original UX-4 dead affordance is now *better-looking* chrome that still misleads — worse, because it reads as deliberately functional. Items already carry `actions: [ActionViewModel]` that remain unreachable.
- **Fix:** Implement a minimal actions popover on ⌘K (present `selectedItem.actions`), or remove the cluster until it works.

### R2-HIGH-5 · [High] In-process + un-sandboxed: the capability model is not a security boundary
- **Where:** `Sources/vee/main.swift:155-169`; `packaging/Vee.entitlements:11-13` (no App Sandbox; `allow-jit`/`allow-unsigned-executable-memory`).
- **Issue:** Plugins run as JS in the launcher's address space with the user's full ambient authority; the capability checks are same-process Swift guards, not a sandbox. Any bridge/JSC/provider memory-safety bug — or the `open:["*"]`/`bundleId:*` waivers — is a full escape. `Manifest.swift:63-65` honestly says as much, but STATUS implies isolation. The built OOP host (R2-CRIT-2) would provide robustness but, as written, is *not* a privilege boundary either (the child has real providers and inherits the parent's environment/TCC).
- **Fix:** Treat installed plugins as fully trusted until OOP + a sandboxed child (App Sandbox, scrubbed env, no inherited TCC) ships; stop claiming isolation meanwhile.

### Medium
- **R2-MED-1 · `"*"` open capability waives the http(s) network re-check** — `Manifest.swift:162` skips `allowsNetworkHost` when `open` contains `"*"`, fully re-opening SEC-1 exfil for any plugin that requests it. Fix: keep the host re-check unconditional.
- **R2-MED-2 · Leaked timers survive teardown/reload** — `JSBridge.teardown()` clears `timerCallbacks` but never `clock.cancel(token)` (`JSBridge.swift:67-76`); with the real `DispatchClock` a `setInterval` keeps firing forever after unload/hot-reload (CPU wakeups; the original ARCH-6 "leaking timers"). Fix: cancel all outstanding tokens in `teardown`.
- **R2-MED-3 · Coordinator mirror can permanently desync after a dropped patch** — on `JSONPatch.apply` failure, `applyRender` returns without advancing the mirror while the host already advanced; every later diff then mis-applies and the surface freezes with no resync (`AppCoordinator.swift:208-214`). Fix: request a full re-render / keyframe on apply failure.
- **R2-MED-4 · Cold-open blank state (UX-6)** — discovery + 5000-app enumeration run async; until they finish the panel shows an empty list, no spinner, no "Loading…" (`main.swift:217-260`, `AppCoordinator.swift:343-372`). Fix: seed a loading/skeleton state.
- **R2-MED-5 · SSRF literal classifier bypassable; no DNS pinning** — `isBlockedNetworkHost` (`Bridges.swift:101-124`) is string-match only; decimal `2130706433`, `0x7f.0.0.1`, `[::ffff:169.254.169.254]`, and DNS-rebinding to a private IP all pass. (Bounded by the per-plugin allowlist, but rebinding against an allowlisted host is unmitigated.) Also `hasPrefix("fc")/("fd")` over-blocks hostnames like `fc-data.com`. Fix: parse with `inet_pton`, classify resolved IPs, pin through redirects.
- **R2-MED-6 · TS SDK `Capabilities` is missing the `open` field** — `types.ts:410-447` lacks `open`, which Swift added (`Manifest.swift:84`), so SDK-authored plugins can't declare `capabilities.open` and are silently default-denied. (Same class as the original PLT-1.) Fix: add `open: string[]` to the TS interface + `emptyCapabilities()`; add a parity test.
- **R2-MED-7 · "Verified visuals" tests the `.sidebar` fallback, not Liquid Glass** — every screenshot + the snapshot harness substitute `NSVisualEffectView(.sidebar)` for `NSGlassEffectView` (`AppKitAdapters.swift:440-466`), so the headline material, its clipping/contrast, and the toast z-order (the banner is constrained across the glass boundary, `:551-568`) are never actually verified. Honest in DESIGN.md, but "re-verified" overstates. Fix: caveat snapshots as layout-only; manual-verify glass on a real 26 desktop; add the toast to the inner content view.
- **R2-MED-8 · Settings "Plugins" tab is hardcoded** — `SettingsWindowController.swift:104-108` shows GitHub/Linear/OpenAI regardless of installed plugins (`main.swift:189` never passes `knownPlugins:`). Fix: drive the roster from `PluginDiscovery`.

### Low / Info (selected)
- **History-size setting no-ops until relaunch** (`SettingsBinding.swift:47-50`) — accepted in UI, never applied live; no caption. 
- **Hotkey recorder gives no validation/collision feedback** — a refused chord shows as bound but silently doesn't fire (`HotkeyRecorderView.swift:202-214`, `main.swift:274-280`).
- **No keyboard route to Settings/Quit while the launcher is open** (accessory app, no main menu; `⌘,` swallowed by the panel).
- **`PluginDiscovery` silently skips a manifest whose bundle is missing** — no diagnostic (`PluginDiscovery.swift:108-118`).
- **Stale comments in `vee-plugin-host/main.swift` and `RUNTIME.md`** describe the pre-ARCH-2 `onReceive`-clobber that no longer exists.
- **`intValue` boundary bug** — `d <= Double(Int.max)` can admit a value that traps `Int(d)` (`JSONValue.swift:67-71`).

---

## 5. Out-of-process host — readiness review (latent until wired)

The subsystem is genuinely well-built (LSP-style `Content-Length` framing tolerant of split/coalesced reads, `EINTR`/`EPIPE` handling, re-entrancy-safe delivery, a real-child integration test). But **before it is wired into production (R2-CRIT-2), these must be fixed** — they are latent only because nothing uses it:

- **[High-when-wired] No max-frame bound** — `parseContentLength` accepts any size; a hostile/garbled `Content-Length` grows the buffer unboundedly → OOM from the very process it's meant to contain (`StdioTransport.swift:199-260`). Cap frames; tear down on violation.
- **[High-when-wired] No request timeout / hang watchdog** — parent→child calls aren't correlated or timed out; a plugin `while(true){}` inside `activate` yields no render and no error, forever (`ChildProcessHost.swift:189-205`). Crash isolation ≠ hang isolation.
- **[High-when-wired] Child binary path resolution is unimplemented for the `.app` bundle** — only the *test* locates `vee-plugin-host` (via scratch dirs); there's no `Bundle.main`-based resolver, so it couldn't launch from a shipped bundle.
- **[Medium-when-wired] SIGPIPE can kill the parent** — a write to a dead child raises SIGPIPE (default: terminate) before `write` returns EPIPE; no `signal(SIGPIPE, SIG_IGN)`/`F_SETNOSIGPIPE` anywhere — so a child crash could take down the launcher, defeating the feature (`StdioTransport.swift:127-145`).
- **[Medium-when-wired] `restart()`/`start()` race the async `terminationHandler`** — can stop the *new* child's transport (`ChildProcessHost.swift:130-181`).
- **[Low] O(n²) frame parsing** under large split payloads (full-buffer copy + rescan-from-0 per read); orphaned child if parent is SIGKILLed; decode failures silently dropped; no multi-plugin-over-one-pipe routing test.

**Test honesty:** `testRealChildCrashIsolationAndRestart` sends **SIGTERM** (`proc.terminate()`), not the **SIGKILL** its comment claims, and never asserts `byUncaughtSignal` — so it proves graceful-shutdown isolation + restart, not uncaught-crash isolation. No test hangs or OOMs a plugin.

---

## 6. Honesty / overclaim re-assessment

The remediation docs are *mostly* honest (deferrals for UX-1, PERF-3, notarization are openly disclosed), but a few headline claims overstate:

| STATUS claim | Reality |
|---|---|
| "a real out-of-process JS plugin platform" | Built + tested as a library; **the app runs in-process loopback** (R2-CRIT-2). `MANUAL-VERIFY.md` still says OOP "is not yet real" — a direct contradiction to reconcile. |
| "the audit's P0/P1 findings remediated" | All P0 *code* fixed, but PERF-3 + UX-1 are deferred (disclosed) — "remediated" should be "all P0 and most P1." |
| "polished, tested, signed Raycast-class launcher" | True for the in-process app; "tested" is **local-only** — CI has never run these commits and will fail on macos-15 (R2-HIGH-1). |
| "Visuals re-verified via the snapshot harness" | Verifies the `.sidebar` fallback, not the shipped Liquid Glass (R2-MED-7). |

---

## 7. Prioritized remediation (Round 2)

**P0 — blocks any use/release**
1. **R2-CRIT-1** — fix the `DispatchClock` one-shot deadlock (`DispatchSpecificKey` guard) + regression test. *Any timer-using plugin is broken today.*
2. **R2-HIGH-1** — lower the deployment target + `@available`-gate Liquid Glass (restores CI + the user base), or move CI to a 26 runner. Then push the 3 commits so CI actually validates the remediation.
3. **Decide R2-CRIT-2** — either wire the OOP host (after the §5 fixes) or stop claiming it; reconcile STATUS vs MANUAL-VERIFY.

**P1 — security & correctness**
4. R2-HIGH-2 (per-plugin storage namespace), R2-HIGH-3 (plugin authenticity / token theft), R2-MED-1 (`"*"` open waiver), R2-MED-2 (leaked timers), R2-MED-5 (SSRF/DNS pinning).
5. R2-MED-3 (mirror desync resync), R2-MED-6 (SDK `open` capability parity), ARCH-4/ARCH-8 (still open).

**P2 — UX/polish/honesty**
6. R2-HIGH-4 (⌘K — implement or remove), R2-MED-4 (loading state), R2-MED-7 (glass verification + toast hierarchy), R2-MED-8 (Settings roster from discovery), the Low/Info items, and the doc reconciliations in §6.

---

## 8. Strengths (genuine, verified)

- **The P0 plugin-pipeline fixes are real and locked with precise regression tests** — `PipelineTests` (retarget + revision reset) and `MultiPluginRoutingTests` (first-loaded plugin still routed) target the exact Round-1 failure modes and would fail if they regressed.
- **Security gating is now real and test-enforced** — `SecurityHardeningTests` (18) asserts both the `-32001` rejection *and* that the provider is never touched, for open/openApp/fetch/clipboard/keychain; the redirect guard is tested against the real `URLSessionTaskDelegate`; keychain `ThisDeviceOnly` is asserted on the actual add-query.
- **Performance fixes are clean** — bounded `IconLRUCache` (and the multi-rep image fixes the real HiDPI-softness regression), fold-once `PreparedCandidate` on the hot path, top-K projection; STATUS is honest about deferring debounce.
- **The new OOP transport is well-engineered** (length-prefixed framing, partial-read reassembly, re-entrancy-safe delivery, a real-child integration test) — it just needs the §5 hardening and to actually be wired.
- **macOS fixes are correct** — lock-guarded frecency with a concurrency stress test, lazy EventKit with cached grant + graceful denial, the C-trampoline hotkey fix, concurrent esbuild pipe drain.
- **UI/UX craft improved markedly** — markdown rendering, key-cap chips (with a regression test for the layout bug found in review), comprehensive VoiceOver labeling, Reduce-Motion, a substantial tested Settings model; zero-hex semantic-color discipline.
- **Test rigor tripled and is real** — 254 Swift + 34 node tests; the security/routing/concurrency/persistence suites assert behavior that would break if the fixes regressed, and the node suite still guards fixture-vs-build drift.

---

*End of re-audit. This document supplements [AUDIT.md](AUDIT.md) (Round 1); original finding IDs are referenced in §3, new findings use the R2- prefix.*
