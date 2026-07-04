# Security Policy

Vee is a native macOS menu-bar script runner. Because it runs arbitrary
executables (plugins), understanding its threat model is essential — please read
the [Threat model](#threat-model) section below, not just the reporting
instructions.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately through either channel:

- **GitHub Security Advisory (preferred):** open a private advisory at
  <https://github.com/navbytes/vee/security/advisories/new>. This keeps the
  report confidential and lets us collaborate on a fix.
- **Email:** `security@` the project's domain — or, until a dedicated address is
  published, contact the maintainer (`navbytes`) via a GitHub private advisory.

Please include:

- A description of the issue and its impact.
- Steps to reproduce (a proof-of-concept plugin or output sample is ideal).
- The Vee version, macOS version, and chip (Apple Silicon).
- Any suggested remediation, if you have one.

### What to expect

- **Acknowledgement** within about 5 business days.
- **Assessment** and a severity judgement, with a rough timeline, shortly after.
- **Fix and disclosure** coordinated with you. We aim to resolve high-severity
  issues promptly and will credit reporters who wish to be named.

Vee is an open-source project maintained on a best-effort basis; these are
targets, not contractual guarantees.

## Supported versions

Vee is pre-1.0 and under active development. Security fixes land on `main` and
in the latest released build. Only the **latest release** is supported — please
upgrade before reporting, and report against the newest version.

| Version        | Supported          |
| -------------- | ------------------ |
| Latest release | :white_check_mark: |
| Older releases | :x:                |

## Threat model

Read this before running any plugin. Vee's security posture is deliberate and
differs from a sandboxed app.

### Plugins run un-sandboxed, by design

A Vee plugin is **any executable in any language** — a shell script, a compiled
binary, a Node/Python program. When Vee runs a plugin it runs with **your full
user privileges**: it can read and write your files, make network requests, run
other programs, and read secrets you have granted it. This is the same model as
xbar and SwiftBar, and it is fundamental to what Vee is — a general script
runner cannot both execute arbitrary code and meaningfully sandbox it.

This is also why Vee is distributed **outside the Mac App Store**, signed with a
Developer ID and notarized: the App Store sandbox is incompatible with running
arbitrary plugins.

### The trust layer is transparency, not enforcement

Vee's differentiator is a **trust/transparency layer**, not a sandbox. Plugins
can *declare* what they touch using `<vee.*>` header tags:

- `<vee.network>api.example.com</vee.network>` — hosts it contacts
- `<vee.filesystem.read>` / `<vee.filesystem.write>` — paths it reads/writes
- `<vee.secrets>NAME</vee.secrets>` — secrets it uses
- `<vee.exec>tool</vee.exec>` — external binaries it invokes
- `<vee.capabilities>network,secrets,...</vee.capabilities>` — capability summary

Vee parses these declarations and surfaces a per-plugin trust summary (badges,
severity, warnings). **These declarations are advisory and are never enforced.**
Vee does not restrict a plugin to what it declared; a plugin can declare nothing
and still do everything, or declare one thing and do another. The trust summary
tells you what a *well-behaved* plugin claims — it is a transparency aid, not a
security boundary.

Preferences are collected via `<xbar.var>` and any secrets you enter are stored
in the macOS **Keychain**, but a plugin you run can still access whatever your
user account can.

### What this means for you

- **Only run plugins you trust.** Treat a plugin exactly as you would treat any
  script you downloaded and ran on your Mac.
- **Read the source before installing.** Plugins are plain text or a binary you
  can inspect. Prefer plugins whose source you can read and whose `<vee.*>`
  declarations match what the code actually does.
- **Be cautious with secrets and tokens.** A plugin you grant a token to can use
  that token however it wishes.
- **Prefer plugins from sources you trust** and that declare their capabilities
  honestly.

### In scope for a security report

- Vulnerabilities in Vee itself: memory-safety or parsing bugs in the app,
  privilege issues, mishandling of Keychain secrets, the trust summary
  misrepresenting a declaration, signing/notarization/update-integrity problems,
  or a plugin escaping Vee to affect the app beyond its own (already full) user
  privileges.

### Out of scope

- The fact that plugins run with full user privileges — this is intended
  behavior (see above), not a vulnerability.
- Malicious behavior by a third-party plugin you chose to install. Report those
  to the plugin's author; if it's in a Vee-hosted catalog, also let us know so we
  can remove it.
- The advisory nature of `<vee.*>` declarations — they are transparency, not
  enforcement, and are documented as such.

Thank you for helping keep Vee and its users safe.
