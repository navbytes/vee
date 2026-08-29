---
title: "SDK migration guide"
description: "Vee's three official plugin SDKs (TypeScript, Python, Go) are retired. Why, what still works forever, and how to port a plugin to plain JSON output."
sidebar:
  label: "SDK migration"
  order: 8
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/sdk.md"
      title: "Markdown source"
  - tag: title
    content: "SDK migration guide — Vee docs"
---
Vee used to ship three official, zero-dependency plugin SDKs — TypeScript, Python, and Go — with typed `Menu`/`Section` builders. **They are retired.** No new versions will be published, `vee sdk` and `vee new`'s SDK-vendoring step are gone, and this page is now a migration guide instead of an API reference.

## Why

A Vee plugin is any executable printing a documented stdout format — that is the whole authoring contract, and every stdout-contract app in this lineage (xbar, SwiftBar, BitBar, Alfred, GitHub Actions) ships zero official runtime SDKs for exactly that reason: the app owns the format, docs, and lint; typed wrappers are a nice-to-have, not something the app has to keep synchronized across three languages, two package registries, and a golden-fixture suite forever. Vee's own SDK machinery had grown install vendoring, import-path injection with source-sniffing, a Node resolver hook, and a discovery filter to keep the SDK from being mistaken for a plugin — all of it there to make an *importable library* behave like *the format*, which it already is on its own. The format is the SDK now: print it directly, with an editor's own type checker giving you autocomplete via a small inlined type block (`vee new`) or the [published JSON Schema](#editor-validation).

## What still works, forever

**If your plugin has a sibling `vee.py` or `vee.ts` file beside it, it keeps running — no action needed, no expiration date.** This isn't a grace period; it's how the two languages already resolve imports:

- Python checks the script's own directory *before* anything else, so `from vee import Menu` resolves to the `vee.py` sitting next to your plugin.
- A relative TypeScript import — `import { Menu } from "./vee.ts"` — names a file directly; there is no package resolution involved at all.

Every plugin `vee new`/`vee sdk` ever scaffolded, and every plugin repository that checked its SDK copy in, already has that sibling file. It is frozen (bug fixes and new format parameters will not reach it), but it is not going to stop working.

**What breaks:** a plugin that imports the SDK with *no* sibling copy anywhere it can resolve — most commonly a bare TypeScript import of the package name:

```ts
import { Menu } from "@navbytes/vee";   // used to resolve to Vee's own copy — no longer injected
```

or a Python plugin that relied on Vee putting `vee.py` on `PYTHONPATH` rather than vendoring its own. `vee lint` catches both: a sibling-less SDK import is now a lint **error** ("the SDK is retired and this plugin cannot run"); an import with a frozen sibling present is a **warning** (it works, but won't gain anything new).

## Porting to JSON output

Reach for [Vee's structured-JSON format](json-output.md) — no escaping rules, typed values, and the format is the whole contract, so there's nothing left to import.

**Before** (TypeScript, importing the SDK):

```ts
import { Menu } from "./vee.ts";

const menu = new Menu();
menu.title("CPU 12%", { color: "green", sfimage: "cpu" });
menu.dropdown.item("Refresh", { refresh: true });
menu.print();
```

**After** (self-contained, no import):

```ts
interface JSONOutput {
  vee: 1;
  title: { text: string; color?: string; sfimage?: string }[];
  items: { text: string; refresh?: boolean }[];
}

const output: JSONOutput = {
  vee: 1,
  title: [{ text: "CPU 12%", color: "green", sfimage: "cpu" }],
  items: [{ text: "Refresh", refresh: true }],
};

console.log(JSON.stringify(output));
```

Python is the same shape with a `TypedDict` instead of an `interface` and `print(json.dumps(...))` instead of `console.log(JSON.stringify(...))` — see `vee new --lang py` for a full starting point. Go, which was always a compiled module dependency rather than a vendored file, is unaffected by any of this except that it will not gain new options.

`vee new --lang ts|py` scaffolds exactly this shape: a small inlined type block covering only the fields the template uses, then a `JSON.stringify`/`json.dumps` call — nothing to import, nothing to vendor, and an editor's own type checker gives you the autocomplete the SDK used to.

## Editor validation

The JSON output format has a [published JSON Schema](https://vee.navbytes.io/schemas/json-output.schema.json) covering the full vocabulary (well past what any one template inlines) — point `$schema` at it for full-field autocomplete and validation in an editor that understands JSON Schema:

```json
{
  "$schema": "https://vee.navbytes.io/schemas/json-output.schema.json",
  "vee": 1,
  "title": [{ "text": "CPU 12%" }]
}
```

The schema is registered in the [SchemaStore](https://www.schemastore.org/) catalog as "Vee JSON menu output", so editors with SchemaStore integration also offer it in their schema pickers.

## Published artifact status

Nothing already published is deleted or broken:

- **`@navbytes/vee` on npm** is deprecated — it stays installable forever, and any plugin already importing it (with a frozen sibling as a fallback, or run under an old Vee) keeps working. No new versions will be published.
- **The Go module** (`github.com/navbytes/vee/plugins/go`) is unaffected in the way that matters most — Go module tags are immutable, so `go get` continues to resolve every tag that was ever cut. No new tags will be cut.
- **`plugins/fixtures/`** in this repository survives, repurposed: it's no longer an SDK contract, just the parser's own conformance goldens.

## See also

- [JSON output format](json-output.md) — the format itself, the full field reference, and worked examples.
- [Plugin authoring reference](plugin-authoring.md) — the xbar/SwiftBar-compatible text format, still fully supported.
- [AGENTS.md](https://github.com/navbytes/vee/blob/main/AGENTS.md) / [`docs/llms.txt`](https://github.com/navbytes/vee/blob/main/docs/llms.txt) — the LLM-facing authoring reference, if you're generating a plugin rather than hand-writing one.
