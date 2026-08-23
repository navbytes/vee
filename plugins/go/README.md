# Vee Go SDK

A tiny, zero-dependency (standard-library only) Go SDK for writing Vee plugins
with typed builders instead of hand-formatting the xbar/SwiftBar text protocol.
It mirrors the [TypeScript](../typescript) and [Python](../python) SDKs — same
builder shape, option names, encoding order, and quoting — and produces
byte-identical output.

## Requirements

- Go 1.21+ (uses only the standard library).

## Layout

```
plugins/go/
├─ go.mod
├─ vee.go                  # the SDK: Menu, Section, Options
├─ examples/cpu/cpu.go     # example plugin exposing Build() -> string
├─ examples/cpu/cpu_test.go# drift guard for the example
├─ examples/controls/      # rich controls: sparkline / toggle / slider / progress
├─ examples/charts/        # share charts: pie / donut / stackedbar
└─ examples/widget-layout/
```

## Hello world

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

Build it to a binary and drop it in your plugins folder as `cpu.5s`
(`go build -o cpu.5s ./...`); a compiled binary is a first-class Vee plugin. The
`.5s` sets a 5-second refresh, exactly as with any other plugin.

## API

- `Menu.Title(text, *Options)` — add a menu-bar title line.
- `Menu.Dropdown() Section` — the dropdown body (everything after `---`).
- `Menu.String()` / `Menu.Print()` — render / print the text protocol.
- `Section.Item(text, *Options)`, `Section.Separator()`,
  `Section.Submenu(text, *Options) Section`.
- `Options` — pointer fields are optional (nil is omitted). Helpers `vee.Str`,
  `vee.Int`, `vee.Bool`, `vee.Float` set them concisely. Fields match the
  TypeScript SDK's `ItemOptions`:
  - **Rendering** — Color, Size, Font, Length, Trim, Ansi, Emojize
  - **Behaviour** — Href, Shell (+ Params), Terminal, Refresh, Dropdown,
    Alternate, Disabled, Checked, Key, Tooltip
  - **Images** — Image, TemplateImage
  - **SF Symbols** — SFImage, SFColor, SFSize, SFConfig, Symbolize
  - **SwiftBar extras** — MD, Badge, Webview, WebviewW, WebviewH, Shortcut
  - **Vee-native rows** — Header, Accessory
  - **Controls** — Toggle, Slider, Progress (a fraction; or ProgressValue +
    ProgressMax for the format's two-argument form)
  - **Inline visuals** — each takes the same size/colour vocabulary:

    | Control | Size | Full width | Colour |
    | ------- | ---- | ---------- | ------ |
    | Sparkline | SparklineW, SparklineH | SparklineFullWidth | SparklineColor |
    | Progress | ProgressW, ProgressH | ProgressFullWidth | ProgressTrackColor |
    | Chart | Chart.W, Chart.H | Chart.FullWidth | Chart.Colors |

  Naming rule: inside a control's own struct the knobs are unprefixed
  (`Chart.W`), because the struct already names the control; on the flat
  `Options` they carry the control's name (`SparklineW`). `TrackColor` is the
  deprecated spelling of `ProgressTrackColor`. See the
  [SDK guide](../../docs/_content/sdk.md) for the rich-param details.

## Widget cards

Beyond menus, the SDK builds the [widget card](../../docs/_content/widgets.md)
payload a plugin prints when Vee invokes it with `VEE_TARGET=widget`:

```go
if os.Getenv("VEE_TARGET") == "widget" {
	c := &vee.WidgetCard{
		Template: vee.TemplateStat,
		Title:    vee.Str("Revenue"),
		Symbol:   vee.Str("chart.line.uptrend.xyaxis"),
		Tint:     vee.Str("green"),
		Value:    vee.Str("$18.2k"),
		Status:   vee.StatusOK,
		Items:    []vee.WidgetCardItem{{Label: "Orders", Value: vee.Str("214")}},
		Actions:  []vee.WidgetCardAction{{Kind: vee.ActionRefresh, Label: "Refresh"}},
	}
	c.Print()
	return
}
```

`Template` selects one of the five presets (`TemplateStat`, `TemplateGauge`,
`TemplateTrend`, `TemplateList`, `TemplateBoard`), or use the constructor of
the same name — matching the TypeScript and Python SDKs:

```go
vee.Stat(vee.WidgetCard{Title: vee.Str("Revenue"), Value: vee.Str("$18.2k")}).Print()
```

`vee.Stat`, `vee.Gauge`, `vee.Trend`, `vee.List`, and `vee.Board` each preset
`Template` on a card you have already filled in. `WidgetCard` has the same
`String()` / `Print()` shape as `Menu`.

For layouts the five templates cannot express, build a **layout tree** with the
`vee.Node` builders and set `Layout`:

```go
layout := vee.Node.VStack([]vee.WidgetNode{
	vee.Node.Text("CPU", vee.Style(vee.WidgetNodeStyle{Tint: vee.Str("secondary")})),
	vee.Node.Text("38%", vee.Style(vee.WidgetNodeStyle{MonospacedDigit: vee.Bool(true)})),
	vee.Node.Gauge(0.38, vee.GaugeStyle("circular")),
}, vee.Align("leading"), vee.Spacing(6))

c := &vee.WidgetCard{Layout: &layout}
c.Print()
```

`vee.Node.VStack`, `HStack`, `ZStack`, `Grid`, `Text`, `Image`, `Gauge`,
`Sparkline`, `Spacer`, and `Divider` are the full vocabulary; node options are
set with `vee.Align`, `vee.Spacing`, `vee.Columns`, `vee.MinLen`,
`vee.GaugeStyle`, `vee.Families`, and `vee.Style`.

Each builder accepts only the options that mean something for its node type, so
a mistake is a compile error rather than a key the renderer quietly ignores:

```go
vee.Node.Text("hi", vee.Columns(4))
// cannot use vee.Columns(4) (value of func type vee.gridOnlyOpt) as
// vee.LeafOpt value in argument to vee.Node.Text
```

See [Widgets](../../docs/_content/widgets.md) for every field and its limits.

## Tests

```sh
cd plugins/go
go test ./...
```

The drift guard runs the example's `Build()` and asserts the output matches its
committed golden fixture in `../fixtures/` — the same files the TypeScript and
Python SDKs assert against, keeping every SDK, the fixtures, and the Swift
parser in lockstep.
