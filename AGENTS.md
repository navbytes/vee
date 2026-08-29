# AGENTS.md — writing Vee plugins

Read this if you are an LLM/agent generating a **Vee plugin** (not working on
Vee's own source — for that, see `CONTRIBUTING.md`).

## The contract

A Vee plugin is **any executable file** that prints a documented format to
stdout. No SDK, no import, no build step, no install step. The filename
encodes the refresh interval: `name.INTERVAL.ext` (e.g. `cpu.30s.sh`,
`weather.5m.py`, `builds.10m.ts`) — units `ms`/`s`/`m`/`h`/`d`; no interval
token means "run on demand only."

**Vee's three official SDKs (TypeScript, Python, Go) are retired.** Do not
write `from vee import ...` or `import { Menu } from "@navbytes/vee"` — that
import cannot resolve for a newly generated plugin and `vee lint` will reject
it. See `docs/_content/sdk.md` (the migration guide) if you encounter an
existing plugin that still has one.

## Preferred output: JSON

For a new plugin, print a single JSON object to stdout instead of the
xbar/SwiftBar text protocol — typed values, no `|`-param quoting/escaping:

```json
{"vee": 1, "title": [{"text": "CPU 12%", "color": "green", "sfimage": "cpu"}],
 "items": [{"text": "Top processes", "href": "https://example.com/procs"},
           {"separator": true},
           {"text": "Refresh", "refresh": true}]}
```

- **Schema** (validate against it, or point `$schema` at it for editor
  autocomplete): <https://vee.navbytes.io/schemas/json-output.schema.json>
- **Full field reference**: `docs/_content/json-output.md`
- **A file that exercises every field**: `plugins/showcase/kitchen-sink.1m.sh`

The xbar/SwiftBar-compatible text protocol (`title\n---\nitem | key=value`) is
still fully supported and is what every example in `plugins/showcase/` uses —
reach for it only if the plugin needs to keep running unchanged on
xbar/SwiftBar too. Full reference: `docs/_content/plugin-authoring.md`, with
the generated parameter table at
`docs/_content/_generated/params-table.md`.

If the plugin renders a **widget** (`VEE_TARGET=widget`), see
`docs/_content/widgets.md` and its schema:
<https://vee.navbytes.io/schemas/widget-card.schema.json>

## Scaffolding

`vee new --lang ts|py|sh --name "..." --interval 30s --out DIR` generates a
self-contained starting point: for `ts`/`py` it's the JSON shape above with an
inlined type block (TypeScript `interface`, Python `TypedDict`) covering just
the fields it uses — nothing to import.

## Trust declarations

If the plugin touches the network, a secret, the filesystem, or shells out to
another binary, declare it honestly with `<vee.*>` comment tags (advisory
only, never enforced — see `docs/_content/trust-model.md`):

```
# <vee.capabilities>network,exec</vee.capabilities>
# <vee.network>api.github.com</vee.network>
# <vee.exec>curl</vee.exec>
```

## Closing the loop

```sh
vee lint ./your-plugin.30s.sh   # authoring mistakes, exits non-zero on findings
vee render ./your-plugin.30s.sh # run it and print the parsed menu tree
vee dev ./your-plugin.30s.sh    # watch + re-render on every save
```

Generate, lint, feed findings back, repeat until clean. A plugin that fails to
run at all (missing interpreter, a crash before it prints anything) is itself
a lint finding.

## Complete examples

- [`plugins/showcase/hello-world.10s.sh`](plugins/showcase/hello-world.10s.sh) — the absolute basics: title, dropdown, a link, a submenu, `refresh=true`. No capabilities.
- [`plugins/showcase/disk-usage.30m.sh`](plugins/showcase/disk-usage.30m.sh) — reading system state, color-coding by threshold, an SF Symbol, graceful degradation when a dependency is missing, and a `<vee.exec>` declaration.
- [`plugins/showcase/kitchen-sink.1m.sh`](plugins/showcase/kitchen-sink.1m.sh) — every field of the JSON output format in one file: titles, rich controls (sparkline/toggle/slider/progress/charts), nested submenus, an alternate row.

## Further reading

- `docs/_content/plugin-authoring.md` — the full text-protocol reference.
- `docs/_content/json-output.md` — the full JSON output reference.
- `docs/_content/trust-model.md` — the `<vee.*>` capability tags.
- `docs/_content/debugging.md` — `vee lint`/`vee dev`/`vee render` in full.
- `docs/llms.txt` — the same pointers in `llms.txt` form.
