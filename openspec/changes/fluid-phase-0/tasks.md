## 1. Protocol and SDK

- [x] 1.1 `FluidProtocol`: `ViewNode` vocabulary, `Manifest`, host and plugin messages, `LineCodec`, capped `LineBuffer`
- [x] 1.2 `FluidKit`: result-builder DSL, `RenderContext` with content-derived action ids, `FluidPlugin`, `PluginRuntime`, stdio transport with stdout redirection

## 2. Host core

- [x] 2.1 `PluginProcess`: spawn, bounded pipe drains, ordered events, terminate escalation, `--manifest` reader
- [x] 2.2 `PluginSupervisor`: hello, launch and interval triggers, events, visibility, restart with `BackoffPolicy`, give up after repeated crashes
- [x] 2.3 `PluginBuilder`: generated package per plugin, content-hash cache, diagnostics mapped to the source, ad-hoc signing with entitlements (macOS)
- [x] 2.4 `SandboxEntitlements` and `TreeTextRenderer`

## 3. Surfaces and tools

- [x] 3.1 `Fluid` app: a status item per plugin, popover panel renderer, wake triggers, empty state with example install
- [x] 3.2 `fluidctl`: `build`, `manifest`, `render` with `--surface`, `--event`, `--json`, `--verbose`
- [x] 3.3 Examples: Clock, PR Cockpit; fixture plugin for tests

## 4. Verification

- [x] 4.1 Tests for protocol, DSL, runtime, supervisor (real processes), builder (real build, opt-in)
- [x] 4.2 `Fluid` CI workflow for Linux and macOS
- [ ] 4.3 On a Mac: the app runs the examples (README "What is not verified yet", step 1)
- [ ] 4.4 On a Mac: the sandbox spike (step 2)
- [ ] 4.5 On a Mac: the ExtensionKit discovery spike (step 3)
- [ ] 4.6 One-week memory gate with PR Cockpit (step 4)
