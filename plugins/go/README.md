# Vee Go SDK

A tiny, zero-dependency (standard-library only) Go SDK for writing Vee plugins
with typed builders instead of hand-formatting the xbar/SwiftBar text protocol.
It mirrors the [TypeScript](../src/vee.ts) and [Python](../python) SDKs — same
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
└─ fixtures/*.txt          # golden output (shared byte-for-byte with the TS/Python SDKs)
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
  `vee.Int`, `vee.Bool` set them concisely. Fields match the TS SDK's
  `ItemOptions`: Color, Size, Font, Length, Href, Shell (+ Params), Terminal,
  Refresh, Alternate, Disabled, Checked, Key, Tooltip, SFImage, MD, Badge,
  Symbolize, and the rich controls Sparkline, Toggle, Slider, Progress (+
  TrackColor, ProgressW, ProgressH). See the
  [SDK guide](../../docs/_content/sdk.md) for the rich-param details.

## Tests

```sh
cd plugins/go
go test ./...
```

The drift guard runs the example's `Build()` and asserts the output matches its
committed golden fixture — shared byte-for-byte with the TypeScript and Python
SDKs, keeping every SDK, the fixtures, and the Swift parser in lockstep.
