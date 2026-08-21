# Trust model

Vee runs plugins as ordinary executables with your full user privileges. There is no sandbox — a plugin can do anything you can do. Rather than pretend to isolate plugins, Vee makes their intentions **transparent**: plugins declare what they touch, and Vee surfaces that to you in plain language before you install and while you manage them.

**This is advisory, never enforced.** The declarations do not restrict what a plugin can actually do. They are a way for authors to be honest and for you to make an informed choice.

## Why transparency, not a sandbox

The whole point of a menu-bar script runner is to run arbitrary scripts — hit an API, read a file, shell out to a CLI tool. A real sandbox tight enough to contain that would break the plugins people want to run, which is exactly why apps in this category are distributed outside the Mac App Store (the App Store sandbox is incompatible with arbitrary plugin execution).

So Vee is honest about the trade-off:

- Plugins run **un-sandboxed by design**, with your privileges.
- Vee cannot and does not verify that a plugin only does what it declares.
- What Vee *can* do is read the declarations, summarize them in human terms, and show a warning when something looks broad or unusual.

Treat plugins like any other script you download and run. Read the source of anything you do not trust.

## Declaring capabilities

Authors add `<vee.*>` tags to the plugin source (anywhere; they are scanned regardless of comment syntax). The available declarations:

| Tag | Meaning |
|-----|---------|
| `<vee.capabilities>` | Comma-separated capability names: `network`, `filesystem`, `secrets`, `exec`, `clipboard`, `notifications`. |
| `<vee.network>` | Comma-separated network domains the plugin connects to (e.g. `api.github.com`). Wildcards like `*.example.com` are allowed but flagged. |
| `<vee.filesystem.read>` | Paths the plugin reads. |
| `<vee.filesystem.write>` | Paths the plugin writes. |
| `<vee.secrets>` | Names of secrets/tokens the plugin uses (usually matching an `<xbar.var>` secret). |
| `<vee.exec>` | External binaries the plugin runs (e.g. `git`, `curl`). |

Declaring a detail tag implies its capability — for example, listing `<vee.network>` domains implies the `network` capability, so you rarely need `<vee.capabilities>` on its own.

### Example declaration

```python
#!/usr/bin/env python3
# <xbar.title>GitHub Notifications</xbar.title>
#
# <vee.network>api.github.com</vee.network>
# <vee.secrets>GITHUB_TOKEN</vee.secrets>
# <vee.exec>git</vee.exec>
# <vee.filesystem.read>~/.config/gh</vee.filesystem.read>
```

Vee reads this as: connects to `api.github.com`, uses the `GITHUB_TOKEN` secret, runs `git`, and reads `~/.config/gh`.

## The install trust summary

When you install a plugin from [Discover](getting-started.md) (the built-in catalog browser), Vee shows a plain-language **trust summary** before installing, translating the declarations into readable statements such as:

- "Connects to the internet → api.github.com"
- "Uses a secret → GITHUB_TOKEN"
- "Runs external tools → git"
- "Reads files → ~/.config/gh"

Installation goes through this trust gate, so you always see the footprint before a catalog plugin lands in your folder.

## Trust levels, badges, and warnings

Vee classifies each plugin's declaration into a **trust level**:

- **Declared** — the plugin fully declares its footprint.
- **Partial** — it declares a capability but leaves out detail (for example, it says it uses the network but lists no domains).
- **Undeclared** — it declares nothing, so its footprint is unknown.

For each declared capability, Vee shows a **trust badge** with a severity heuristic:

- **Network** — low if specific domains are listed; **medium** if a wildcard domain is used; **high** if network is declared with no domains.
- **Filesystem** — low for read-only or no writes; medium for scoped writes; **high** for broad writes (writing to `~`, `~/`, `/`, or `*`).
- **Secrets** and **exec** — medium (they involve credentials or running other programs).
- **Clipboard** and **notifications** — low.

Vee also raises **warnings** for the risky cases — a wildcard network domain, a broad filesystem write, or network declared without any domains. These badges and warnings appear in the **Plugin Manager** so you can review a plugin's footprint at any time, not just at install.

## What this does and does not guarantee

- It **does** give you a clear, honest picture of what an author says their plugin does.
- It **does** flag broad or vague declarations so nothing hides in "trust me."
- It **does not** stop a plugin from doing something it did not declare. Nothing here is enforced.

If a plugin is undeclared or you are unsure, open its source (Reveal in Finder from the Plugin Manager) and read it before enabling it.

## See also

- [Preferences](preferences.md) — how secrets referenced in `<vee.secrets>` are entered and stored in the Keychain.
- [Plugin authoring reference](plugin-authoring.md) — where to put `<vee.*>` tags.
- [FAQ](faq.md) — "Is it safe if it's un-sandboxed?"
