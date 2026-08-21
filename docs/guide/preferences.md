# Preferences

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

You do not declare "this is a secret" explicitly — naming the variable appropriately (e.g. `API_TOKEN`) is enough. If you also want the secret to appear in the plugin's [trust summary](trust-model.md), reference it in a `<vee.secrets>` tag:

```python
# <xbar.var>string(API_TOKEN=): Your service API token.</xbar.var>
# <vee.secrets>API_TOKEN</vee.secrets>
```

## See also

- [Plugin authoring reference](plugin-authoring.md) — the full plugin format.
- [Trust model](trust-model.md) — declaring which secrets a plugin uses.
