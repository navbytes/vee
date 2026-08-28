# Roadmap

Work that is understood and wanted, but deliberately not done yet. Each entry
says what the problem is, why it was deferred, and what "done" looks like — so
picking one up doesn't mean re-deriving the decision.

This file is engineering follow-up: specific deferrals with a known shape. It is
not the product strategy — that is `docs/design/roadmap.md`, an internal record
of where Vee is heading as a product. Work that has a written proposal lives in
`openspec/changes/`, and smaller deliberate shortcuts live in `ponytail:`
comments next to the code they qualify.

## Move streaming plugins onto the hardened spawn path

**From:** August 2026 bug-bounty review, finding C3.

`StreamingProcess` launches with Foundation's `Process`. Every other plugin run
goes through `SystemProcessRunner`, which uses `posix_spawn` with
`POSIX_SPAWN_SETPGROUP` (so a timeout reaps the whole process group, not just
the child), `CLOEXEC_DEFAULT`, stdin on `/dev/null`, and a bounded drain of both
pipes. A streaming plugin gets none of that: a grandchild it backgrounds
survives, and it inherits whatever descriptors happened to be open.

Half of C3 is already fixed — stderr is captured and a non-zero exit now throws
`StreamingPluginError` carrying the tail, so a crash-looping plugin says why.
This is the other half.

Deferred because `SystemProcessRunner` is built around run-to-completion: it
resumes a continuation exactly once, caps captured output at 8 MB, and arms a
timeout. A streaming plugin runs indefinitely and yields as it goes, so this is
a real refactor of the runner's shape, not a call-site swap — with regression
risk concentrated in the streaming path, which is the hardest to test.

**Done looks like:** one spawn path for both run shapes; a streaming plugin's
process group is reaped on stop/cancel; `StreamingTests` still passes, plus a
test that a backgrounded grandchild does not outlive the session.

## Manifest-supplied catalog metadata

**From:** August 2026 bug-bounty review, findings U1 and U3.

Discover cards get their title, summary and author by downloading the plugin's
**entire source** and parsing its header — one HTTP request per card, to render
two lines of text.

Two user-visible problems fall out of that, both mitigated but not solved:

- **Search** (U1) could only match what had been fetched, so results depended on
  how far the user had scrolled. Now scoped to fields known up front — filename,
  category, and manifest title/summary — so results are stable. The cost: for a
  store whose manifest carries no metadata, search no longer looks at titles or
  descriptions at all.
- **Cost** (U3) is unchanged. A failed fetch is at least retryable now rather
  than blanking a card until relaunch.

Deferred because the fix is a store-side format change, not an app change: the
manifest has to carry `title`/`summary`/`author` per entry, and the public xbar
catalog would need generating that way.

**Done looks like:** `CatalogEntry.manifestTitle`/`manifestSummary` populated for
the built-in store; card rendering never needs `fetchSource`; search covers
titles and summaries again with no per-card download; `loadHeader` used only for
the trust footprint at the install gate.
