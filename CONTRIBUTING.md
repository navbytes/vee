# Contributing to Vee

Thanks for your interest in Vee — a native macOS menu-bar script runner and a
modern successor to [xbar](https://github.com/matryer/xbar) /
[SwiftBar](https://github.com/swiftbar/SwiftBar). Contributions of all kinds are
welcome: bug reports, fixes, new plugins for the showcase, plugin-format
features, and documentation.

This guide covers how to get set up, where things live, and how to get a change
merged.

## Ground rules

- **Be kind.** Assume good faith and keep discussion technical.
- **Zero third-party dependencies in what ships.** Vee ships with no external
  Swift packages. A PR that adds one will almost always be declined — please
  open an issue to discuss before writing code that needs one.

  The documentation site under `docs-site/` is the one deliberate exception: it
  builds with Astro and Starlight. Nothing it pulls in is linked into a binary,
  executed by a user, or vendored into a plugin, and it is confined to that
  directory. The policy protects the product, not the repository.
- **Tests come with the change.** Vee is built test-first (a comprehensive XCTest suite).
  New behavior needs new tests; a bug fix needs a test that fails before and
  passes after.

## Requirements

- **macOS 26+** on Apple Silicon (arm64). The package targets `.macOS("26.0")`
  for the Liquid Glass UI, so older SDKs cannot build the app.
- **Swift 6.2+ / Xcode 26+.**
- **XcodeGen** — only if you build the packaged `.app` bundle
  (`brew install xcodegen`).

## Development setup

```sh
git clone https://github.com/navbytes/vee.git
cd vee

swift build          # build the libraries + the dev `vee` executable
swift test           # run the XCTest suites (TDD — keep these green)
swift run vee        # run the menu-bar app for local development
```

Building the distributable, signed-style app bundle (not needed for most
changes, but exercised in CI):

```sh
xcodegen generate                                   # project.yml -> Vee.xcodeproj
xcodebuild -project Vee.xcodeproj -scheme Vee build # build the app target
```

## Where things live

Vee is a modular SwiftPM package. All testable logic lives in library targets;
the `vee` executable is a thin entry point.

| Module            | Responsibility |
| ----------------- | -------------- |
| `VeeCore`         | Shared primitives: `RefreshInterval`, `PluginFilename`, `PluginID`, clock, errors. |
| `VeePluginFormat` | Pure xbar/SwiftBar output + header parser (`---`/`--` menus, `\|` params, `<xbar.*>`/`<swiftbar.*>` headers, ANSI, emoji, JSON, colors). |
| `VeeRuntime`      | Plugin discovery, leak-free execution, scheduling, and `~~~` streaming. |
| `VeeMenu`         | `ParsedOutput` -> `NSMenu` (colors, ANSI, SF Symbols, actions). |
| `VeePreferences`  | `<xbar.var>` preference sidecar + Keychain-backed secret store. |
| `VeeTrust`        | `<vee.*>` capability declarations -> advisory trust summaries. |
| `VeeCatalog`      | The `matryer/xbar-plugins` catalog client + installer (fetch, parse, freshness, provenance). |
| `VeeUI`           | SwiftUI settings and plugin-manager windows. |
| `VeeWidgetShared` | Foundation-only snapshot model + store shared with the WidgetKit / Control Center extension. |
| `VeeCLI`          | AppKit-free logic for the `vee render`/`lint`/`new`/`search`/`show`/`dev` authoring subcommands. |
| `VeeApp`          | AppKit shell: status items, coordinators, app delegate (as a library). |
| `vee`             | Thin executable entry point: boots the app, or dispatches CLI subcommands. |
| `plugins/`        | Showcase example plugins (`showcase/`) and parser-conformance golden fixtures (`fixtures/`). |
| `docs/`           | Documentation sources: guides in `docs/_content/*.md`, the parameter record in `docs/api/params.json`, JSON Schemas, the hand-written landing and comparison pages, and the guard scripts. Nothing here is generated output. |
| `docs-site/`      | The Astro + Starlight build that turns `docs/` into the published site. The only third-party dependency in the repository. |

For a deeper tour of how the pieces fit together — the execution pipeline, the
leak-free design, the trust model, and the widget channel — see
**[ARCHITECTURE.md](ARCHITECTURE.md)**.

App bundle configuration lives in `project.yml` (XcodeGen spec) and `App/`
(Info.plist properties + entitlements). Showcase example plugins live in
`plugins/showcase/` — see `plugins/showcase/README.md`.

### Docs

The guides are written in `docs/_content/*.md`. Nothing under `docs/` is
generated output any more — the site is built from these sources by
`docs-site/` and deployed by `.github/workflows/docs.yml`. Preview a change the
way you would any web project:

```sh
cd docs-site && npm install && npm run dev
```

Each page carries its own frontmatter: `title`, `description` (the site's SEO
metadata *and* its one-line summary in `llms.txt`), and `sidebar.label` /
`sidebar.order`, which drive the sidebar and the prev/next pager. Adding a
guide means adding the file; there is no page list to update.

The build also emits the machine-readable forms Vee publishes for LLM and agent
consumers: a Markdown mirror of every page at `/guide/<slug>.md` with a
`<link rel="alternate">` pointing at it, `llms.txt`, `llms-full.txt`, the
parameter record at `/api/params.json`, and a redirect from every page's old
`.html` URL. Search is a [Pagefind](https://pagefind.app) index built from the
pages at build time — there is no index to regenerate and none to commit.

**The parameter surface is data.** `docs/api/params.json` records every
menu-line parameter with its type, accepted values, default, group, and the
chart it belongs to. The reference tables in the published guides are generated
from it into `docs/_content/_generated/`, and pulled into a page with an
ordinary Markdown link:

```markdown
[**The full parameter table** →](_generated/params-table.md)
```

The site splices the table in where that link sits; on GitHub, which renders
`docs/_content/*.md` directly, it stays a link to the same file. That is why
the partials are committed and why the directive is a link rather than an HTML
comment — a comment renders as nothing, which left both generated tables
invisible to anyone reading the docs in the repository.

Do not hand-edit a generated table:

```sh
python3 docs/scripts/build_reference.py          # write the generated partials
python3 docs/scripts/build_reference.py --check  # fails if a partial is stale
```

Four checks run on docs in CI, all pure standard library — the
`build_reference.py --check` above, plus these three:

```sh
python3 docs/scripts/check_params.py   # parser, linter, and docs agree on the
                                       # parameter set, and on the constants the
                                       # docs state about it
python3 docs/scripts/check_schemas.py  # docs/schemas matches the shipped fixtures
python3 docs/scripts/check_links.py    # every documented repository and same-site link
                                       # resolves, anchors included
```

### A rule of thumb for where a change goes

- Parsing or interpreting plugin output/headers -> `VeePluginFormat`.
- Running plugins, scheduling, streaming -> `VeeRuntime`.
- Rendering to the menu -> `VeeMenu`.
- New `<vee.*>` capability or trust heuristic -> `VeeTrust`.
- New `<xbar.var>` behavior or secret handling -> `VeePreferences`.
- UI/windows -> `VeeUI` / `VeeApp`.

Keep the pure targets (`VeeCore`, `VeePluginFormat`, `VeeTrust`) free of AppKit
so they stay unit-testable in isolation.

## Coding style

- **Match the surrounding Swift.** Follow the conventions already in the file
  you are editing (naming, doc comments, access control). Public API gets a `///`
  doc comment explaining intent.
- **SwiftLint** runs advisory in CI (`.swiftlint.yml`). It won't block the
  build, but keep new code clean — don't add force casts/tries, and prefer
  clear names.
- **No new dependencies** (see Ground rules).
- **Determinism in the pure targets.** Parsers must never throw on malformed
  input — return best-effort output plus diagnostics, as the existing parsers do.

## Tests (TDD)

- Add tests in the matching `Tests/<Module>Tests` suite.
- For plugin-format changes, prefer a golden fixture in `plugins/fixtures/`
  (parsed by `FixtureRoundTripTests`) when it fits.
- Run `swift test` locally before pushing.

## Pull request flow

1. **Branch** from `main` (e.g. `fix/streaming-backoff`, `feat/sfimage-color`).
2. Make the change **with tests**. Keep commits focused.
3. Ensure **CI is green**. CI runs:
   - **SwiftPM** `swift build` + `swift test` on `macos-26`.
   - **App bundle** `xcodegen generate` + unsigned `xcodebuild` on `macos-26`.
   - **SwiftLint** (advisory — annotates, doesn't block).
4. Open the PR using the template. Describe what changed, why, and how you
   tested it. Link any related issue.
5. Respond to review. Squash-friendly, focused history is appreciated.

### Commit messages

Write imperative, present-tense subjects that say what the commit does, and keep
the subject reasonably short:

```
Add sfimage color support to title lines

Explain the why in the body if it isn't obvious from the subject. Reference
issues with "Fixes #123" when applicable.
```

The existing history uses concise, descriptive subjects (occasionally with a
`type:` prefix like `release:`); match that. Conventional Commits are welcome but
not required.

## Proposing a new plugin

- **`plugins/showcase/`** — copy-paste showcase plugins (plain shell) that
  demonstrate Vee features and the trust model. Add here for a runnable,
  well-commented demo. Not wired into the test suite.
- **`plugins/fixtures/`** — parser-conformance goldens for
  `FixtureRoundTripTests`, not an authoring reference. Add here only alongside
  a Swift parser change that needs a new fixture.

To propose a plugin for the community catalog/gallery, open an issue using the
**Plugin submission** template. Include what it does, its language and
dependencies, its declared `<vee.*>` capabilities, and a link to the source. Good
plugins are self-contained, degrade gracefully when a tool or token is missing,
and declare their capabilities honestly.

## Proposing a plugin-format feature

The format is an xbar/SwiftBar superset, so compatibility matters. Before
implementing:

1. Open an issue describing the new line param, header tag, or `<vee.*>`
   capability and the behavior you want.
2. Note whether it maps to an existing xbar/SwiftBar feature or is Vee-specific
   (Vee-specific rendering params live under the SwiftBar/`vee` groupings).
3. Once agreed, implement it in `VeePluginFormat` (and `VeeTrust` for a new
   capability) with tests and, ideally, a golden fixture.

Thanks for helping make Vee better.
