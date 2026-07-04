# Vee plugin SDK (TypeScript)

A tiny, zero-dependency TypeScript SDK for authoring Vee plugins with typed
builders instead of hand-formatting the xbar/SwiftBar text protocol. Node runs
the TypeScript directly (type-stripping), so there is no build step.

## Writing a plugin

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

menu.print();
```

Make it executable (`chmod +x cpu.5s.ts`) and drop it in your Vee plugins
folder. The `.5s` in the filename sets a 5-second refresh, exactly as with
xbar/SwiftBar.

## Layout

- `src/vee.ts` — the SDK (`Menu`, `Section`, `ItemOptions`).
- `examples/*.ts` — example plugins; each exports `build(): string`.
- `fixtures/*.txt` — golden output for each example.
- `test/*.test.ts` — drift guard: asserts each example's `build()` matches its
  fixture. The same fixtures are parsed by the Swift `VeePluginFormat` tests, so
  the SDK, the fixtures, and the parser stay in lockstep.

## Commands

```sh
npm test                 # run the fixture drift guard (node --test)
npm run build:fixtures   # regenerate fixtures from the examples
```

Requires Node 24+ (for native TypeScript execution).
