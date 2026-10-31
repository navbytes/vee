## Why

Vee's script model fits a world where writing an app was expensive. Now that an
AI writes most code, the scarce things are a UI vocabulary an AI can target
reliably, the platform services a small app needs, and a sandbox for code
nobody read line by line. The successor, Fluid, is a separate app for Swift
plugins. Naveen decided on Swift only (2026-10-31), because supporting many
languages buys nothing when the code is AI-written, and the compiler checks
what the AI produces. Vee keeps its script and xbar users. The full reasoning
is in the design doc linked from `Fluid/README.md`.

## What Changes

- Add a standalone SwiftPM package, `Fluid/`, with `FluidProtocol`, `FluidKit`,
  `FluidHostCore`, the `Fluid` menu-bar app and the `fluidctl` CLI.
- Add two example plugins (Clock, PR Cockpit) and a fixture plugin for
  supervisor tests.
- Add a `Fluid` CI workflow (Linux and macOS) that runs only when `Fluid/`
  changes.
- Vee's own sources, tests and workflows are untouched.

## Impact

- Code: new `Fluid/` directory and `.github/workflows/fluid.yml` only.
- Vee users: none.
- Follow-up: move Fluid to its own repository once it has one, and extract
  Vee's process runner into a package both apps share (phase 1).
