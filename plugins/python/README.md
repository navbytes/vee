# Vee Python SDK

A tiny, zero-dependency (standard-library only) Python SDK for writing Vee
plugins with typed builders instead of hand-formatting the xbar/SwiftBar text
protocol. It mirrors the [TypeScript SDK](../src/vee.ts) — same builder shape,
option names, encoding order, and quoting — and produces byte-identical output,
so a plugin reads the same in either language.

## Requirements

- Python 3.9+ (uses only the standard library).

## Layout

```
plugins/python/
├─ vee.py            # the SDK: Menu, Section
├─ examples/*.py     # example plugins; each defines build() -> str
├─ fixtures/*.txt    # golden output for each example (shared with the TS SDK)
└─ test/             # drift guard (unittest)
```

## Hello world

Create `cpu.5s.py` in your plugins folder:

```python
#!/usr/bin/env python3
import sys, os
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

Make it executable (`chmod +x cpu.5s.py`) and drop it in your plugins folder.
The `.5s` sets a 5-second refresh, exactly as with any other plugin.

## API

### `Menu`

- `title(text, **options)` — add a menu-bar title line (call more than once for
  multiple lines).
- `dropdown` — a property returning a `Section` for the dropdown body
  (everything after `---`).
- `to_string()` / `str(menu)` — render the whole menu to the text protocol.
- `print()` — write `to_string()` (plus a trailing newline) to stdout. This is
  what a real plugin calls.

### `Section`

- `item(text, **options)` — add a menu item. Returns `self` for chaining.
- `separator()` — add a `---` separator at this depth.
- `submenu(text, **options)` — add an item and return a `Section` for its
  submenu.

### Options

`color`, `size`, `font`, `length`, `href`, `shell` (+ `params`), `terminal`,
`refresh`, `alternate`, `disabled`, `checked`, `key`, `tooltip`, `sfimage`,
`md`, `badge`, `symbolize` — matching the TypeScript SDK's `ItemOptions`.

## Tests

```sh
cd plugins/python
python3 -m unittest discover -s test -v
```

The drift guard runs each example's `build()` and asserts the output matches its
committed golden fixture. Because the fixtures are shared with the TypeScript
SDK, this keeps both SDKs, the fixtures, and the Swift parser in lockstep.
