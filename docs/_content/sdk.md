---
title: "Plugin SDKs"
description: "Zero-dependency Vee plugin SDKs for TypeScript, Python, and Go — the same typed Menu/Section builders in every language, producing byte-identical output."
sidebar:
  label: "Plugin SDKs"
  order: 8
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/sdk.md"
      title: "Markdown source"
  - tag: title
    content: "Plugin SDKs — Vee docs"
---
Vee ships tiny, zero-dependency SDKs for writing plugins with typed builders instead of hand-formatting the xbar/SwiftBar text protocol. There are three, one per language — **TypeScript**, **Python**, and **Go** — and they mirror each other exactly: the same builder shape, option names, encoding order, and quoting, so a plugin reads the same in any language and all three produce **byte-identical** output for the same menu.

The SDKs live in the [`plugins/`](https://github.com/navbytes/vee/tree/main/plugins) directory of the repository:

- TypeScript — [`plugins/typescript/`](https://github.com/navbytes/vee/tree/main/plugins/typescript) ([README](https://github.com/navbytes/vee/tree/main/plugins/typescript/README.md))
- Python — [`plugins/python/`](https://github.com/navbytes/vee/tree/main/plugins/python) ([README](https://github.com/navbytes/vee/tree/main/plugins/python/README.md))
- Go — [`plugins/go/`](https://github.com/navbytes/vee/tree/main/plugins/go) ([README](https://github.com/navbytes/vee/tree/main/plugins/go/README.md))

Pick whichever language you are most comfortable in; the API is the same shape in all three.

## Getting the SDK

A Vee plugin is a single executable you drop in your plugins folder — no build
step, no `node_modules`, no virtualenv. So the TypeScript and Python SDKs travel
*with* the plugin as a sibling file rather than being resolved from a package
manager:

```sh
vee sdk ts --out ~/Library/Application\ Support/Vee/plugins   # writes vee.ts
vee sdk py --out ~/Library/Application\ Support/Vee/plugins   # writes vee.py
```

```ts
import { Menu } from "./vee.ts";
```

```python
from vee import Menu  # vee.py sits beside this plugin
```

`vee new --lang ts --out DIR` does both in one step: it scaffolds a plugin and
writes the SDK beside it, so the result runs immediately.

The TypeScript SDK is also on npm, for a plugin that is part of a project with a
`node_modules` — bundled, or built before it is dropped in:

```sh
npm install @navbytes/vee
```

```ts
import { Menu } from "@navbytes/vee";
```

It ships compiled JavaScript with declarations (Node will not strip types under
`node_modules`) and has no dependencies. Vendoring stays the default for
drop-in plugins, because it keeps a plugin a single file with a sibling.

Go is the exception. A Go plugin compiles to a binary, so it takes the SDK as a
normal module dependency:

```sh
go get github.com/navbytes/vee/plugins/go
```

```go
import vee "github.com/navbytes/vee/plugins/go"
```

The examples in this repository import `../vee.ts` (and the local module)
because they sit beside the SDK there. Copying one out means running
`vee sdk` beside it — and, for TypeScript, changing that import to `./vee.ts`.

## Requirements

- **TypeScript** — Node 24 or later (for native TypeScript execution / type stripping; there is **no build step**).
- **Python** — Python 3.9 or later (standard library only).
- **Go** — Go 1.21 or later (standard library only; you build the plugin to a binary).

## Hello world

The same menu in each language. Adjust the import path to point at wherever the SDK lives relative to your plugin.

### TypeScript

Create `cpu.5s.ts`. Node runs the `.ts` directly (type-stripping), so you drop the file straight into your plugins folder — no compile step.

```ts
#!/usr/bin/env node
import { Menu } from "./vee.ts";

const menu = new Menu();
menu.title("CPU 12%", { color: "green", sfimage: "cpu" });

const d = menu.dropdown;
d.item("Top processes", { href: "https://example.com/procs" });
d.separator();

const details = d.submenu("Details");
details.item("Load: 1.20");
details.item("Cores: 8");

d.item("Refresh", { refresh: true });

menu.print();
```

```sh
chmod +x cpu.5s.ts
```

### Python

Create `cpu.5s.py`. Options are passed as keyword arguments.

```python
#!/usr/bin/env python3
import sys
from vee import Menu  # vee.py sits beside this plugin

menu = Menu()
menu.title("CPU 12%", color="green", sfimage="cpu")

d = menu.dropdown
d.item("Top processes", href="https://example.com/procs")
d.separator()

details = d.submenu("Details")
details.item("Load: 1.20")
details.item("Cores: 8")

d.item("Refresh", refresh=True)

menu.print()
```

```sh
chmod +x cpu.5s.py
```

### Go

Options are a `*vee.Options` struct; the `vee.Str`/`vee.Int`/`vee.Bool` helpers set the optional pointer fields concisely. Build to a binary named `cpu.5s`.

```go
package main

import "vee"

func main() {
	m := &vee.Menu{}
	m.Title("CPU 12%", &vee.Options{Color: vee.Str("green"), SFImage: vee.Str("cpu")})

	d := m.Dropdown()
	d.Item("Top processes", &vee.Options{Href: vee.Str("https://example.com/procs")})
	d.Separator()

	details := d.Submenu("Details", nil)
	details.Item("Load: 1.20", nil)
	details.Item("Cores: 8", nil)

	d.Item("Refresh", &vee.Options{Refresh: vee.Bool(true)})
	m.Print()
}
```

```sh
go build -o cpu.5s ./...
```

A compiled binary is a first-class Vee plugin. The `.5s` in the filename sets a 5-second refresh, exactly as with any other plugin (see [plugin authoring](plugin-authoring.md#filenames-and-refresh-intervals)).

## The API

All three SDKs expose the same four types.

### `Menu`

The top-level menu: title line(s) plus a dropdown.

| Method | TypeScript | Python | Go |
|--------|------------|--------|----|
| Add a title line (call more than once for multiple lines) | `title(text, options?)` | `title(text, **options)` | `Title(text, *Options)` |
| The dropdown body (everything after `---`) | `dropdown` (getter) | `dropdown` (property) | `Dropdown() Section` |
| Render to the text protocol string | `toString()` | `to_string()` / `str(menu)` | `String()` |
| Write the rendered menu (+ newline) to stdout | `print()` | `print()` | `Print()` |

`print()` is what a real plugin calls.

### `Section`

A menu section at a given submenu depth (0 = top level).

- **Item** — `item(text, options?)` / `item(text, **options)` / `Item(text, *Options)` adds a menu item.
- **Separator** — `separator()` / `separator()` / `Separator()` adds a `---` divider.
- **Submenu** — `submenu(text, ...)` / `Submenu(text, ...)` adds an item and returns a new `Section` for its children (one level deeper).

### `JSONMenu`

The same surface as `Menu`, emitting the [structured-JSON format](json-output.md)
instead of the text protocol. It mirrors `Menu` method for method — `title`,
`dropdown`, `item`, `separator`, `submenu`, `toString`/`to_string`/`String`,
`print` — so choosing a wire format no longer means choosing a different way to
work.

Prefer it when a plugin's values contain characters the text protocol has to
escape (pipes, quotes, newlines), since the JSON encoder handles them without
the escaping rules the text format needs.

### Options

Options map onto the line parameters in the [authoring reference](plugin-authoring.md#line-parameters). The supported keys are the same in every SDK (in TypeScript they are `ItemOptions`; in Python keyword arguments; in Go the `Options` struct fields):

- **Rendering** — `color`, `size`, `font`, `length`, `trim`, `ansi`, `emojize`
- **Behaviour** — `href`, `shell` (with `params` → `param1..N`), `terminal`, `refresh`, `dropdown`, `alternate`, `disabled`, `checked`, `key`, `tooltip`
- **Images** — `image`, `templateImage` (Python `template_image`, Go `TemplateImage`)
- **SF Symbols** — `sfimage`, `sfColor`, `sfSize`, `sfConfig`, `symbolize`
- **SwiftBar extras** — `md`, `badge`, `webview`, `webviewW`, `webviewH`, `shortcut`
- **Vee-native rows** — `header`, `accessory`

Naming follows each language's idiom, not one shared spelling: TypeScript is
camelCase (`templateImage`), Python is snake_case (`template_image`), Go is
PascalCase (`TemplateImage`). The emitted parameter is the same in all three.

For example, in each language:

```ts
d.item("Open build", { shell: "/usr/bin/open", params: ["-a", "Xcode"], terminal: false });
d.item("Inbox", { badge: "12" });
d.item("**Bold** text", { md: true });
d.item("Status :checkmark.circle:", { symbolize: true });
```

```python
d.item("Open build", shell="/usr/bin/open", params=["-a", "Xcode"], terminal=False)
d.item("Inbox", badge="12")
d.item("**Bold** text", md=True)
d.item("Status :checkmark.circle:", symbolize=True)
```

```go
d.Item("Open build", &vee.Options{Shell: vee.Str("/usr/bin/open"), Params: []string{"-a", "Xcode"}, Terminal: vee.Bool(false)})
d.Item("Inbox", &vee.Options{Badge: vee.Str("12")})
d.Item("**Bold** text", &vee.Options{MD: vee.Bool(true)})
d.Item("Status :checkmark.circle:", &vee.Options{Symbolize: vee.Bool(true)})
```

Values containing spaces or `|` are quoted (and embedded quotes escaped) automatically, in every SDK — you never format the protocol by hand. So is a value that *begins* with a quote character, which the parser would otherwise read as its own delimiter.

Numbers are formatted by one shared rule — JavaScript's `String(Number)`, i.e.
ECMA-262 `Number::toString` — rather than each language's default, so the three
SDKs emit the same bytes for the same value. (Go's own `'g'` verb would render
`1000000` as `1e+06`.)

**Unknown options are an error, not a no-op.** TypeScript rejects them at
compile time, Go as an unknown struct field, and Python raises `TypeError`:

```python
d.item("Disk", progress=0.5, track_colour="gray")
# TypeError: unknown option 'track_colour'. Did you mean 'progress_track_color'?
```

## Rich params

All three SDKs expose **typed builders** for Vee's inline controls —
**sparkline**, **toggle**, **slider**, and **progress** — plus each visual
control's tuning params. You pass structured values; the SDK formats the
protocol (numbers, ranges, and quoting) for you, so the whole class of "I
hand-formatted `slider=` wrong" bugs is impossible to write. (These render
natively in Vee; in xbar/SwiftBar the unknown params are ignored, so plugins
stay portable.)

Every inline visual takes the same size and colour vocabulary —
`<control>W` / `<control>H` / a colour — and every width accepts `"full"` to
stretch across whatever width the row actually has:

| Control | Width | Height | Colour |
| ------- | ----- | ------ | ------ |
| `sparkline` | `sparklineW` | `sparklineH` | `sparklineColor` |
| `progress` | `progressW` | `progressH` | `progressTrackColor` |
| `chart` | `chart.w` | `chart.h` | `chart.colors` |

In Go, a control with its own struct leaves its knobs unprefixed (`Chart.W`)
because the struct already names the control, while the flat `Options` carries
the control's name (`SparklineW`, `ProgressW`); `full` is a sibling boolean
(`SparklineFullWidth`) since Go has no union type.

`trackColor` is the deprecated spelling of `progressTrackColor`; it still works
and still emits `progresstrackcolor=`.

**TypeScript**

```ts
d.item("Load history", { sparkline: [1, 2, 3, 5, 8, 13], sparklineW: 120, sparklineH: 18, sparklineColor: "teal" });
d.item("Notifications", { toggle: true });
d.item("Volume", { slider: { min: 0, max: 100, value: 40 } });
d.item("Disk usage", { color: "green", progress: 0.72, progressTrackColor: "#333333", progressW: 80, progressH: 6 });
// progress also accepts a value/max pair, emitted as `progress=72,100`:
d.item("Budget", { progress: { value: 72, max: 100 } });
// and any width takes "full":
d.item("Requests", { sparkline: [12, 40, 31, 55], sparklineW: "full" });
```

**Python**

```python
d.item("Load history", sparkline=[1, 2, 3, 5, 8, 13], sparkline_w=120, sparkline_h=18, sparkline_color="teal")
d.item("Notifications", toggle=True)
d.item("Volume", slider={"min": 0, "max": 100, "value": 40})
d.item("Disk usage", color="green", progress=0.72, progress_track_color="#333333", progress_w=80, progress_h=6)
d.item("Budget", progress={"value": 72, "max": 100})
d.item("Requests", sparkline=[12, 40, 31, 55], sparkline_w="full")
```

**Go**

```go
d.Item("Load history", &vee.Options{Sparkline: []float64{1, 2, 3, 5, 8, 13}, SparklineW: vee.Float(120), SparklineH: vee.Float(18), SparklineColor: vee.Str("teal")})
d.Item("Notifications", &vee.Options{Toggle: vee.Bool(true)})
d.Item("Volume", &vee.Options{Slider: &vee.Slider{Min: 0, Max: 100, Value: 40}})
d.Item("Disk usage", &vee.Options{Color: vee.Str("green"), Progress: vee.Float(0.72), ProgressTrackColor: vee.Str("#333333"), ProgressW: vee.Float(80), ProgressH: vee.Float(6)})
d.Item("Budget", &vee.Options{ProgressValue: vee.Float(72), ProgressMax: vee.Float(100)})
d.Item("Requests", &vee.Options{Sparkline: []float64{12, 40, 31, 55}, SparklineFullWidth: true})
```

### Share charts

The [share charts](plugin-authoring.md#share-charts-pie-donut-stackedbar)
(`pie=`/`donut=`/`stackedbar=`) get one typed builder rather than three: the
shapes take the same data, so `kind` is the only thing that changes between them.
`labels` and `colors` are optional and positional; `w`/`h` (`W`/`H` in Go) set
the inline size in points, emitted as `accessoryw=`/`accessoryh=`. Pass
`w: "full"` (Go: `FullWidth: true`) to stretch a `stackedbar` to the row's own
width — a bar only, since a circle has no free width; on `pie`/`donut` Vee warns
and falls back to points. `progress=` takes the same knob as
`progressW: "full"` (Go: `ProgressFullWidth: true`).

**TypeScript**

```ts
d.item("By category", { chart: { kind: "pie", values: [45, 30, 25], labels: ["Documents", "Photos", "Apps"] } });
d.item("By volume", { chart: { kind: "donut", values: [512, 256, 128], colors: ["blue", "teal", "orange"] } });
```

**Python**

```python
d.item("By category", chart={"kind": "pie", "values": [45, 30, 25], "labels": ["Documents", "Photos", "Apps"]})
d.item("By volume", chart={"kind": "donut", "values": [512, 256, 128], "colors": ["blue", "teal", "orange"]})
```

**Go**

```go
d.Item("By category", &vee.Options{Chart: &vee.Chart{
    Kind: "pie", Values: []float64{45, 30, 25}, Labels: []string{"Documents", "Photos", "Apps"},
}})
d.Item("By volume", &vee.Options{Chart: &vee.Chart{
    Kind: "donut", Values: []float64{512, 256, 128}, Colors: []string{"blue", "teal", "orange"},
}})
```

Vee reads labels and colors as comma-separated lists, so a segment name can't
contain a comma; names with spaces are quoted for you.

All three emit byte-identical protocol output (there are `controls` and `charts`
examples with shared golden fixtures proving it). See the underlying
line-parameter grammar in the
[plugin authoring reference](plugin-authoring.md#line-parameters).

## Widget cards

All three SDKs also build the rich [widget card](widgets.md)
payload a plugin prints when invoked with `VEE_TARGET=widget` — a generic
`widgetCard(...)`/`WidgetCard(...)` constructor, plus `Stat`/`Gauge`/`Trend`/
`List`/`Board` convenience builders that preset the `template` field. Each
returns/builds an object with the same `toString()`/`to_string()`/`String()`
+ `print()` shape as `Menu`.

**TypeScript**

```ts
import { Stat } from "./vee.ts";

Stat({
  title: "Revenue",
  symbol: "chart.line.uptrend.xyaxis",
  tint: "green",
  value: "$18.2k",
  status: "ok",
  items: [{ label: "Orders", value: "214", symbol: "bag", tint: "blue" }],
  actions: [{ kind: "refresh", label: "Refresh" }],
}).print();
```

**Python**

```python
from vee import Stat

Stat(
    title="Revenue",
    symbol="chart.line.uptrend.xyaxis",
    tint="green",
    value="$18.2k",
    status="ok",
    items=[{"label": "Orders", "value": "214", "symbol": "bag", "tint": "blue"}],
    actions=[{"kind": "refresh", "label": "Refresh"}],
).print()
```

**Go**

```go
vee.Stat(vee.WidgetCard{
	Title:   vee.Str("Revenue"),
	Symbol:  vee.Str("chart.line.uptrend.xyaxis"),
	Tint:    vee.Str("green"),
	Value:   vee.Str("$18.2k"),
	Status:  vee.StatusOK,
	Items:   []vee.WidgetCardItem{{Label: "Orders", Value: vee.Str("214"), Symbol: vee.Str("bag"), Tint: vee.Str("blue")}},
	Actions: []vee.WidgetCardAction{{Kind: vee.ActionRefresh, Label: "Refresh"}},
}).Print()
```

Setting `Template:` on a `vee.WidgetCard` literal works too — the constructor
just presets it, so the three languages choose a template the same way.

All three emit byte-identical JSON for the same card (there's a `widget-card`
example and a shared golden fixture proving it, also round-tripped through
the Swift parser). See the full field/template/action reference in
[Widgets](widgets.md).

### Layout nodes take only the options that fit them

For layouts the five templates can't express, the `Node` builders compose a
layout tree. Each builder accepts only the options meaningful for its node type
— `columns` belongs to a grid, `min_length` to a spacer — and all three SDKs
enforce that, as does the published
[`widget-card.schema.json`](https://github.com/navbytes/vee/tree/main/docs/schemas/widget-card.schema.json):

```ts
Node.Text("hi", { columns: 4 });   // TypeScript: compile error
```

```python
Node.Text("hi", columns=4)
# TypeError: 'columns' is not a valid option for a 'text' node; it accepts families, style
```

```go
vee.Node.Text("hi", vee.Columns(4))
// cannot use vee.Columns(4) (value of func type vee.gridOnlyOpt) as
// vee.LeafOpt value in argument to vee.Node.Text
```

## The no-build-step note (TypeScript)

For TypeScript there is deliberately no compiler or bundler in the loop. Node 24+ strips the TypeScript types at load time and runs the file, so:

- Your plugin is a plain `.ts` file with a `#!/usr/bin/env node` shebang.
- You edit it and Vee re-runs it — nothing to compile.
- The SDK ships as source (`src/vee.ts`), imported directly.

Python plugins run the same way (no build). Go plugins are compiled once to a binary, which Vee then runs like any other executable plugin.

## Drift guard and fixtures

The SDKs, the golden fixtures, and the Swift parser are kept in lockstep by a fixture drift guard:

- Each example (`examples/*.ts`, `python/examples/*.py`, `go/examples/*`) builds a menu and its committed output lives in `fixtures/<name>.txt`.
- Each SDK's test asserts that its examples still match those fixtures.
- The **same fixtures** are shared byte-for-byte across all three SDKs and are parsed by the Swift `VeePluginFormat` tests. So if any SDK's output ever diverges from what the Swift parser expects, a test fails on one side or the other.

Commands:

```sh
# TypeScript (run from plugins/typescript)
npm test                 # run the drift guard (node --test)
npm run build:fixtures   # regenerate fixtures from the examples

# Python (run from plugins/python)
python3 -m unittest discover -s test -v

# Go (run from plugins/go)
go test ./...
```

If you change an SDK's output, regenerate the fixtures and run the tests — and the Swift-side tests will confirm the parser still agrees.

## See also

- [Writing plugins with an LLM](writing-plugins-with-an-llm.md) — the SDKs make several of the format's easiest mistakes impossible.

- [Plugin authoring reference](plugin-authoring.md) — the underlying text format the SDKs emit, including the rich params.
- [JSON output format](json-output.md) — the optional structured-JSON alternative to the text protocol.
- [Getting started](getting-started.md) — where the plugins folder is.
- Python SDK README — [`plugins/python/README.md`](https://github.com/navbytes/vee/tree/main/plugins/python/README.md).
- Go SDK README — [`plugins/go/README.md`](https://github.com/navbytes/vee/tree/main/plugins/go/README.md).
