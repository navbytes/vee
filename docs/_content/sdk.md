# Plugin SDKs

Vee ships tiny, zero-dependency SDKs for writing plugins with typed builders instead of hand-formatting the xbar/SwiftBar text protocol. There are three, one per language — **TypeScript**, **Python**, and **Go** — and they mirror each other exactly: the same builder shape, option names, encoding order, and quoting, so a plugin reads the same in any language and all three produce **byte-identical** output for the same menu.

The SDKs live in the [`plugins/`](https://github.com/navbytes/vee/tree/main/plugins) directory of the repository:

- TypeScript — [`plugins/src/vee.ts`](https://github.com/navbytes/vee/tree/main/plugins/src/vee.ts)
- Python — [`plugins/python/`](https://github.com/navbytes/vee/tree/main/plugins/python) ([README](https://github.com/navbytes/vee/tree/main/plugins/python/README.md))
- Go — [`plugins/go/`](https://github.com/navbytes/vee/tree/main/plugins/go) ([README](https://github.com/navbytes/vee/tree/main/plugins/go/README.md))

Pick whichever language you are most comfortable in; the API is the same shape in all three.

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
import { Menu } from "./src/vee.ts";

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
sys.path.insert(0, "/path/to/plugins/python")
from vee import Menu

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

All three SDKs expose the same three types.

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

### Options

Options map onto the line parameters in the [authoring reference](plugin-authoring.md#line-parameters). The supported keys are the same in every SDK (in TypeScript they are `ItemOptions`; in Python keyword arguments; in Go the `Options` struct fields):

`color`, `size`, `font`, `length`, `href`, `shell` (with `params` → `param1..N`), `terminal`, `refresh`, `alternate`, `disabled`, `checked`, `key`, `tooltip`, `sfimage`, `md`, `badge`, `symbolize`.

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

Values containing spaces or `|` are quoted (and embedded quotes escaped) automatically, in every SDK — you never format the protocol by hand.

## Rich params

The richer inline controls — **sparkline**, **toggle**, **slider**, and **progress** (with their tuning params such as `trackColor`, `progressW`, and `progressH`) — are part of the **text protocol** and are documented in the [plugin authoring reference](plugin-authoring.md#line-parameters). They are emitted directly on a line, for example:

```text
Load | sparkline="12,18,9,22,30,14"
Notifications | toggle=true
Volume | slider=40 trackColor=gray
Sync | progress=0.6 progressW=120
```

Because the SDKs pass any option through to the line parameters and handle quoting/escaping for you, you can emit these from a plugin today by setting the corresponding option (using the raw parameter name). The SDKs do not yet expose dedicated typed builders for the rich params — that typed surface is planned. Until then, hand the value through as an option and let the SDK do the quoting.

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
# TypeScript (run from plugins/)
npm test                 # run the drift guard (node --test)
npm run build:fixtures   # regenerate fixtures from the examples

# Python (run from plugins/python)
python3 -m unittest discover -s test -v

# Go (run from plugins/go)
go test ./...
```

If you change an SDK's output, regenerate the fixtures and run the tests — and the Swift-side tests will confirm the parser still agrees.

## See also

- [Plugin authoring reference](plugin-authoring.md) — the underlying text format the SDKs emit, including the rich params.
- [JSON output format](json-output.md) — the optional structured-JSON alternative to the text protocol.
- [Getting started](getting-started.md) — where the plugins folder is.
- Python SDK README — [`plugins/python/README.md`](https://github.com/navbytes/vee/tree/main/plugins/python/README.md).
- Go SDK README — [`plugins/go/README.md`](https://github.com/navbytes/vee/tree/main/plugins/go/README.md).
