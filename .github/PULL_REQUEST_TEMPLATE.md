<!--
Thanks for contributing to Vee! Please fill this in so reviewers have context.
See CONTRIBUTING.md for the full flow (dev setup, module layout, TDD, CI).
-->

## Summary

<!-- What does this PR do, and why? Link any related issue (e.g. "Fixes #123"). -->

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Plugin-format change (new line param / header tag / `<vee.*>` capability)
- [ ] Showcase example plugin (`examples/`) or SDK example (`plugins/`)
- [ ] Documentation only
- [ ] Refactor / internal change (no behavior change)
- [ ] Breaking change (fix or feature that changes existing behavior)

## Testing done

<!-- How did you verify this? Which commands did you run? -->

- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift run vee` (manual check in the menu bar)
- [ ] `xcodegen generate` + `xcodebuild` (if the app target is affected)
- [ ] `npm test` in `plugins/` (if the TypeScript SDK is affected)

<!-- Describe what you tested and any manual verification: -->

## Checklist

- [ ] Tests added/updated for the change (TDD — a bug fix has a regression test).
- [ ] All tests pass locally.
- [ ] No new third-party dependencies introduced (zero-dependency policy).
- [ ] Code matches the surrounding Swift style; public API has doc comments.
- [ ] If plugin output/format changed, golden fixtures were regenerated and
      committed (`npm run build:fixtures`).
- [ ] Documentation (README / CONTRIBUTING / relevant docs) updated as needed.
- [ ] Commits have clear, imperative subjects.

## Screenshots / output

<!-- For UI or rendering changes, include before/after screenshots or the plugin
output that produced them. -->
