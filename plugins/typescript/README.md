# Vee TypeScript SDK

A tiny, zero-dependency TypeScript SDK for writing Vee plugins with typed
builders instead of hand-formatting the xbar/SwiftBar text protocol. It mirrors
the [Python](../python) and [Go](../go) SDKs — same builder shape, option names,
encoding order, and quoting — and produces byte-identical output. Node runs the
TypeScript directly (type-stripping), so there is no build step.

## Requirements

- Node 24+ (for native TypeScript execution). No dependencies.

## Installing

A Vee plugin is a single executable dropped in your plugins folder — no build
step, no `node_modules`. The SDK therefore travels *with* the plugin as a
sibling file rather than being resolved from a package manager:

```sh
vee sdk ts --out ~/path/to/your/plugins   # writes vee.ts there
```

```ts
import { Menu } from "./vee.ts";
```

`vee new --lang ts --out DIR` does both at once — it scaffolds a plugin and
writes `vee.ts` beside it, so the result runs immediately.

**Or from npm**, if your plugin is part of a project that already has a
`node_modules` — a bundled plugin, or one you build before dropping in:

```sh
npm install @navbytes/vee
```

```ts
import { Menu } from "@navbytes/vee";
```

The package ships compiled JavaScript with type declarations, because Node
refuses to strip types under `node_modules`. It has no dependencies, and it
carries the same version as the app it was released with — the SDK and the
parser that reads its output ship from one commit, so a matching pair is a
guaranteed-compatible pair.

The examples in this repository import `../vee.ts` because they sit next to the
SDK here. Copying one out means running `vee sdk ts` beside it and changing that
import to `./vee.ts`.

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

Make it executable (`chmod +x cpu.5s.ts`) and drop it in your plugins folder.
The `.5s` sets a 5-second refresh, exactly as with any other plugin.

## API

The three SDKs expose the same `Menu` / `Section` / options surface, method for
method, and are checked against each other so they cannot drift. Rather than
restate a third of that contract here, the full cross-language reference —
every method, every option, and the TypeScript spelling of each — lives in one
place:

**[Plugin SDKs reference](https://vee.navbytes.io/guide/sdk/)**

For the parameters themselves — what each one accepts, its default, and which
chart it belongs to — see the [plugin authoring
reference](https://vee.navbytes.io/guide/plugin-authoring/) and
[Charts](https://vee.navbytes.io/guide/charts/), both generated from
`docs/api/params.json`, the same record this SDK is verified against.

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
