# Vee example plugins

Copy-paste showcase plugins that demonstrate Vee's core features and its
trust/transparency layer. They are meant to be **read, learned from, and run** —
each one is heavily commented and self-contained.

> **`examples/` vs `plugins/examples/`** — don't confuse the two:
>
> - **`examples/`** (this folder) — runnable **showcase** plugins written in
>   plain shell, demonstrating the plugin format and the `<vee.*>` trust model.
>   Nothing here is wired into the test suite.
> - **`plugins/examples/`** — TypeScript **SDK** examples that double as golden
>   fixtures for the drift guard (`npm test`). Change those and you must
>   regenerate their fixtures.

## What's here

| Plugin                        | Interval | Shows off |
| ----------------------------- | -------- | --------- |
| `hello-world.10s.sh`          | 10s      | The absolute basics of the format — title, dropdown, params. No capabilities. |
| `disk-usage.30m.sh`           | 30m      | Reading system state via `df`, color-coding, an SF Symbol, and a `<vee.exec>` declaration. |
| `github-notifications.5m.sh`  | 5m       | Network access, a secret token via `<xbar.var>` + the Keychain, links, and honest `<vee.network>` / `<vee.secrets>` declarations. Degrades gracefully with no token. |
| `dev-dashboard.5m.sh`         | 5m       | The searchable filter panel (`<vee.filter>`) and a global search hotkey (`<vee.shortcut>`) over a large multi-section menu — the showcase used by `vee search`. |

## Running an example

Vee runs any executable whose filename encodes a refresh interval
(`name.<interval>.<ext>`, e.g. `cpu.5s.sh`). To try one:

1. Make it executable and drop it in your Vee plugins folder:

   ```sh
   chmod +x hello-world.10s.sh
   cp hello-world.10s.sh "<your Vee plugins folder>"
   ```

   (Files here are intentionally shipped **without** the executable bit — set it
   yourself after reviewing the source.)

2. Refresh in Vee. The plugin's first line(s) become the menu-bar item; anything
   after a line containing only `---` becomes the dropdown.

You can also run any of them straight from a terminal to see their raw output:

```sh
sh hello-world.10s.sh
```

## The format in 30 seconds

- **Title vs dropdown** — lines before the first `---` are the menu-bar
  title(s); lines after it are the dropdown. `--` prefixes nest submenu items.
- **Params** — append ` | key=value` to a line: `color`, `href`, `bash`/`shell`
  + `paramN`, `terminal`, `refresh`, `sfimage`, `md`, `ansi`, `symbolize`, and
  more.
- **Metadata** — `<xbar.title>`, `<xbar.author>`, `<xbar.desc>`, `<xbar.var>`
  (typed preferences), etc., live in comments and are language-agnostic.
- **Trust** — Vee-specific `<vee.*>` tags declare what the plugin touches
  (network, filesystem, secrets, exec). They are **advisory only** — Vee shows a
  trust summary but never enforces them (plugins run un-sandboxed). Declare them
  honestly.

See the top-level `README.md` and `CONTRIBUTING.md` for the full format and the
trust model.

> **Safety:** these examples are safe to read and run, but remember the general
> rule — a Vee plugin runs with your full user privileges. Only run plugins you
> trust, and read the source first.
