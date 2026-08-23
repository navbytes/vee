# Vee Go SDK

A tiny, zero-dependency (standard-library only) Go SDK for writing Vee plugins
with typed builders instead of hand-formatting the xbar/SwiftBar text protocol.
It mirrors the [TypeScript](../typescript) and [Python](../python) SDKs — same
builder shape, option names, encoding order, and quoting — and produces
byte-identical output.

## Requirements

- Go 1.21+ (uses only the standard library).

## Installing

A Go plugin compiles to a binary, so the SDK is a normal module dependency —
there is nothing to vendor beside the plugin:

```sh
go get github.com/navbytes/vee/plugins/go@v0.2.0   # or @latest
```

The SDK is a module in a subdirectory, so its versions come from tags prefixed
with that path (`plugins/go/v0.2.0`). Each release pushes one, and it carries
the same version as the app — the SDK and the parser that reads its output ship
together, so a matching pair is a guaranteed-compatible pair.

```go
import vee "github.com/navbytes/vee/plugins/go"
```

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

The three SDKs expose the same `Menu` / `Section` / options surface, method for
method, and are checked against each other so they cannot drift. Rather than
restate a third of that contract here, the full cross-language reference —
every method, every option, and the Go spelling of each — lives in one
place:

**[Plugin SDKs reference](https://vee.navbytes.io/guide/sdk/)**

For the parameters themselves — what each one accepts, its default, and which
chart it belongs to — see the [plugin authoring
reference](https://vee.navbytes.io/guide/plugin-authoring/) and
[Charts](https://vee.navbytes.io/guide/charts/), both generated from
`docs/api/params.json`, the same record this SDK is verified against.

## Tests

```sh
cd plugins/go
go test ./...
```

The drift guard runs the example's `Build()` and asserts the output matches its
committed golden fixture in `../fixtures/` — the same files the TypeScript and
Python SDKs assert against, keeping every SDK, the fixtures, and the Swift
parser in lockstep.
