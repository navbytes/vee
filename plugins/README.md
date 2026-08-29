# Vee plugins

A Vee plugin is any executable that prints the xbar/SwiftBar text format, or
Vee's optional structured-JSON format, to stdout — no SDK, no build step, no
install step. This folder holds the runnable examples and the parser's own
test fixtures.

| Folder | What it is |
| ------ | ---------- |
| [`showcase/`](showcase/) | **Showcase plugins** in plain shell — heavily commented, meant to be read and run. Start here. |
| [`fixtures/`](fixtures/) | Golden plugin output the Swift parser is tested against (`FixtureRoundTripTests`). Not an authoring reference — see `showcase/` for that. |

## Writing a plugin

See the [plugin authoring reference](../docs/_content/plugin-authoring.md) for
the full text-protocol format, the [JSON output format](../docs/_content/json-output.md)
for the recommended structured alternative (with a
[published JSON Schema](../docs/schemas/json-output.schema.json) editors can
validate against), and [`showcase/`](showcase/) for commented, runnable
examples of both plus the `<vee.*>` trust model.

`vee new` scaffolds a self-contained starting point in shell, TypeScript, or
Python — the TS/Python templates build the JSON output directly, with an
inlined type block for editor autocomplete and nothing to import.

Previously this repository also shipped three official runtime SDKs
(TypeScript/Python/Go). They were retired — see the
[migration guide](../docs/_content/sdk.md) if you have a plugin that imports
one.
