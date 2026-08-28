---
title: "Preferences"
description: "Plugins declare typed settings with <xbar.var>; Vee auto-generates a form and stores secrets in the macOS Keychain. Configuration belongs to the plugin."
sidebar:
  label: "Preferences"
  order: 7
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/preferences.md"
      title: "Markdown source"
  - tag: title
    content: "Preferences — Vee docs"
---
Configuration in Vee belongs to the plugin, not the app. A plugin declares its own typed settings with `<xbar.var>` tags; Vee reads them, generates a settings form automatically, and injects the values back into the plugin as environment variables. The app never hardcodes service names, API keys, or credentials — it only renders whatever a plugin declares.

## Declaring a preference

Add one `<xbar.var>` tag per setting, anywhere in the plugin source. The syntax is:

```
<xbar.var>TYPE(NAME=DEFAULT): Description [option1, option2, …]</xbar.var>
```

- `TYPE` is one of `string`, `number`, `boolean`, or `select`.
- `NAME` is the environment variable the value is exposed as.
- `DEFAULT` is the initial value (may be empty).
- The text after `:` is a human-readable description shown as the field label/help.
- The optional `[…]` list supplies the choices for a `select`.

### Examples

```python
# <xbar.var>string(CITY=London): Which city's weather to show.</xbar.var>
# <xbar.var>number(REFRESH_COUNT=5): How many items to display.</xbar.var>
# <xbar.var>boolean(SHOW_ICON=true): Show an icon in the menu bar.</xbar.var>
# <xbar.var>select(UNITS=metric): Measurement units. [metric, imperial]</xbar.var>
# <xbar.var>string(API_TOKEN=): Your service API token.</xbar.var>
```

`<swiftbar.var>` is accepted as well, with the same syntax.

## The auto-generated settings form

From those declarations Vee builds a form in the plugin's settings pane (open it from the **Plugin Manager**). Each type maps to a control:

| Declared type | Rendered control |
|---------------|------------------|
| `string` | A text field. |
| `number` | A numeric field. |
| `boolean` | A toggle. |
| `select` | A dropdown of the declared options. |

For the declarations above, the form would look like:

```
City            [ London              ]   Which city's weather to show.
Refresh count   [ 5                   ]   How many items to display.
Show icon       ( ●) on                    Show an icon in the menu bar.
Units           [ metric ▾ ]              Measurement units.
API token       [ ••••••••••••         ]   Your service API token.
```

When you save, Vee stores the values and injects each one as an environment variable of the same `NAME` on every plugin run. In the plugin you just read the environment:

```python
import os
city = os.environ.get("CITY", "London")
token = os.environ.get("API_TOKEN", "")
```

Declared variables take precedence over Vee's other injected variables (see [Injected environment variables](plugin-authoring.md#environment-variables-vee-injects)).

## Secret fields and the Keychain

Vee treats a preference as a **secret** when its name looks like a credential — it contains `token`, `secret`, `password`, `passwd`, `apikey`, or `api_key` (case-insensitive). So `API_TOKEN`, `GITHUB_TOKEN`, `DB_PASSWORD`, and `SERVICE_APIKEY` are all detected as secrets automatically.

For secret fields:

- The value is **masked** in the settings form.
- The value is stored in the **macOS Keychain**, namespaced per plugin (one plugin cannot read another plugin's secrets), rather than in a plaintext settings file.
- The value is still injected as an environment variable at run time, so your plugin reads it exactly like any other preference.

### When secrets are deleted

A plugin's settings and Keychain secrets are removed once its file is genuinely
gone from the plugins folder. "Genuinely" does real work here: a file can be
briefly absent for reasons that are not a deletion — an editor saving
non-atomically, a plugin dragged out to edit and dragged back, a network volume
between unmount and remount — so Vee waits for the absence to persist for several
minutes before removing anything it cannot restore. Switching to a different
plugins folder is never treated as a deletion; the folder you switched away from
keeps its settings and secrets.

The consequence worth knowing: for a few minutes after deleting a plugin, a *new*
plugin installed under the same filename inherits the old one's settings and
secrets. Deleting and immediately reinstalling under the same name is the one
case where that matters.

Deleting a plugin from the Plugin Manager moves the **script** to the Trash,
where it can be restored. Its settings, saved secrets and install history are not
recoverable — restoring the script gives you a plugin that needs setting up again.

You do not declare "this is a secret" explicitly — naming the variable appropriately (e.g. `API_TOKEN`) is enough. If you also want the secret to appear in the plugin's [trust summary](trust-model.md), reference it in a `<vee.secrets>` tag:

```python
# <xbar.var>string(API_TOKEN=): Your service API token.</xbar.var>
# <vee.secrets>API_TOKEN</vee.secrets>
```

## Vee's own settings

Vee itself has little to configure — the app-level settings live in **Preferences → General**, and one of them is a shortcut:

- **Bring windows to front.** A global shortcut that brings every open [plugin window](plugin-authoring.md#leaving-a-plugin-open-in-a-window) in front of whatever you are working in, with one of them focused. Vee has no Dock icon, so this is the fastest way back to a window you have unpinned and covered up. Type a combination in the same format a plugin declares (`cmd+shift+w`, `⌘⇧W`); it applies when you press Return or leave the field, and reports itself as active, already in use, or invalid. It ships unbound, and leaving the field empty gives the combination back to the system. With no windows open, pressing it does nothing — it retrieves windows, it never opens them.

## See also

- [Plugin authoring reference](plugin-authoring.md) — the full plugin format.
- [Trust model](trust-model.md) — declaring which secrets a plugin uses.
