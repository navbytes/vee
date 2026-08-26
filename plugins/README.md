# Vee plugins

Everything for authoring Vee plugins: three SDKs, one shared set of golden
fixtures, and a set of runnable showcase plugins.

| Folder | What it is |
| ------ | ---------- |
| [`showcase/`](showcase/) | **Showcase plugins** in plain shell — heavily commented, meant to be read and run. Start here. |
| [`typescript/`](typescript/README.md) | The **TypeScript SDK** — zero-dep, Node 24+ runs it directly. |
| [`python/`](python/README.md) | The **Python SDK** — standard library only. |
| [`go/`](go/README.md) | The **Go SDK** — standard library only. |
| [`fixtures/`](fixtures/) | **Golden output**, shared by all three SDKs. See below. |

Each SDK folder has the same shape: a README, the single SDK file
(`vee.ts` / `vee.py` / `vee.go`), `examples/`, and a test.

## The shared fixtures

The three SDKs expose the same builders and produce **byte-identical** output.
`fixtures/` is what makes that true rather than aspirational: every SDK's drift
guard asserts its examples' output against these same files, and the Swift
`VeePluginFormat` round-trip tests parse them too. One set of goldens is the
contract between four implementations — change any SDK's output and the other
three fail until they agree.

Regenerate them from the TypeScript examples:

```sh
cd plugins/typescript && npm run build:fixtures
```

Then run all four suites; anything that disagrees is a real divergence, not a
stale copy:

```sh
cd plugins/typescript && npm test
cd plugins/python     && python3 -m unittest discover -s test
cd plugins/go         && go test ./...
swift test --filter FixtureRoundTripTests    # from the repo root
```

## Writing a plugin

A plugin is any executable that prints the xbar/SwiftBar format to stdout — the
SDKs just save you from hand-formatting it. The filename encodes the refresh
interval (`cpu.5s.ts`, `disk.30m.sh`), exactly as with xbar/SwiftBar.

See the [SDK guide](../docs/_content/sdk.md) for the full format, each SDK's
README for its API, and [`showcase/`](showcase/) for commented, runnable
examples of the format and the `<vee.*>` trust model.

For a **new** plugin, prefer each SDK's `JSONMenu` builder (or hand-printing
Vee's [structured-JSON format](../docs/_content/json-output.md) directly) over
the text-emitting `Menu` — see `examples/json-demo.*` in each SDK folder, and
[`showcase/kitchen-sink.1m.sh`](showcase/kitchen-sink.1m.sh) for one file
exercising every JSON field.
