# Design spec — Custom plugin stores (enterprise self-hosted catalogs)

Status: **Proposed** · Owner: TBD · Target module surface: `VeeCatalog`, `VeeUI`,
`VeePreferences`, `VeeApp`

This spec describes adding **custom, self-hostable plugin stores** to Vee so an
organization can run its own curated, trust-gated catalog of internal plugins
alongside (or instead of) the public `matryer/xbar-plugins` catalog. It is
grounded in the code that exists today; every proposed change names the concrete
type or file it touches.

---

## 1. Background — how "the store" works today

Vee's store client is the `VeeCatalog` module. Its shape is already an
abstraction, which is what makes this feature cheap:

- **`CatalogFetching`** (`Sources/VeeCatalog/CatalogClient.swift`) — the store
  protocol. Three methods: `fetchIndex() -> [CatalogEntry]`,
  `fetchSource(_:) -> String`, `fetchLastUpdated(_:) -> Date?`. The entire UI
  depends on this protocol; tests inject fakes.
- **`GitHubCatalogClient`** — the one implementation. It is hardwired to
  `matryer/xbar-plugins`: the git-trees API URL, the `raw.githubusercontent.com`
  base, and the commits API URL are all string literals. It is unauthenticated
  and response-size-capped (`treeCap`/`sourceCap`/`commitsCap`).
- **`CatalogParser`** — turns the git-tree JSON into `[CatalogEntry]`. There is
  **no manifest**: a plugin is *inferred* from repo shape (top-level dir =
  category, leaf blob = plugin, with an ignore-list of extensions and scaffolding
  dirs).
- **`CatalogEntry`** — `path`, `category`, `filename`, `rawURL`, lazy
  `lastUpdated`. `id == path`.
- **`PluginInstaller`** — writes fetched source into the plugins directory,
  path-traversal-hardened (`sanitizedFilename` + `assertContained`), `chmod 755`.
- **`PluginProvenance` / `ProvenanceStore`** — records `sourceURL` + SHA-256 at
  install (`.vee-provenance.json` ledger). Detects later tampering (TOFU model).
- **`VeeTrust`** — `TrustParser` → `TrustDeclaration` → `TrustAnalyzer` →
  `TrustSummary`; static `SourceScan`; `TrustDiff` on update. Advisory, never
  enforced.
- **`PluginBrowserModel` / `PluginBrowserView`** (`VeeUI`) — Discover grid; the
  trust-at-install gate (`InstallPrompt` → `confirmInstall`).
- **The one hardcoded binding**: `AppController.openBrowser()`
  (`Sources/VeeApp/AppController.swift:358`) constructs `GitHubCatalogClient()`
  directly. Everything downstream is store-agnostic.

App-level config is `AppPreferences` (`Sources/VeePreferences/AppPreferences.swift`),
a `UserDefaults`-backed singleton. Secrets are `KeychainSecretStore`
(`Sources/VeePreferences/SecretStore.swift`), namespaced by service name.

**Implication:** a custom store is a *second configuration of an existing
protocol*, plus auth, plus a registry of stores, plus UI. The security-critical
paths (path-safe install, size caps, provenance, trust gate) are reused
unchanged.

---

## 2. Goals & non-goals

### Goals

1. An enterprise can publish internal plugins to a **self-hosted store** and have
   employees discover/install/update them through Vee's existing Discover UI and
   trust gate.
2. A store **can be just a GitHub repo** — public, private, or GitHub Enterprise
   Server — with **zero new format required** for the simplest case.
3. Optional **curation manifest** for stores that want explicit metadata,
   integrity pinning, and signing.
4. **Multiple stores** coexist (public xbar + one or more internal), selectable
   in Discover.
5. **Private** stores authenticate; tokens live in the Keychain and are never
   exposed to plugin runtime.
6. **Managed configuration**: IT can pre-provision stores via MDM so users
   configure nothing.
7. Integrity/authenticity ladder: TOFU provenance (today) → index-pinned SHA-256
   → author signature.
8. Preserve today's behavior exactly when no custom store is configured.

### Non-goals

- **Not** a hosted Vee backend or a bespoke store server. The store is a
  repo/static host the customer already runs.
- **Not** an OS-enforced sandbox. Consistent with the roadmap, trust stays
  *advisory*; a store trust policy changes *framing/defaults*, never enforcement.
- **Not** cross-machine plugin sync (explicitly out of scope in the roadmap).
- **Not** paid/licensed plugin distribution, ratings, or telemetry.
- **Not** a plugin build/CI system — the store distributes source as-is, exactly
  like the xbar catalog.

---

## 3. Personas & primary flows

- **Platform/IT admin** — creates the internal store repo, writes/reviews
  plugins via PRs, optionally publishes a manifest and signs entries, pushes an
  MDM profile so every managed Mac sees the store automatically.
- **Employee** — opens Discover, sees an "Acme Internal Tools" store next to the
  public catalog, installs a plugin in one click through a streamlined
  (internal-reviewed) trust gate.
- **Power user (non-enterprise)** — adds a friend's public GitHub repo as a store
  manually in Preferences.

Primary flow (employee): open Discover → pick store (or "All") → browse cards
(title/category/trust/freshness from the store) → Install → trust gate (framed by
store policy, integrity verified) → written to plugins dir → auto-loaded.

---

## 4. Store shapes — "can it just be a GitHub repo?"

Yes. Two tiers, both shipped; the manifest is opt-in and auto-detected.

### 4.1 Tier 1 — Convention repo (zero-config)

A repo laid out exactly like `matryer/xbar-plugins`:

```
acme-vee-plugins/
├─ Deployment/   deploy-status.30s.sh
├─ Oncall/       pager.1m.py
└─ Metrics/      burn-rate.5m.ts
```

`CatalogParser.parse(treeJSON:)` already understands this verbatim once the repo
base URL is parameterized. Metadata (title/summary/author/trust) is read lazily
per card exactly as today (`loadHeader`), and freshness via the commits API.

**This is the recommended default** and needs almost no new parsing code.

### 4.2 Tier 2 — Manifest repo (opt-in curation)

A `vee-catalog.json` at the store root (path configurable). When present, it is
authoritative and the tree-inference path is skipped.

```jsonc
{
  "vee_catalog": 1,                       // schema version; reject unknown majors
  "name": "Acme Internal Tools",
  "homepage": "https://wiki.acme.corp/vee",
  "updated": "2026-07-01T00:00:00Z",
  "signing_key": "MCowBQYDK2VwAyEA...",   // optional base64 Ed25519 public key
  "plugins": [
    {
      "path": "Oncall/pager.1m.py",       // repo-relative; sanitized on install
      "title": "PagerDuty On-call",
      "category": "Oncall",
      "summary": "Shows the current on-call engineer.",
      "author": "sre@acme.corp",
      "min_macos": "26.0",                // hide/disable install below this
      "sha256": "9f2b...",                // integrity pin (see §8)
      "signature": "base64...",           // optional, over sha256 bytes (see §8)
      "deprecated": false,
      "tags": ["oncall", "sre"]
    }
  ]
}
```

Manifest wins Tier 1 on: metadata without downloading every file (faster, fewer
API calls, no per-file `loadHeader`), **integrity pinning**, deprecation,
min-OS gating, stable ordering, and signing. Absent → fall back to Tier 1.

### 4.3 Transport variants (same manifest/convention)

- **`github`** — `api.github.com` (public or private via token).
- **`githubEnterprise`** — a customer `ghe.acme.corp/api/v3` host.
- **`http`** — a plain static host serving `vee-catalog.json` + raw sources
  (S3/artifactory/nginx). Convention-inference is git-specific, so **static HTTP
  stores require a manifest**.
- **`local`** — a `file://` directory (air-gapped mirror). Manifest optional;
  directory inference works locally.

All four are the same `CatalogFetching` protocol behind a factory (§6).

---

## 5. New/changed value types (`VeeCatalog` + `VeePreferences`)

### 5.1 `StoreID`, `StoreKind`, `StoreTrustPolicy`

```swift
public struct StoreID: Hashable, Codable, Sendable {
    public let rawValue: String            // e.g. "com.vee.store.xbar", "acme-internal"
}

public enum StoreKind: String, Codable, Sendable {
    case github, githubEnterprise, http, local
}

/// How loudly the install gate frames a store. Never changes enforcement —
/// provenance + trust scan always run; this only reframes and sets the default
/// button posture.
public enum StoreTrustPolicy: String, Codable, Sendable {
    case publicUntrusted     // current behavior: full warnings, no default action
    case internalReviewed    // "Reviewed internal source"; warnings still shown
}
```

### 5.2 `StoreConfig`

```swift
public struct StoreConfig: Identifiable, Codable, Sendable, Equatable {
    public var id: StoreID
    public var displayName: String
    public var kind: StoreKind
    public var isEnabled: Bool
    public var isBuiltIn: Bool               // xbar; not removable
    public var isManaged: Bool               // from MDM; read-only in UI

    // Location (which fields apply depends on kind):
    public var apiHost: URL?                 // github/ghe: API base
    public var rawHost: URL?                 // github/ghe: raw content base
    public var owner: String?                // github/ghe
    public var repo: String?                 // github/ghe
    public var ref: String                   // branch/tag/sha; default "main"
    public var baseURL: URL?                 // http/local: index + source root
    public var manifestPath: String          // default "vee-catalog.json"

    // Security posture:
    public var trustPolicy: StoreTrustPolicy // default .publicUntrusted
    public var authMode: StoreAuthMode       // .none / .token
    public var requireSignature: Bool        // reject unsigned/invalid at install
    public var pinnedSigningKey: String?     // base64 Ed25519; overrides manifest key
}

public enum StoreAuthMode: String, Codable, Sendable { case none, token }
```

The built-in xbar store is a fixed `StoreConfig` (id `com.vee.store.xbar`,
`isBuiltIn: true`, `github`, `owner: "matryer"`, `repo: "xbar-plugins"`,
`trustPolicy: .publicUntrusted`). Constructing it reproduces today's URLs exactly
→ zero behavior change when it is the only store.

### 5.3 `CatalogEntry` gains a store dimension

`CatalogEntry.id` is currently `path`, which collides across stores. Change:

```swift
public var storeID: StoreID
public var id: String { "\(storeID.rawValue)#\(path)" }   // was: path
```

Add optional manifest-sourced fields populated when Tier 2 is used, left `nil`
under Tier 1 so lazy loading is unchanged: `title`, `summary`, `author`,
`declaredSHA256`, `signature`, `minMacOS`, `deprecated`.

Audit `id` usages (SwiftUI `ForEach`, `isInstalled`, `headers`/`trustLevels`
dictionaries keyed by `path`) — re-key by `entry.id` so two stores can carry the
same `path`.

### 5.4 `StoreRegistry` (`VeePreferences`)

```swift
public final class StoreRegistry: @unchecked Sendable {
    public init(defaults: UserDefaults = .standard)
    public func stores() -> [StoreConfig]          // managed ⊕ user ⊕ built-in xbar
    public func add(_ store: StoreConfig) throws    // user store
    public func remove(_ id: StoreID) throws        // rejects built-in/managed
    public func setEnabled(_ enabled: Bool, id: StoreID)
    public func update(_ store: StoreConfig) throws // rejects managed
}
```

Persistence: user stores as JSON under a new `AppPreferences` key
`vee.customStores`. **Managed** stores come from the MDM-forced defaults key
`vee.managedStores` (see §7) and are merged read-only, taking precedence on ID
collision. The built-in xbar store is always appended unless a managed policy
key `vee.disablePublicStore` is set.

---

## 6. Client factory & auth

### 6.1 Generalize `GitHubCatalogClient`

Replace hardcoded URLs with values derived from a `StoreConfig`:

```swift
public init(config: StoreConfig, tokenProvider: StoreTokenProviding? = nil, session: URLSession = .shared)
```

- `treeURL` ← `apiHost/repos/{owner}/{repo}/git/trees/{ref}?recursive=1`
- `repoBase` (in `CatalogParser`) ← `rawHost/{owner}/{repo}/{ref}/`
- commits URL ← `apiHost/repos/{owner}/{repo}/commits?path=…&per_page=1`
- On each request, if `authMode == .token`, set
  `Authorization: Bearer <token>` from `tokenProvider`.

`CatalogParser.parse(treeJSON:repoBase:)` and `parseLastCommitDate` stay pure;
`repoBase` becomes a parameter instead of a private constant. Size caps unchanged.

### 6.2 New clients

- **`ManifestCatalogClient`** — fetches `manifestPath`, decodes `vee-catalog.json`,
  maps to `[CatalogEntry]` with metadata pre-filled and `declaredSHA256`. Used by
  all kinds when a manifest exists. `fetchSource` resolves each entry's raw URL
  from the store base + path. `fetchLastUpdated` returns the manifest `updated`
  or `nil` (no per-file commits call needed).
- **`LocalCatalogClient`** — `file://` reads via `FileManager`; manifest or
  directory walk.
- **`HTTPCatalogClient`** — static host; manifest-only.

### 6.3 Factory

```swift
public enum CatalogClientFactory {
    public static func make(for config: StoreConfig,
                            tokenProvider: StoreTokenProviding?) -> CatalogFetching
}
```

Resolution order inside a git/http store: probe manifest first; if present return
a manifest-backed client, else the tree/convention client. `AppController.openBrowser()`
stops calling `GitHubCatalogClient()` directly and instead builds a
multi-store model from `StoreRegistry.stores()` (§9).

### 6.4 Token storage

Reuse the Keychain pattern. Add:

```swift
public struct StoreTokenStore: StoreTokenProviding {
    public init(storeID: StoreID)          // service "com.vee.store.<id>"
    public func token() -> String?
    public func set(_ token: String?)
}
```

Same `kSecClassGenericPassword` / `kSecAttrAccessibleWhenUnlocked` shape as
`KeychainSecretStore`. **The store token is never placed in a plugin's
environment** (`PluginExecutor` environment building must exclude it) — it is an
app credential, not a plugin secret.

---

## 7. Managed configuration (MDM)

`UserDefaults.standard` transparently surfaces MDM-forced ("managed") keys, so no
new mechanism is needed — Vee just reads a reserved key and treats it as
read-only.

- Reserved managed keys (pushed via a `.mobileconfig` / `com.vee.Vee` domain):
  - `vee.managedStores` — array of dicts mirroring `StoreConfig` public fields
    (minus secrets). Merged into `StoreRegistry.stores()` as `isManaged: true`.
  - `vee.disablePublicStore` (Bool) — hide the built-in xbar store.
  - `vee.managedPluginsDirectory` (String, optional) — pin the plugins folder.
- Managed stores render in the Stores settings tab **locked** with a "Managed by
  your organization" badge; add/remove/edit are disabled for them.
- Tokens are *not* delivered via managed defaults (they would be world-readable
  in the profile). For private managed stores, either (a) the token is entered
  once by the user, or (b) a managed store uses a GitHub App / SSO flow (future).
  The spec ships (a); (b) is a follow-up.
- Admin docs: a sample `.mobileconfig` and a "Publish an internal Vee store"
  guide land in `docs/_content/enterprise-store.md`.

---

## 8. Integrity & authenticity ladder

Three rungs, each opt-in, layered on the existing provenance:

1. **TOFU provenance (today, unchanged).** `PluginProvenance` records
   `sourceURL` + SHA-256 at install; later local edits flip to "Modified". No
   change required; `sourceURL` still disambiguates across stores. Optionally add
   `storeID` to `PluginProvenance` for cleaner auditing.
2. **Index-pinned SHA-256 (Tier 2 manifest).** When an entry carries
   `declaredSHA256`, `confirmInstall` verifies the fetched source hashes to it
   **before** writing; mismatch is a hard failure with a distinct error
   ("source does not match the catalog's pinned hash"). This defends against a
   compromised raw host when the index is trusted. Uses the existing
   `PluginHash.sha256Hex`.
3. **Author signature (optional).** Manifest carries `signing_key` (or the store
   pins `pinnedSigningKey`), and each entry carries `signature` over its
   `sha256` bytes. Vee verifies with `CryptoKit`
   (`Curve25519.Signing.PublicKey.isValidSignature`). If
   `StoreConfig.requireSignature`, a missing/invalid signature blocks install.
   This realizes the roadmap's "Signed plugins" Day-2 item and adds **zero**
   third-party dependencies (CryptoKit is a system framework, already used by
   `PluginHash`).

Verification points live in `PluginBrowserModel.requestInstall`/`confirmInstall`
and a new pure `StoreIntegrity` enum in `VeeCatalog` (unit-testable without I/O).

---

## 9. UI changes (`VeeUI`)

### 9.1 Preferences → new "Stores" tab

- Table of configured stores: name, kind, enabled toggle, trust-policy chip,
  managed/built-in badges.
- **Add store** sheet: kind picker → fields (owner/repo/ref, or host, or
  file path) → optional token (masked, saved to Keychain) → optional
  "internal-reviewed" trust policy and require-signature toggle → a **Test
  connection** button that calls `fetchIndex()` and reports count/error via
  `CatalogErrorPresenter`.
- Built-in xbar store: present, toggle-able (unless managed-disabled), not
  removable. Managed stores: locked rows.

### 9.2 Discover becomes multi-store

- `PluginBrowserModel` holds `[StoreConfig]` and a `[StoreID: CatalogFetching]`
  map (via the factory). A **store scope** control (sidebar section or segmented
  header): "All stores" merges entries; a single store filters to it.
- Entries render a small **store chip** on the card when scope is "All".
- Category sidebar and search operate over the merged, scoped set.
- Loading/error is **per store**: one store being offline shows an inline banner
  for that store, not the full-screen error (which stays reserved for "no stores
  reachable at all"). Extend `CatalogErrorPresenter` with a 401/unauthorized
  case ("Sign in to this store — check its access token").

### 9.3 Install gate framing

`InstallPrompt` gains `storeTrustPolicy` and `integrity` (verified/pinned/signed).
The sheet:

- `.publicUntrusted` → today's wording unchanged.
- `.internalReviewed` → header "Reviewed internal source · Acme Internal Tools",
  integrity line ("Signed by sre@acme.corp" / "Hash matches catalog"), warnings
  still listed but de-emphasized. **Never** hides a detected capability.

---

## 10. Security & threat model

| Threat | Mitigation |
| --- | --- |
| Compromised **raw/source host**, honest index | Tier-2 SHA-256 pin (§8.2) fails the install on mismatch. |
| Compromised **index** (manifest) | Signature (§8.3) with a store-pinned key; without signing, an internal store is only as trusted as its repo's access control + PR review. |
| **Token exfiltration** by an installed plugin | Token in Keychain under the app's service; explicitly excluded from plugin env in `PluginExecutor`. |
| **Path traversal** via manifest `path`/`filename` | `PluginInstaller.sanitizedFilename` + `assertContained` already enforce a single safe component; manifest paths route through the same gate. |
| **SSRF / arbitrary host** via user-added store | Schemes restricted to `https`/`file`; `file://` only for `kind == .local`; managed stores are admin-authored. A user-added store is added deliberately by the user (same trust as pasting a repo URL). |
| **DoS via huge index/source** | Existing `treeCap`/`sourceCap`/`commitsCap`; add a manifest byte cap and a `plugins` count cap; reject unknown `vee_catalog` major. |
| **Downgrade** (store drops signing to push an unsigned plugin) | `StoreConfig.requireSignature` is client-side policy and cannot be lowered by the store; managed profile can force it on. |
| **Rate limiting** on private GitHub | Authenticated requests raise the limit; lazy metadata (`loadHeader`/`loadLastUpdated`) already avoids eager per-plugin calls; manifest avoids them entirely. |

Trust remains **advisory**: none of this enforces an OS sandbox. A store trust
policy changes framing and default posture only — consistent with the roadmap's
capability boundary. `SECURITY.md` gains a "Custom stores" section.

---

## 11. Testing plan (TDD, zero new deps)

Pure/unit (no network — inject fakes like the existing suites):

- `CatalogParser`: manifest decode (golden `vee-catalog.json` fixture),
  tree-vs-manifest selection, fallback when manifest absent, unknown-version
  rejection, count/size caps.
- `StoreConfig` ↔ built-in xbar reproduces exactly today's URLs (regression lock
  on current behavior).
- `StoreIntegrity`: SHA-256 pin pass/fail; Ed25519 signature valid/invalid/
  missing under `requireSignature` true/false.
- `sanitizedFilename` applied to manifest paths (traversal fixtures).
- `StoreRegistry`: user-store CRUD; managed precedence; built-in not removable;
  `disablePublicStore`.
- Auth: a fake `URLProtocol`/session asserts the `Authorization` header is set
  when and only when `authMode == .token`.
- `PluginBrowserModel`: multi-store merge, per-store error isolation, entry `id`
  uniqueness across stores, store-scope filtering.
- `CatalogErrorPresenter`: new 401 case.

Integration (existing style): `swift test` green; manual `swift run vee` against
a throwaway public repo configured as a store; `xcodegen`+`xcodebuild` if the app
target changes. No golden-fixture (plugin-format) changes — output format is
untouched.

---

## 12. Phasing (each phase = reviewable, shippable, one-ish commit)

- **P0 — Parameterize (no user-visible change).** Introduce `StoreConfig`;
  generalize `GitHubCatalogClient` + `CatalogParser` to take it; construct the
  built-in xbar store; `openBrowser()` uses it. Behavior identical. Regression
  tests lock current URLs.
- **P1 — Multi-store + private repos.** `StoreRegistry`, Stores settings tab,
  Discover store scope, Keychain `StoreTokenStore`, `Authorization` header, 401
  handling. **Delivers the enterprise private-repo use case.**
- **P2 — Manifest + integrity pin.** `vee-catalog.json` parsing,
  `ManifestCatalogClient`, SHA-256 pin verify at install. Curation + integrity.
- **P3 — Transports.** GitHub Enterprise host params; `LocalCatalogClient`
  (`file://` air-gap) and `HTTPCatalogClient` (static host).
- **P4 — Signing + trust policy.** Ed25519 verify, `requireSignature`,
  `internalReviewed` gate framing.
- **P5 — Managed config.** `vee.managedStores` / `disablePublicStore` reading,
  locked UI rows, sample `.mobileconfig`, `docs/_content/enterprise-store.md`.

P0–P1 alone make Vee usable in an enterprise; P2–P5 are the trust/curation
upgrades.

---

## 13. Backward compatibility

- With no custom store configured, the app builds exactly one store (built-in
  xbar) whose client emits today's URLs → **no behavior change**.
- `CatalogEntry.id` changes from `path` to `storeID#path`; internal only (an
  `Identifiable`/dictionary key), no persisted format depends on it.
- `PluginProvenance` ledger format is unchanged (optional additive `storeID`).
- `AppPreferences` gains keys (`vee.customStores`, managed keys); absent keys
  behave as before.

---

## 14. Open questions

1. **Auth for managed private stores** — ship user-entered token first; is a
   GitHub App / SSO device-flow worth a follow-up, or is a PAT acceptable for the
   target customers?
2. **Signing key distribution** — manifest-embedded key (TOFU) vs store-pinned
   `pinnedSigningKey` via MDM (stronger). Ship both; default to pinned when
   managed.
3. **Update notifications** — the roadmap's "new version available" nudge pairs
   naturally with a manifest `updated`/`sha256`; include in P2 or defer to Day 2?
4. **Static HTTP layout** — require a manifest (proposed) vs also support a
   directory-listing convention. Manifest-only keeps HTTP stores simple.
5. **Per-store plugins subfolder** — should installs from different stores land
   in separate subdirectories to avoid filename collisions, or keep one flat
   folder and let the install gate warn on overwrite (today's behavior)?
</content>
</invoke>
