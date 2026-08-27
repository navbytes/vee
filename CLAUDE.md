# Vee — house rules for AI sessions

Read `CONTRIBUTING.md` for style and the PR flow. Two things it does not say:

**Surface parity.** Touching `LineParams`, `MenuAccessory`, `WidgetNode`, or
`WidgetCard` means answering what the *widget* does with the new vocabulary:
update `WidgetParity` (`Sources/VeePluginFormat/WidgetParity.swift`) and the
ledger it generates, `docs/design/surface-parity.md`. The switches carry no
`default` case, so a new menu graphic will not compile until you do; the ledger
test tells you the table to paste. Background:
`docs/design/widget-surface-contract.md`.

**Planned work lives in `openspec/`.** A change with a directory under
`openspec/changes/` has its proposal, design, and tasks there — those are the
authority; keep `tasks.md` ticked as you go.

Gate before you call it done:

```sh
swift build && swift test && swiftlint lint --strict
```
