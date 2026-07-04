# TypeScript SDK

`vee-plugins` is a tiny, zero-dependency TypeScript SDK for writing Vee plugins with typed builders instead of hand-formatting the xbar/SwiftBar text protocol. Node runs the TypeScript directly (type-stripping), so there is **no build step** — you drop a `.ts` file straight into your plugins folder.

The SDK lives in the [`plugins/`](https://github.com/navbytes/vee/tree/main/plugins) directory of the repository.

## Requirements

- Node 24 or later (for native TypeScript execution / type stripping).

## Layout

```
plugins/
├─ src/vee.ts        # the SDK: Menu, Section, ItemOptions
├─ examples/*.ts     # example plugins; each exports build(): string
├─ fixtures/*.txt    # golden output for each example
├─ test/*.test.ts    # drift guard (see below)
├─ package.json
└─ tsconfig.json
```

## Hello world

Create `cpu.5s.ts` and import the SDK:

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

Make it executable and drop it in your plugins folder:

```sh
chmod +x cpu.5s.ts
```

The `.5s` in the filename sets a 5-second refresh, exactly as with any other plugin (see [plugin authoring](plugin-authoring.md#filenames-and-refresh-intervals)). Adjust the import path to point at wherever `src/vee.ts` lives relative to your plugin.

## The API

### `Menu`

The top-level menu: title line(s) plus a dropdown.

- `title(text, options?)` — add a menu-bar title line. Call it more than once for multiple title lines.
- `dropdown` — a getter returning a `Section` for the dropdown body (everything after `---`).
- `toString()` — render the whole menu to the text protocol string.
- `print()` — write `toString()` (plus a trailing newline) to stdout. This is what a real plugin calls.

### `Section`

A menu section at a given submenu depth (0 = top level).

- `item(text, options?)` — add a menu item. Returns `this` for chaining.
- `separator()` — add a `---` divider. Returns `this`.
- `submenu(text, options?)` — add an item and return a new `Section` for its children (one level deeper).

### `ItemOptions`

Options map onto the line parameters in the [authoring reference](plugin-authoring.md#line-parameters). The supported keys are:

`color`, `size`, `font`, `length`, `href`, `shell` (with `params: string[]` → `param1..N`), `terminal`, `refresh`, `alternate`, `disabled`, `checked`, `key`, `tooltip`, `sfimage`, `md`, `badge`, `symbolize`.

For example:

```ts
d.item("Open build", { shell: "/usr/bin/open", params: ["-a", "Xcode"], terminal: false });
d.item("Inbox", { badge: "12" });
d.item("**Bold** text", { md: true });
d.item("Status :checkmark.circle:", { symbolize: true });
```

Values containing spaces or `|` are quoted automatically.

## The no-build-step note

There is deliberately no compiler or bundler in the loop. Node 24+ strips the TypeScript types at load time and runs the file, so:

- Your plugin is a plain `.ts` file with a `#!/usr/bin/env node` shebang.
- You edit it and Vee re-runs it — nothing to compile.
- The SDK ships as source (`src/vee.ts`), imported directly.

## Drift guard and fixtures

The SDK, the golden fixtures, and the Swift parser are kept in lockstep by a fixture drift guard:

- Each example in `examples/*.ts` exports a `build(): string` function.
- Its committed output lives in `fixtures/<name>.txt`.
- `test/drift.test.ts` asserts that every example's `build()` still matches its fixture.
- The **same fixtures** are parsed by the Swift `VeePluginFormat` tests. So if the SDK's output format ever diverges from what the Swift parser expects, a test fails on one side or the other.

Commands (run from `plugins/`):

```sh
npm test                 # run the drift guard (node --test)
npm run build:fixtures   # regenerate fixtures from the examples
```

If you change the SDK's output, run `npm run build:fixtures` to update the golden files, then `npm test` to confirm — and the Swift-side tests will confirm the parser still agrees.

## See also

- [Plugin authoring reference](plugin-authoring.md) — the underlying text format the SDK emits.
- [Getting started](getting-started.md) — where the plugins folder is.
