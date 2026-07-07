# Custom plugin stores (enterprise)

Vee ships with the public [`matryer/xbar-plugins`](https://github.com/matryer/xbar-plugins)
catalog in **Discover**. You can also point Vee at **your own store** — a curated,
trust-gated catalog of internal plugins — and it shows up in Discover next to (or
instead of) the public one, installing through the same trust gate.

A store is just a place Vee can read an index and download sources from. **It can
be a plain GitHub repo** (public, private, or GitHub Enterprise Server), a static
HTTP host, or a local `file://` mirror for air-gapped machines.

- [Quick start: a store in one repo](#quick-start)
- [Two store shapes](#two-store-shapes)
- [Private repositories](#private-repositories)
- [GitHub Enterprise, static HTTP, and air-gapped mirrors](#other-transports)
- [Integrity and signing](#integrity-and-signing)
- [Managed configuration (MDM)](#managed-configuration-mdm)
- [Adding a store by hand](#adding-a-store-by-hand)
- [Security notes](#security-notes)

<a name="quick-start"></a>
## Quick start: a store in one repo

1. Create a repository, e.g. `acme/vee-plugins`.
2. Put each plugin in a **category folder**, exactly like the public catalog:

   ```
   acme-vee-plugins/
   ├─ Deployment/
   │  └─ deploy-status.30s.sh
   ├─ Oncall/
   │  └─ pager.1m.py
   └─ Metrics/
      └─ burn-rate.5m.ts
   ```

   The top-level folder is the plugin's **category**; the filename encodes its
   refresh interval (`name.INTERVAL.ext`), just like any Vee/xbar plugin.
3. In Vee, open **Preferences → Stores → Add store…**, choose **GitHub**, and
   enter the owner and repo. Your plugins appear in Discover under your store.

That's the whole thing. No manifest, no build step — the repo layout *is* the
catalog.

<a name="two-store-shapes"></a>
## Two store shapes

### 1. Convention (zero-config)

The quick-start layout above. Vee infers the catalog from the repo's folders,
exactly as it does for the public catalog. A plugin's title, description, and
declared capabilities are read from its source headers (`<xbar.title>`,
`<vee.*>`, …) when its card is shown — nothing extra to write.

### 2. Manifest (`vee-catalog.json`)

Add a `vee-catalog.json` at the repo root when you want **curation**: explicit
titles and descriptions without downloading every file, an integrity hash per
plugin, a minimum-macOS gate, deprecation flags, and optional signing. When the
file is present it is authoritative; otherwise Vee falls back to the convention.

```jsonc
{
  "vee_catalog": 1,
  "name": "Acme Internal Tools",
  "homepage": "https://wiki.acme.corp/vee",
  "updated": "2026-07-01T00:00:00Z",
  "signing_key": "MCowBQYDK2VwAyEA…",     // optional, base64 Ed25519 public key
  "plugins": [
    {
      "path": "Oncall/pager.1m.py",        // repo-relative
      "title": "PagerDuty On-call",
      "category": "Oncall",
      "summary": "Shows the current on-call engineer.",
      "author": "sre@acme.corp",
      "min_macos": "26.0",
      "sha256": "9f2b…",                    // integrity pin (see below)
      "signature": "base64…",              // optional (see below)
      "deprecated": false,
      "tags": ["oncall", "sre"]
    }
  ]
}
```

A static HTTP host **must** publish a manifest (there's no repo to infer from); a
Git repo or a local mirror may use either.

<a name="private-repositories"></a>
## Private repositories

For a private GitHub/GHE repo, add the store as usual and paste a **personal
access token** (or a fine-grained token / GitHub App token with read access to
the repo). Vee stores it in the **macOS Keychain** and sends it only to that
store's host. The token is an app credential — it is **never** placed in a
plugin's environment.

Use the **Test connection** button in the Add-store sheet to confirm the token
and repo before saving. A `401` in Discover means the token is missing or
invalid — update it in **Preferences → Stores**.

<a name="other-transports"></a>
## GitHub Enterprise, static HTTP, and air-gapped mirrors

Vee supports four store kinds; all install through the same trust gate.

| Kind | Where it reads from | Manifest |
| --- | --- | --- |
| **GitHub** | `api.github.com` + `raw.githubusercontent.com` | optional |
| **GitHub Enterprise** | your `ghe.acme.corp/api/v3` + raw host | optional |
| **Static HTTP** | a host serving `vee-catalog.json` + raw sources (S3, Artifactory, nginx) | required |
| **Local (`file://`)** | a directory on disk or a mounted share | optional |

A **local mirror** is the simplest air-gapped option: clone your store repo (or
export it) to `/opt/vee/store` on the managed machines and configure a `local`
store pointing at it. No network required.

<a name="integrity-and-signing"></a>
## Integrity and signing

Vee offers three levels of assurance, each optional and layered on the existing
[provenance](trust-model.md) (source URL + hash recorded at install):

1. **Pinned hash.** Set `sha256` on a manifest entry and Vee verifies the fetched
   source against it **before** writing to disk. A mismatch blocks the install —
   this defends against a tampered raw host when the manifest is trusted.
2. **Signature.** Publish a `signing_key` (base64 Ed25519 public key) in the
   manifest, and sign each entry's source. The signature is computed over the
   source's SHA-256 digest:

   ```sh
   # digest of the source, then sign it with your Ed25519 private key
   openssl dgst -sha256 -binary plugin.py > plugin.sha256
   # (sign plugin.sha256 with your key; base64 the result into "signature")
   ```
3. **Require signatures.** Turn on **Require signature** for the store (or push it
   via MDM). Any unsigned or invalid-signature plugin is refused. This setting is
   client-side and **cannot be lowered by the store** — a compromised catalog
   can't downgrade a machine that requires signing.

Prefer a **policy-pinned key** (`pinnedSigningKey`, delivered by MDM) over the
manifest's own key when you can: it can't be replaced by whoever controls the
repo.

<a name="managed-configuration-mdm"></a>
## Managed configuration (MDM)

Push stores to managed Macs with a configuration profile for the `com.vee.app`
preference domain. Managed stores are **read-only and force-enabled** — a user
can't disable or remove them.

Reserved keys:

| Key | Type | Effect |
| --- | --- | --- |
| `vee.managedStores` | array of dicts | Stores to install (see fields below). |
| `vee.disablePublicStore` | bool | Hide the built-in public xbar catalog. |

Each entry in `vee.managedStores` mirrors a store's fields:

| Field | Notes |
| --- | --- |
| `id`, `displayName`, `kind` | Required. `kind` ∈ `github`, `githubEnterprise`, `http`, `local`. |
| `apiHost`, `rawHost` | For `github`/`githubEnterprise`. |
| `owner`, `repo`, `ref` | For `github`/`githubEnterprise` (`ref` defaults to `main`). |
| `baseURL` | For `http`/`local`. |
| `manifestPath` | Defaults to `vee-catalog.json`. |
| `trustPolicy` | `internalReviewed` (default for managed) or `publicUntrusted`. |
| `authMode` | `none` or `token`. |
| `requireSignature` | `true` to refuse unsigned plugins. |
| `pinnedSigningKey` | Base64 Ed25519 public key that overrides the manifest's. |

Example profile payload (abbreviated):

```xml
<key>vee.managedStores</key>
<array>
  <dict>
    <key>id</key><string>acme-internal</string>
    <key>displayName</key><string>Acme Internal Tools</string>
    <key>kind</key><string>githubEnterprise</string>
    <key>apiHost</key><string>https://ghe.acme.corp/api/v3</string>
    <key>rawHost</key><string>https://ghe.acme.corp/raw</string>
    <key>owner</key><string>platform</string>
    <key>repo</key><string>vee-plugins</string>
    <key>requireSignature</key><true/>
    <key>pinnedSigningKey</key><string>MCowBQYDK2VwAyEA…</string>
  </dict>
</array>
<key>vee.disablePublicStore</key><true/>
```

**Tokens are not delivered via the profile** (a profile is world-readable on the
device). For a managed private store, the user enters the token once, or the
store uses a host that authenticates through your SSO.

<a name="adding-a-store-by-hand"></a>
## Adding a store by hand

Anyone (not just enterprise) can add a store in **Preferences → Stores →
Add store…**: pick the kind, fill in the location, optionally paste a token, and
optionally mark it *internal-reviewed* or *require signature*. User-added stores
are fully under your control — enable, disable, edit, or remove them at any time.
The built-in public catalog can be toggled off but not removed.

<a name="security-notes"></a>
## Security notes

- **Trust stays advisory.** A store's trust policy changes how loudly the install
  gate speaks and what the default action is — it never enforces an OS sandbox
  and never hides a capability Vee detected. See the [trust model](trust-model.md).
- **Review is your gate.** For an internal Git store, pull-request review of the
  repo is the real control; Vee's provenance and (optional) signing verify that
  what you install is what was reviewed.
- **Filenames are sanitized.** A plugin path from any store is reduced to a single
  safe filename before it's written, so a hostile `path` can't escape the plugins
  folder.
- **Responses are bounded.** Index and source downloads are size-capped, and a
  manifest's plugin count is capped, so a hostile or compromised store can't
  exhaust memory.
