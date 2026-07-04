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
- **Zero third-party dependencies.** Vee ships with no external Swift packages,
  and the TypeScript SDK is dependency-free (Node runs the `.ts` directly). A PR
  that adds a dependency will almost always be declined — please open an issue to
  discuss before writing code that needs one.
- **Tests come with the change.** Vee is built test-first (currently ~120 tests).
  New behavior needs new tests; a bug fix needs a test that fails before and
  passes after.

## Requirements

- **macOS 26+** on Apple Silicon (arm64). The package targets `.macOS("26.0")`
  for the Liquid Glass UI, so older SDKs cannot build the app.
- **Swift 6.2+ / Xcode 26+.**
- **Node 24+** — only if you touch the TypeScript SDK under `plugins/` (Node 24
  runs TypeScript natively, so there is no build step).
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

### The plugin SDK (`plugins/`)

The TypeScript SDK lives in `plugins/`. It has no build step and no
dependencies — Node runs the `.ts` files directly.

```sh
cd plugins
npm test                 # fixture "drift guard" (node --test)
npm run build:fixtures   # regenerate golden fixtures from examples/*.ts
```

The drift guard asserts that each example plugin's `build()` output still
matches its committed golden fixture in `plugins/fixtures/`. Those same fixtures
are parsed by the Swift `VeePluginFormat` tests, so the SDK, the fixtures, and
the parser stay in lockstep. If you intentionally change an example's output,
regenerate the fixtures and commit them alongside the code.

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
| `VeeCatalog`      | The plugin catalog / gallery model. |
| `VeeUI`           | SwiftUI settings and plugin-manager windows. |
| `VeeApp`          | AppKit shell: status items, coordinators, app delegate (as a library). |
| `vee`             | Thin executable entry point (`swift run vee`). |
| `plugins/`        | TypeScript plugin SDK, example plugins, and golden fixtures. |

App bundle configuration lives in `project.yml` (XcodeGen spec) and `App/`
(Info.plist properties + entitlements). Showcase example plugins live in
`examples/` at the repo root — see `examples/README.md`.

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
  (parsed by both the Swift tests and the SDK drift guard) when it fits.
- Run `swift test` locally before pushing. If you touched `plugins/`, also run
  `npm test` in that directory.

## Pull request flow

1. **Branch** from `main` (e.g. `fix/streaming-backoff`, `feat/sfimage-color`).
2. Make the change **with tests**. Keep commits focused.
3. Ensure **CI is green**. CI runs:
   - **SwiftPM** `swift build` + `swift test` on `macos-26`.
   - **App bundle** `xcodegen generate` + unsigned `xcodebuild` on `macos-26`.
   - **SwiftLint** (advisory — annotates, doesn't block).
   - **Plugin SDK** `npm test` (fixture drift guard) on Node 24.
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

Two different things live under similar names — pick the right one:

- **`plugins/examples/`** — SDK examples that double as golden fixtures for the
  drift guard. Add here only if you're demonstrating the TypeScript SDK and are
  prepared to commit a matching fixture.
- **`examples/`** (repo root) — copy-paste showcase plugins that demonstrate
  Vee features and the trust model. Add here for a runnable, well-commented demo.

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
