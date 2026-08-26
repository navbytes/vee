---
title: "JSON output format"
description: "Vee's optional structured-JSON output format: opt in with a top-level {\"vee\":1} object, skip the text protocol's quoting and escaping, and get typed items and clean nesting."
sidebar:
  label: "JSON output"
  order: 9
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/json-output.md"
      title: "Markdown source"
  - tag: title
    content: "JSON output format — Vee docs"
---
Alongside the xbar/SwiftBar text protocol, Vee understands an **optional structured-JSON output format**. A plugin prints a single JSON object describing its title and menu, and Vee decodes it directly — no line parsing, no `|`-separated parameters, no quoting rules.

## When to use JSON vs the text protocol

**JSON is the recommended format for a new plugin.** It avoids the escaping and nesting rules the text format needs:

- **No quoting or escaping games.** Menu text, URLs, and shell arguments that contain spaces, `|`, or quotes are just JSON strings. There is no `| title="two words"` dance and no `\"` escaping.
- **Typed items.** Booleans are real booleans (`"separator": true`, `"terminal": false`), sizes are numbers, and there is no ambiguity between a value and a parameter name.
- **Clean nesting.** Submenus are arrays nested inside an item (`"submenu": [ … ]`) rather than depth-prefixed with `--` dashes, so deep menus stay readable and are trivial to build from a data structure.

The text protocol remains fully supported as the **xbar/SwiftBar-compatibility format** — it's what lets every existing xbar/SwiftBar plugin run on Vee unchanged, and it's still a fine choice for a quick one-liner or a plugin you want to keep portable to those tools. But if you're starting a plugin from scratch and don't need it to run outside Vee, reach for JSON first — especially one emitted from structured data (an API response, a config object).

The showcase plugin [`kitchen-sink.1m.sh`](https://raw.githubusercontent.com/navbytes/vee/main/plugins/showcase/kitchen-sink.1m.sh) is one file that exercises every field below — download and run it to see the whole format at once:

```sh
curl -o ~/Library/Application\ Support/Vee/plugins/kitchen-sink.1m.sh \
  https://raw.githubusercontent.com/navbytes/vee/main/plugins/showcase/kitchen-sink.1m.sh
chmod +x ~/Library/Application\ Support/Vee/plugins/kitchen-sink.1m.sh
```

## Opting in

JSON is **opt-in per run**. Vee uses the JSON parser only when your plugin's output is a top-level JSON object that declares the format version:

- The first non-whitespace character of stdout must be `{`.
- The object must contain the key `"vee": 1` (the current format version).

If both hold and the object decodes, Vee renders it as JSON. Otherwise it falls back to the text parser (`OutputParser.parseAuto` tries JSON first, then the text format). This means:

- Malformed JSON, or JSON missing the `"vee"` key, silently falls through to the text parser rather than erroring.
- Text-protocol plugins are unaffected — text rarely begins with `{`, and even if it does, the `"vee"` requirement keeps the two formats from colliding.

The minimal opt-in is a title-only object:

```json
{"vee":1,"title":[{"text":"Hello"}]}
```

## Schema

### Top level

```json
{ "vee": 1, "title": [ … ], "items": [ … ] }
```

| Key | Type | Required | Meaning |
|-----|------|----------|---------|
| `vee` | number | **yes** | Format version. Must be `1`. Its presence is what opts the run into JSON. |
| `title` | array of JSONTitle | no | The menu-bar title line(s). Multiple entries render as multiple title lines. |
| `items` | array of JSONItem | no | The dropdown body, top to bottom. |

### JSONTitle

An entry in `title`.

| Key | Type | Required | Meaning |
|-----|------|----------|---------|
| `text` | string | **yes** | The title text shown in the menu bar. |
| `color` | string | no | Text color (a named color or hex, e.g. `"green"`, `"#34c759"`). |
| `sfimage` | string | no | An SF Symbol name to render alongside the text. |
| `size` | number | no | Font size in points. |

### JSONItem

An entry in `items` (or in a `submenu`). Every field is optional; the shape of the item depends on which fields you set.

| Key | Type | Meaning |
|-----|------|---------|
| `text` | string | The item's label. Omitted for a separator. |
| `separator` | boolean | When `true`, this entry is a divider; all other fields are ignored. |
| `header` | boolean | When `true`, render as a real, non-interactive section header rather than a normal row (the JSON spelling of `header=true`). |
| `color` | string | Text color (named or hex). |
| `href` | string | A URL to open when the item is clicked. |
| `shell` | string | A command to run on click (a launch path or command name). |
| `params` | array of string | Arguments passed to `shell`, in order. |
| `terminal` | boolean | When `true`, run the `shell` command in Terminal; otherwise run it in the background. |
| `refresh` | boolean | When `true`, clicking re-runs the plugin. |
| `sfimage` | string | An SF Symbol name to render alongside the text. |
| `size` | number | Font size in points. |
| `disabled` | boolean | When `true`, the item is shown greyed-out and not clickable. |
| `checked` | boolean | When `true`, the item shows a checkmark. |
| `tooltip` | string | Hover tooltip text. |
| `submenu` | array of JSONItem | Child items, forming a nested submenu. |
| `alternate` | JSONItem | An alternate item shown when Option is held (mirrors the text protocol's `alternate=true`). |

## Examples

### Title-only menu

The smallest useful JSON plugin — just a menu-bar title, no dropdown.

```json
{
  "vee": 1,
  "title": [{ "text": "CPU 12%", "color": "green", "sfimage": "cpu" }]
}
```

### Link, separator, submenu, and an alternate

A dropdown with a clickable link, a divider, a nested submenu, and an Option-key alternate on the first item.

```json
{
  "vee": 1,
  "title": [{ "text": "Build ✓", "color": "green" }],
  "items": [
    {
      "text": "Open dashboard",
      "href": "https://ci.example.com/builds",
      "alternate": { "text": "Open dashboard (raw logs)", "href": "https://ci.example.com/builds/raw" }
    },
    { "separator": true },
    {
      "text": "Recent",
      "submenu": [
        { "text": "#4210 passed", "color": "green", "href": "https://ci.example.com/4210" },
        { "text": "#4209 failed", "color": "red", "href": "https://ci.example.com/4209" }
      ]
    }
  ]
}
```

### A shell-action item with params

An item that runs a command when clicked, passing arguments via `params`.

```json
{
  "vee": 1,
  "title": [{ "text": "Deploy" }],
  "items": [
    {
      "text": "Restart web server",
      "shell": "/usr/bin/sudo",
      "params": ["systemctl", "restart", "nginx"],
      "terminal": true,
      "tooltip": "Runs in Terminal so you can watch it"
    },
    { "text": "Refresh", "refresh": true }
  ]
}
```

## Building it with an SDK

All three SDKs have a typed builder for this format, mirroring the text-protocol
`Menu` method for method — `title`, `dropdown`, `item`, `separator`, `submenu`,
`print` — so choosing a wire format does not mean learning a second builder:

```ts
import { JSONMenu } from "./vee.ts";

const menu = new JSONMenu();
menu.title("JSON ✓", { color: "green", sfimage: "curlybraces" });

const d = menu.dropdown;
d.item("Structured item", { href: "https://example.com" });
d.separator();
d.submenu("Submenu").item("Child", { color: "blue" });

menu.print();
```

```python
from vee import JSONMenu

menu = JSONMenu()
menu.title("JSON ✓", color="green", sfimage="curlybraces")

d = menu.dropdown
d.item("Structured item", href="https://example.com")
d.separator()
d.submenu("Submenu").item("Child", color="blue")

menu.print()
```

```go
m := &vee.JSONMenu{}
m.Title("JSON ✓", &vee.JSONOptions{Color: vee.Str("green"), SFImage: vee.Str("curlybraces")})

d := m.Dropdown()
d.Item("Structured item", &vee.JSONOptions{Href: vee.Str("https://example.com")})
d.Separator()
d.Submenu("Submenu", nil).Item("Child", &vee.JSONOptions{Color: vee.Str("blue")})

m.Print()
```

The builder emits the keys in one canonical order, so the three SDKs produce
byte-identical JSON for the same menu (a shared golden fixture proves it).
Because the JSON format carries a subset of the text protocol's parameters, its
option type is a distinct one: an option JSON cannot express is a compile error
in TypeScript and Go, and a `TypeError` in Python, rather than a key silently
dropped on the way out.

## A runnable example

The repository ships a runnable JSON plugin at [`plugins/typescript/examples/json-demo.ts`](https://github.com/navbytes/vee/tree/main/plugins/typescript/examples/json-demo.ts). It builds a `{"vee":1,…}` object with `JSONMenu` — a colored title, a link, a separator, and a submenu — then prints it. A good starting point to copy.

## Rich params

The Vee-native inline controls are available in JSON too, as typed item fields:

| Field | Type | Notes |
|-------|------|-------|
| `sparkline` | `number[]` | Inline chart popover data. Non-finite values are dropped. |
| `sparklineWidth` | `number \| "full"` | Sparkline width in points; `"full"` stretches it to the row's width. |
| `sparklineHeight` | `number` | Sparkline height in points. |
| `sparklineColor` | `string` | Sparkline line color (named or hex). Falls back to the item's `color`. |
| `toggle` | `boolean` | On/off switch. |
| `slider` | `{ "min": number, "max": number, "value": number }` | Requires `min < max`; `value` is clamped into range. |
| `progress` | `number` | A completion fraction, clamped to `0…1`. The fill uses the item's `color`. |
| `progressTrackColor` | `string` | Progress track color (named or hex). |
| `trackColor` | `string` | **Deprecated** — the pre-v2 spelling of `progressTrackColor`. Still accepted; removed in the next major version. |
| `progressWidth` | `number` | Progress bar width in points. |
| `progressHeight` | `number` | Progress bar height in points. |
| `chart` | `{ "kind": "pie" \| "donut" \| "stackedbar", "values": number[], "labels"?: string[], "colors"?: string[], "w"?: number, "h"?: number }` | A categorical share chart. `values` must be finite and `>= 0` with a positive total; at most 8 segments (a longer series folds its tail into "Other"). `labels`/`colors` are positional — a color that is `null`, blank, malformed, or unrecognised keeps that segment's palette slot. `w`/`h` are **deprecated** — use the item's `accessoryWidth`/`accessoryHeight`, which size whichever accessory the item carries. Both are in points, clamped to 8–200; `"full"` stretches the chart to the row's width. |

```json
{
  "vee": 1,
  "title": [{ "text": "System" }],
  "items": [
    { "text": "Load history", "sparkline": [1, 2, 3, 5, 8, 13], "sparklineWidth": 120, "sparklineHeight": 18, "sparklineColor": "teal" },
    { "text": "Notifications", "toggle": true },
    { "text": "Volume", "slider": { "min": 0, "max": 100, "value": 40 } },
    { "text": "Disk usage", "color": "green", "progress": 0.72, "progressTrackColor": "#333333", "progressWidth": 80, "progressHeight": 6 },
    { "text": "By category", "chart": { "kind": "donut", "values": [45, 30, 25], "labels": ["Documents", "Photos", "Apps"] } }
  ]
}
```

These map to exactly the same controls as the text protocol's `sparkline=` /
`toggle=` / `slider=` / `progress=` / `pie=`,`donut=`,`stackedbar=` (see the
[plugin authoring reference](plugin-authoring.md#line-parameters)) — the JSON
form collapses the three chart shapes into one `chart` object with a `kind`,
since they describe the same data —
so colors, SF Symbols, links, shell actions, submenus, alternates, checkmarks,
tooltips, and the rich controls are all available in both formats.

## Editor validation (JSON Schema)

The JSON output format has a published schema too:

<https://vee.navbytes.io/schemas/json-output.schema.json>

```json
{
  "$schema": "https://vee.navbytes.io/schemas/json-output.schema.json",
  "vee": 1,
  "title": [{ "text": "System" }],
  "items": [{ "text": "Hello" }]
}
```

As with the widget card, `$schema` is ignored by Vee, and CI validates the
schema against the shipped fixtures.

## See also

- [Plugin authoring reference](plugin-authoring.md) — the text protocol and the full set of line parameters, including the rich params.
- [Plugin SDKs](sdk.md) — typed builders that emit the text protocol in TypeScript, Python, and Go.
- [Getting started](getting-started.md) — where the plugins folder is.
