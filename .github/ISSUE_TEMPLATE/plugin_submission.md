---
name: Plugin submission
about: Propose a plugin for the Vee catalog / gallery
title: "[Plugin]: "
labels: ["plugin-submission"]
assignees: []
---

<!--
Use this to propose a plugin for the Vee catalog/gallery. Please be honest and
specific about what the plugin does and what it touches — the trust declarations
are how users decide whether to run it.

Reminder: Vee plugins run un-sandboxed with full user privileges, and `<vee.*>`
declarations are advisory (see SECURITY.md). Submissions whose declarations don't
match their behavior will be declined.
-->

## Plugin name

<!-- Display name, and the intended filename with its refresh interval, e.g.
github-notifications.5m.sh -->

- **Name:**
- **Filename (encodes refresh interval):**

## What it does

A short description of what the plugin shows in the menu bar and what its
dropdown does.

## Language & dependencies

- **Language / interpreter:** <!-- e.g. bash, Python 3, Node, compiled binary -->
- **External tools required:** <!-- e.g. curl, jq, gh — anything it shells out to -->
- **How it degrades if a tool/token is missing:** <!-- graceful fallback? -->

## Declared trust capabilities

<!-- List the `<vee.*>` tags the plugin declares. These must match what the code
actually does. Delete lines that don't apply. -->

```
<vee.capabilities>network,secrets,exec</vee.capabilities>
<vee.network>api.example.com</vee.network>
<vee.filesystem.read>~/some/path</vee.filesystem.read>
<vee.filesystem.write>~/some/path</vee.filesystem.write>
<vee.secrets>SOME_TOKEN</vee.secrets>
<vee.exec>curl, jq</vee.exec>
```

## Preferences

<!-- Any `<xbar.var>` preferences it declares (tokens, options, etc.). Note which
are secrets (stored in the Keychain). -->

## Source link

<!-- Link to the plugin source (a repo, gist, or file). Reviewers will read it. -->

- **Source:**
- **Author / maintainer:**
- **License:**

## Checklist

- [ ] The `<vee.*>` declarations match what the code actually does.
- [ ] The plugin is self-contained and degrades gracefully when a tool or token
      is missing.
- [ ] It uses a correct filename refresh interval (e.g. `.5m`, `.30s`).
- [ ] No secrets/tokens are hard-coded in the source.
- [ ] The source is public and readable.
