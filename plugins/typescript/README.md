# Vee TypeScript SDK

A tiny, zero-dependency TypeScript SDK for writing Vee plugins with typed
builders instead of hand-formatting the xbar/SwiftBar text protocol. It mirrors
the [Python](../python) and [Go](../go) SDKs — same builder shape, option names,
encoding order, and quoting — and produces byte-identical output. Node runs the
TypeScript directly (type-stripping), so there is no build step.

## Requirements

- Node 24+ (for native TypeScript execution). No dependencies.

## Layout

```
plugins/typescript/
├─ vee.ts           # the SDK: Menu, Section, ItemOptions
├─ examples/*.ts    # example plugins; each exports build() -> string
├─ test/*.test.ts   # drift guard (node --test)
└─ package.json     # npm test, npm run build:fixtures
```

Golden fixtures live one level up in [`../fixtures/`](../fixtures) and are shared
by all three SDKs — see the [plugins README](../README.md).

## Hello world

Create `cpu.5s.ts` in your plugins folder:

```ts
#!/usr/bin/env node
import { Menu } from "/path/to/plugins/typescript/vee.ts";

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

Make it executable (`chmod +x cpu.5s.ts`) and drop it in your plugins folder.
The `.5s` sets a 5-second refresh, exactly as with any other plugin.

## API

### `Menu`

- `title(text, options?)` — add a menu-bar title line (call more than once for
  multiple lines).
- `dropdown` — a `Section` for the dropdown body (everything after `---`).
- `toString()` — render the whole menu to the text protocol.
- `print()` — write `toString()` to stdout. This is what a real plugin calls.

### `Section`

- `item(text, options?)` — add a menu item.
- `separator()` — add a `---` separator at this depth.
- `submenu(text, options?)` — add an item and return a `Section` for its
  submenu.

### `ItemOptions`

`color`, `size`, `font`, `length`, `href`, `shell` (+ `params`), `terminal`,
`refresh`, `alternate`, `disabled`, `checked`, `key`, `tooltip`, `sfimage`,
`md`, `badge`, `symbolize`, and the rich controls `sparkline`, `toggle`,
`slider`, `progress` (+ `trackColor`, `progressW`, `progressH`), and `chart`
(the `pie`/`donut`/`stackedbar` share charts). See the
[SDK guide](../../docs/_content/sdk.md) for the rich-param details.

## Widget cards

Beyond menus, the SDK builds the [widget card](../../docs/_content/widgets.md)
payload a plugin prints when Vee invokes it with `VEE_TARGET=widget`:

```ts
import { Stat } from "/path/to/plugins/typescript/vee.ts";

if (process.env.VEE_TARGET === "widget") {
  Stat({
    title: "Revenue",
    symbol: "chart.line.uptrend.xyaxis",
    tint: "green",
    value: "$18.2k",
    status: "ok",
    items: [{ label: "Orders", value: "214" }],
    actions: [{ kind: "refresh", label: "Refresh" }],
  }).print();
}
```

`Stat`, `Gauge`, `Trend`, `List`, and `Board` preset the card's `template`;
`widgetCard(...)` is the generic constructor. For layouts the five templates
cannot express, build a **layout tree** with the `Node` builders and pass it as
`layout`. See [Widgets](../../docs/_content/widgets.md) for every field.

## Tests

```sh
cd plugins/typescript
npm test                 # fixture drift guard (node --test)
npm run build:fixtures   # regenerate ../fixtures from the examples
```

The drift guard runs each example's `build()` and asserts the output matches its
golden fixture in `../fixtures/`. Because those fixtures are shared with the
Python and Go SDKs and parsed by the Swift `VeePluginFormat` tests, this keeps
every SDK, the fixtures, and the parser in lockstep.
