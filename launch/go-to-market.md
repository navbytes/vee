# Vee — Go-to-Market, SEO & Launch Copy

Internal launch playbook. See [positioning.md](positioning.md) for the messaging spine and fact guardrails. **All copy here has the "xbar = Electron" error removed** — aim the performance point at xbar's documented memory-growth reports, never an architecture label.

## Channel plan (sequenced)

Seed evergreen assets first, then fire the time-boxed launches in one window. **Never launch HN and Product Hunt the same day.**

| # | Venue | Effort | Payoff | Needs | When |
|---|---|---|---|---|---|
| 1 | Landing + `/compare` pages (own site) | High | Foundational | Hero screenshot + working download | T-14…T-7 |
| 2 | README polish (repo = dev product page) | Med | High | Demo GIF at top | T-10 |
| 3 | alternativeto.net (alt to SwiftBar/xbar/BitBar) | Low | High long-tail SEO | 260-char desc | T-10 (slow approval) |
| 4 | awesome-mac / awesome-macos PRs | Low-Med | Compounding backlinks | One-line entry | T-7 |
| 5 | **Show HN** | Med | Highest single spike | Working download + first comment | Day 1, Tue–Thu 08:00 PT |
| 6 | **Product Hunt** | Med-High | Durable badge + backlink | Gallery + tagline | Day 3–4, never same day as HN |
| 7 | r/macapps (rules-gated: need 10 karma, no shortened links, disclose dev) | Low | Med | Non-ad post | Day 2 |
| 8 | Lobsters `show` (needs account standing) | Low | Med | HN URL | Day 2–3 |
| 9 | Michael Tsai (mjtsai.com) | Low | Med-High authority backlink | Short factual email | Day 2–5 |
| 10 | **Homebrew cask** — own tap `navbytes/vee` ships **now** (`brew install --cask vee`); homebrew-core submission later (gated ~225★) | Med | High durability | Cask ruby file (already in repo) | Launch day (own tap); core Week 2–4 |
| 11 | MacStories / Club MacStories | Low-Med | Med editorial | Press kit | Week 1–2 |
| 12 | X + Mastodon (fosstodon) | Low | Amplify | Demo GIF | Day 1 with HN |
| 13 | r/macOS + r/apple | Low | Low-Med | Screenshot | Week 2, only if HN validated |

## Ready-to-post copy

### Show HN
**Title:** `Show HN: Vee – a native menu-bar script runner that runs xbar/SwiftBar plugins`

**First comment:**
> I built Vee because I loved xbar's idea — write a script in any language, print text, get a live menu-bar widget — but I kept having to quit and relaunch it as its memory climbed over the day. SwiftBar fixed the native side well; I wanted to go further on subprocess handling and add the things I kept wishing existed.
>
> Vee runs your existing xbar and SwiftBar plugins unchanged (same text protocol, same `<xbar.var>` prefs → an auto-generated settings form, secrets in Keychain). What's new: plugins declare what they touch — network, filesystem, secrets, exec — and you get a plain-language trust summary *before* you install. It's advisory, not a sandbox; these are still ordinary executables. There's also a built-in Discover browser over the xbar catalog with trust chips, and a typed TS SDK with no build step.
>
> macOS 26+, Apple Silicon, notarized, open source. It's v0.1.x — early, and I'd genuinely like to hear where the compatibility or trust model breaks. What would you want a menu-bar runner to guarantee?

### Product Hunt
- **Name:** Vee
- **Tagline (≤60):** `The native, leak-free successor to xbar and SwiftBar`
- **Description (≤260):** `Vee runs scripts in any language as live macOS menu-bar widgets. Drop-in compatible with your xbar & SwiftBar plugins, but native and leak-free. Plugins declare what they touch, so you see a plain-language trust summary before install. Open source, notarized.`
- **Maker comment:**
  - *Why I built it:* I wanted xbar's "any script → menu bar" magic without the memory creep. Vee is native Swift/SwiftUI with careful subprocess handling, so it stays light.
  - *Zero migration:* Your existing xbar/SwiftBar plugins run unchanged — same protocol, same typed prefs, secrets in Keychain. Point Vee at your plugins folder and go.
  - *Trust before you run it:* Plugins are just executables, so Vee makes them declare what they access (network, files, secrets, exec) and shows a plain-language summary at install. Transparency, not a sandbox — I'd love your take on where to take it.

### Reddit r/macapps
**Title:** `Vee — an open-source, native menu-bar script runner that runs your existing xbar/SwiftBar plugins [dev]`

> I'm the developer, flagging that up front. I've used xbar and SwiftBar for years to put little scripts (build status, calendar, crypto, system stats) into the menu bar. I built Vee scratching my own itch.
>
> It's a native macOS menu-bar script runner: write a script in any language, print text in the xbar/SwiftBar format, and it renders as a menu-bar item with dropdowns. Fully compatible with existing xbar and SwiftBar plugins, so there's nothing to rewrite.
>
> Two things I added that I hadn't seen elsewhere:
> - Plugins declare what they access (network / files / secrets / exec) and you get a plain-language trust summary *before* installing. Advisory, not a sandbox — these are still normal executables — but at least you're not running things blind.
> - A built-in browser over the xbar plugin catalog, and typed prefs that auto-generate a settings form (secrets go to Keychain).
>
> Requirements are real: macOS 26+, Apple Silicon only, notarized build from GitHub Releases. It's early (v0.1.x). Happy to answer anything.

## SEO

| Keyword | Target page |
|---|---|
| SwiftBar alternative | /compare/vee-vs-swiftbar |
| xbar alternative | /compare/vee-vs-xbar |
| macOS menu bar script runner | Homepage |
| bitbar replacement | /compare hub |
| menu bar automation mac | Homepage + blog pillar |
| xbar plugins / swiftbar plugins | Discover/catalog page |

- **Homepage title:** `Vee — Native macOS Menu-Bar Script Runner (xbar & SwiftBar compatible)`
- **Homepage meta:** `Turn any script into a live macOS menu-bar widget. Native, leak-free, and drop-in compatible with your xbar and SwiftBar plugins. Open source, notarized.`
- **Compare title template:** `Vee vs {Competitor}: {differentiator} — Menu-Bar Script Runner`

**Blog ideas:** (1) Migrating from xbar/SwiftBar to Vee; (2) Why long-running menu-bar apps leak memory — and how a native runtime avoids it; (3) A trust layer for menu-bar plugins (category-defining, uncontested); (4) Build a menu-bar widget in 10 lines; (5) Best xbar/SwiftBar plugins and how to run them safely; (6) BitBar is dead — the modern successor path.

## Assets checklist

**Must-have:** hero screenshot (dropdown open, live plugins); working notarized download verified on a clean machine; demo GIF (~12s: live item → Discover w/ trust chip → install trust sheet → new item live → settings form w/ secret field); OG image 1200×630; favicon (16/32/180/512); 30-sec elevator description.
**Nice-to-have:** 60–90s narrated PH video; press kit zip; extra gallery screenshots; compat-matrix graphic.

## Launch-day runbook

1. **T-14…T-7:** ship landing + both `/compare` pages (meta + OG); polish README w/ GIF; submit alternativeto.net; open awesome-* PRs.
2. **T-3…T-1:** fresh-machine download→Gatekeeper→run-a-plugin test; pre-write replies to "vs SwiftBar? sandboxed? Intel? why macOS 26? Homebrew?"; line up honest early users (never fake HN upvotes).
3. **Day 1 (Show HN, Tue–Thu 08:00 PT):** submit → post first comment → X/Mastodon thread → **tend every comment for 3h**, factually, fix trivia live.
4. **Day 2:** r/macapps (if qualified) + Lobsters (if standing) + email Michael Tsai with the HN hook.
5. **Day 3–4 (Product Hunt, 00:01 PT):** gallery + tagline + maker comment; notify network individually; reply all day.
6. **Week 1–2:** pitch MacStories; r/macOS/r/apple if HN validated; **submit to homebrew-core once the ★ threshold clears** (the own-tap `brew install --cask vee` is already live from day 1); publish blog #1 and #2; post-mortem by channel.

## Biggest strategic notes

- Keep the leak/native hammer pointed at **xbar**, never SwiftBar. HN and SwiftBar's author will catch over-claiming.
- Lead with the **macOS 26 + Apple Silicon** limits honestly — biggest conversion ceiling and the #1 "when will you support…" question.
- **Homebrew is a day-1 asset, not a reward.** The own-tap cask (`navbytes/vee`) ships at launch — `brew install --cask vee` works immediately and is a stronger Show HN / Product Hunt hook than "download a zip." Only the homebrew-core listing is star-gated; don't conflate the two. Sequence: launch with own-tap cask → HN → stars → homebrew-core PR.
- The **trust layer** is the only uncontested position. Blog #3 can define a category, not just win a comparison.
