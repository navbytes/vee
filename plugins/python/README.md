# Vee Python SDK

A tiny, zero-dependency (standard-library only) Python SDK for writing Vee
plugins with typed builders instead of hand-formatting the xbar/SwiftBar text
protocol. It mirrors the [TypeScript SDK](../typescript) — same builder shape,
option names, encoding order, and quoting — and produces byte-identical output,
so a plugin reads the same in either language.

## Requirements

- Python 3.9+ (uses only the standard library).

## Installing

A Vee plugin is a single executable dropped in your plugins folder — no
virtualenv, no `pip install`. The SDK travels *with* the plugin as a sibling
file:

```sh
vee sdk py --out ~/path/to/your/plugins   # writes vee.py there
```

```python
from vee import Menu
```

No `sys.path` juggling is needed: Python already searches the running script's
own directory, so a sibling `vee.py` is importable as-is. `vee new --lang py
--out DIR` scaffolds a plugin and writes `vee.py` beside it in one step.

For a new plugin, prefer `JSONMenu` over `Menu` — see
[`examples/json-demo.py`](examples/json-demo.py) and the
[JSON output format](https://vee.navbytes.io/guide/json-output/) docs.

## Layout

```
plugins/python/
├─ vee.py            # the SDK: Menu, Section
├─ examples/*.py     # example plugins; each defines build() -> str
└─ test/             # drift guard (unittest)
```

## Hello world

Create `cpu.5s.py` in your plugins folder:

```python
#!/usr/bin/env python3
from vee import Menu  # vee.py sits beside this file

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

The three SDKs expose the same `Menu` / `Section` / options surface, method for
method, and are checked against each other so they cannot drift. Rather than
restate a third of that contract here, the full cross-language reference —
every method, every option, and the Python spelling of each — lives in one
place:

**[Plugin SDKs reference](https://vee.navbytes.io/guide/sdk/)**

For the parameters themselves — what each one accepts, its default, and which
chart it belongs to — see the [plugin authoring
reference](https://vee.navbytes.io/guide/plugin-authoring/) and
[Charts](https://vee.navbytes.io/guide/charts/), both generated from
`docs/api/params.json`, the same record this SDK is verified against.

## Naming and deprecations

Python-specific, and the one thing this SDK does not share with the other two.
Option names are **snake_case** throughout — menu options and layout-node
options alike — so the format's `templateImage` is `template_image` here,
`sfcolor` is `sf_color`, and `progresstrackcolor` is `progress_track_color`.

**Unknown options raise `TypeError`.** They used to be dropped in silence, so a
typo emitted nothing at all:

```python
d.item("Disk", progress=0.5, track_colour="gray")
# TypeError: unknown option 'track_colour'. Did you mean 'progress_track_color'?
```

Two spellings are deprecated and still work, each emitting a
`DeprecationWarning`; both go in the next major version:

| Deprecated | Use instead |
| ---------- | ----------- |
| camelCase (`trackColor`, `progressW`, `templateImage`, …) | snake_case (`progress_track_color`, `progress_w`, `template_image`, …) |
| tuple forms (`progress=(72, 100)`) | mapping forms |

## Tests

```sh
cd plugins/python
python3 -m unittest discover -s test -v
```

The drift guard runs each example's `build()` and asserts the output matches its
committed golden fixture in `../fixtures/`. Those files are shared with the
TypeScript and Go SDKs, so this keeps every SDK, the fixtures, and the Swift
parser in lockstep.
