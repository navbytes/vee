# Vee — Positioning (canonical)

Internal reference for all public copy. Keep claims honest and defensible.

## Fact guardrails (get these right)

- **xbar is not Electron.** Since its v2 rewrite xbar is **Go + Wails (WKWebKit WebView)**. *BitBar* — the deprecated predecessor — was the Electron one. Never write "xbar is Electron."
- Aim the performance argument at xbar's **documented, still-open memory-growth reports** (RAM creeping to multiple GB), not at any architecture label: xbar issues [#731](https://github.com/matryer/xbar/issues/731), [#725](https://github.com/matryer/xbar/issues/725), [#493](https://github.com/matryer/xbar/issues/493). This is the single most defensible proof point.
- **SwiftBar is the category leader** — native Swift, light, mature, MIT, Homebrew. Do **not** claim Vee is "faster/lighter than SwiftBar." Position against SwiftBar's *gaps*: no trust layer (it auto-`chmod +x`es and runs whatever lands in the folder), plus refresh-after-sleep reliability issues ([#179](https://github.com/swiftbar/SwiftBar/issues/179), [#390](https://github.com/swiftbar/SwiftBar/issues/390)). Never disparage it.
- Real limits, stated plainly: **macOS 26+, Apple Silicon only, no Homebrew cask yet.**

## Positioning statement

For macOS power users and developers who live in the menu bar, **Vee** is a native, leak-free script runner that runs your existing xbar and SwiftBar plugins unchanged — and, uniquely, tells you in plain language what each plugin will touch before you install it. Unlike xbar's WebView runtime that users have reported ballooning to gigabytes of RAM, and unlike SwiftBar's fire-and-forget "drop a file, we run it" model, Vee pairs pure-Swift efficiency with trust-at-install transparency.

## Taglines

- **Primary (hero):** Every xbar plugin. None of the memory leaks.
- **Secondary (trust):** Run any script in your menu bar. See what it touches first.
- **Cold audience (no xbar knowledge):** A native macOS app that turns any script into a live menu-bar widget.

## Messaging pillars (in order)

1. **Native and leak-free — built to run forever.** Pure Swift/AppKit, no WebView runtime, careful subprocess handling; stays light for days.
2. **Drop-in for everything you already have.** A superset of both the xbar *and* SwiftBar protocols — your plugins just work, unchanged.
3. **Trust at install, not blind execution.** (The standout — uncontested.) Plugins declare what they touch; a plain-language summary and badges show the reach before you grant it. Transparency, not a sandbox.
4. **Discover and install in one click.** A built-in browser over the xbar catalog, with trust chips and a Plugin Manager.
5. **A real SDK for authors.** Typed, zero-dependency TypeScript SDK, no build step, fixture drift guard.

## Personas

1. **Menu-bar power user** (primary convert) — already runs 5–15 plugins on xbar/SwiftBar. Converts on zero-switching-cost drop-in compat + the leak/reliability fix.
2. **Security-conscious developer** (uncontested) — wants the automation but distrusts running arbitrary un-sandboxed code. Only Vee serves them, via the trust layer. Give this disproportionate weight.
3. **Plugin author / tinkerer** (ecosystem flywheel) — converts on the typed SDK + trust-badge signal + Discover distribution.

## Objection → response (short forms)

- *"Why not SwiftBar?"* → Vee is a superset of it; the difference is the trust layer, the built-in Discover catalog, refresh reliability, and a typed SDK. Same native lightness, more finish.
- *"Un-sandboxed = unsafe."* → Every tool in the category runs plugins un-sandboxed; it's inherent. The honest question is "do you know what you're running?" Vee is the only one that makes plugins declare their reach and shows it before install. Transparency, not enforcement.
- *"macOS 26 only?"* → Deliberate — a modern base is *why* it's clean. Forward bet. Need older macOS today? SwiftBar covers 10.15+.
- *"Apple Silicon only?"* → arm64 only, keeps the binary lean; that's where the install base is heading.
- *"Yet another menu-bar app / new format?"* → The opposite — it runs the xbar *and* SwiftBar formats you already use, unchanged. Nothing to port.

## One-liner (verbatim-usable)

Vee runs every xbar and SwiftBar plugin you already have — natively, without the memory leaks, and it tells you what each one touches before you install it.
