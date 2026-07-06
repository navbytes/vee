# CLI and URL actions

Vee can be driven from the command line during development and controlled at runtime through URL actions. Plugins use those same URL schemes to trigger refreshes and post notifications.

## Running from source (`swift run vee`)

For development, run the menu-bar app straight from the SwiftPM package:

```sh
swift build          # build the libraries + dev executable
swift test           # run the test suites
swift run vee        # launch the menu-bar app for development
```

`swift run vee` starts the app so you can iterate on plugins and code without producing a full app bundle. See the project README for building the distributable, notarized `Vee.app`.

While developing you can point Vee at a specific plugins folder with an environment variable, which overrides the folder chosen in the UI:

```sh
VEE_PLUGINS_DIR=~/dev/my-plugins swift run vee
```

## URL actions

Vee registers two URL schemes: `vee://` and `swiftbar://`. The `swiftbar://` scheme is supported for compatibility, so plugins written for SwiftBar keep working. Both schemes accept the same actions.

The **action is the URL host**, and parameters come from the query string. The plugin name is passed as `name` (or `path`).

| Action | Description | Example |
|--------|-------------|---------|
| `refreshallplugins` (alias `refreshall`) | Re-run every plugin. | `vee://refreshallplugins` |
| `refreshplugin` | Re-run one plugin by name. | `vee://refreshplugin?name=cpu` |
| `enableplugin` | Enable a plugin. | `vee://enableplugin?name=cpu` |
| `disableplugin` | Disable a plugin. | `vee://disableplugin?name=cpu` |
| `toggleplugin` | Toggle a plugin's enabled state. | `vee://toggleplugin?name=cpu` |
| `addplugin` | Download and install a plugin from a URL. | `vee://addplugin?src=https://example.com/cpu.5s.sh` |
| `setephemeralplugin` | Show transient menu content in its own status item, with no file on disk (optionally auto-removed after `exitafter` seconds). | `vee://setephemeralplugin?name=build&content=Done&exitafter=5` |
| `notify` | Post a system notification. | `vee://notify?title=Done&subtitle=Build&body=Succeeded&href=https://example.com` |

The same URLs work with the `swiftbar://` scheme, e.g. `swiftbar://refreshplugin?name=cpu`.

### The `notify` action

`notify` posts a macOS notification. Its parameters:

- `title` — the notification title.
- `subtitle` — an optional subtitle.
- `body` — the notification body text.
- `href` — an optional URL to open when the notification is clicked.

```
vee://notify?title=Backup&subtitle=Nightly&body=Completed%20successfully&href=https://example.com
```

Remember to URL-encode parameter values that contain spaces or special characters.

## Triggering actions from a plugin

Because these are ordinary URLs, a plugin triggers them the same way it opens any link — either as an `href` on a menu item, or by opening the URL from the script.

**As a clickable menu item** (`href=`):

```bash
echo "Refresh now | href=vee://refreshplugin?name=cpu"
echo "Enable weather | href=vee://enableplugin?name=weather"
```

**From the script itself** (open the URL with `open`):

```bash
# Notify when a long task finishes
open "vee://notify?title=Build&body=Done"

# Force this plugin to re-render immediately
open "vee://refreshplugin?name=$VEE_PLUGIN_PATH"
```

Note that a menu item can also refresh the plugin without a URL at all, using the `refresh=true` line parameter:

```bash
echo "Refresh | refresh=true"
```

Use `refresh=true` for the common "re-run me" case; use the URL actions when a plugin needs to refresh, enable/disable, or toggle a *different* plugin, or to post a notification.

## See also

- [Plugin authoring reference](plugin-authoring.md#line-parameters) — the `href` and `refresh` parameters.
- [Plugin authoring reference](plugin-authoring.md#environment-variables-vee-injects) — `VEE_PLUGIN_PATH` and other injected variables.
