# Vee Python SDK

A tiny, zero-dependency (standard-library only) Python SDK for writing Vee
plugins with typed builders instead of hand-formatting the xbar/SwiftBar text
protocol. It mirrors the [TypeScript SDK](../typescript) — same builder shape,
option names, encoding order, and quoting — and produces byte-identical output,
so a plugin reads the same in either language.

## Requirements

- Python 3.9+ (uses only the standard library).

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

Option names are **snake_case** throughout — menu options and layout-node
options alike:

- **Rendering** — `color`, `size`, `font`, `length`, `trim`, `ansi`, `emojize`
- **Behaviour** — `href`, `shell` (+ `params`), `terminal`, `refresh`,
  `dropdown`, `alternate`, `disabled`, `checked`, `key`, `tooltip`
- **Images** — `image`, `template_image`
- **SF Symbols** — `sfimage`, `sf_color`, `sf_size`, `sf_config`, `symbolize`
- **SwiftBar extras** — `md`, `badge`, `webview`, `webview_w`, `webview_h`,
  `shortcut`
- **Vee-native rows** — `header`, `accessory`
- **Controls** — `toggle`, `slider`, `progress` (a fraction, or `(value, max)`
  for the format's two-argument form)
- **Inline visuals** — each takes the same `<control>_w` / `<control>_h` /
  colour vocabulary:

  | Control | Size | Colour |
  | ------- | ---- | ------ |
  | `sparkline` | `sparkline_w`, `sparkline_h` | `sparkline_color` |
  | `progress` | `progress_w`, `progress_h` | `progress_track_color` |
  | `chart` | `chart["w"]`, `chart["h"]` | `chart["colors"]` |

  `sparkline_w`, `progress_w`, and `chart["w"]` all accept `"full"` to stretch
  to the row's own width.

**Unknown options raise `TypeError`.** They used to be dropped in silence, so a
typo — or the idiomatic snake_case spelling, back when these were camelCase —
emitted nothing at all:

```python
d.item("Disk", progress=0.5, track_colour="gray")
# TypeError: unknown option 'track_colour'. Did you mean 'progress_track_color'?
```

The old camelCase spellings (`trackColor`, `progressW`, `templateImage`, …)
still work and emit a `DeprecationWarning`; they will be removed in the next
major version. See the [SDK guide](../../docs/_content/sdk.md) for the
rich-param details.

## Widget cards

Beyond menus, the SDK builds the [widget card](../../docs/_content/widgets.md)
payload a plugin prints when Vee invokes it with `VEE_TARGET=widget`:

```python
import os
from vee import Stat

if os.environ.get("VEE_TARGET") == "widget":
    Stat(
        title="Revenue",
        symbol="chart.line.uptrend.xyaxis",
        tint="green",
        value="$18.2k",
        status="ok",
        items=[{"label": "Orders", "value": "214", "symbol": "bag", "tint": "blue"}],
        actions=[{"kind": "refresh", "label": "Refresh"}],
    ).print()
else:
    ...  # ordinary menu output
```

`Stat`, `Gauge`, `Trend`, `List`, and `Board` preset the card's `template`;
`widget_card(...)` is the generic constructor. Each returns an object with the
same `to_string()` / `print()` shape as `Menu`.

For layouts the five templates cannot express, build a **layout tree** with the
`Node` builders and pass it as `layout=`:

```python
from vee import widget_card, Node

widget_card(
    layout=Node.VStack(
        [
            Node.Text("CPU", style={"font": {"size": "caption"}, "tint": "secondary"}),
            Node.Text("38%", style={"font": {"size": "title"}, "monospaced_digit": True}),
            Node.Gauge(0.38, gauge_style="circular"),
        ],
        align="leading",
        spacing=6,
    ),
).print()
```

`Node.VStack`, `HStack`, `ZStack`, `Grid`, `Text`, `Image`, `Gauge`,
`Sparkline`, `Spacer`, and `Divider` are the full vocabulary. See
[Widgets](../../docs/_content/widgets.md) for every field and its limits.

## Tests

```sh
cd plugins/python
python3 -m unittest discover -s test -v
```

The drift guard runs each example's `build()` and asserts the output matches its
committed golden fixture in `../fixtures/`. Those files are shared with the
TypeScript and Go SDKs, so this keeps every SDK, the fixtures, and the Swift
parser in lockstep.
