# Vee — Design Language

> **Ethos: disappear into macOS.** Vee has almost no "custom" visual design, and
> that is the point. Every atom — color, type, material, iconography, motion — is
> borrowed from the system, then arranged in the Spotlight/Raycast command-palette
> layout. Originality is spent on *layout and restraint*, not on a skin. Because
> nothing is hardcoded, the app inherits Light/Dark, the user's accent color,
> Increase Contrast, and Reduce Motion for free.

This document is the contract for the launcher's look and for any new screen or
plugin surface. It is tied to source — the numbers below come from the
`private enum UI` token block and the view builders in
[AppKitAdapters.swift](../Sources/VeeApp/AppKitAdapters.swift).

---

## 1. Principles

1. **System-semantic color, zero hex.** Color is always a *role*
   (`labelColor`, `secondaryLabelColor`, …, `controlAccentColor`,
   `separatorColor`), never a literal value. This is the single biggest "native"
   cue and what makes theme/accent/contrast adaptation automatic.
2. **Real material, not a faked blur.** A borderless floating panel over an
   `NSVisualEffectView` (`.sidebar`, behind-window) — genuine macOS vibrancy.
3. **The system type ramp, three weights only** — regular / medium / semibold.
   No bold, no light, no custom font.
4. **An 8-pt grid with one disciplined alignment line** — the 20-pt gutter that
   the search glyph, section headers, and every row icon share.
5. **Selection is a floating tinted pill, not a bar** — accent color at low
   alpha, inset from the row edges.
6. **Menu-grade key-cap chips** for shortcuts — the same vocabulary as native
   menu shortcut hints.
7. **Fast, subtle, accessible motion** — a ~0.12 s entrance; Reduce Motion
   downgrades to a crossfade with no movement.
8. **Content-forward chrome** — no title bar or window buttons; hero search →
   results → a thin action-bar footer.

---

## 2. Design tokens

The whole geometry system is centralized in `private enum UI`
([AppKitAdapters.swift:14](../Sources/VeeApp/AppKitAdapters.swift)). One enum is
the single knob for evolving the look.

| Token | Value (pt) | Role |
|---|---|---|
| `panelWidth` × `panelHeight` | 720 × 470 | launcher panel size |
| `cornerRadius` | 14 | panel + backdrop corner |
| `rowHeight` | 40 | list row |
| `gutter` | 20 | shared left edge (search icon, section, row icons) |
| `listInset` | 4 | scroll inset; selection pill floats ~10 pt from the panel edge |
| `iconSize` | 26 | row / detail icon |
| `rowCornerRadius` | 8 | selection pill corner |
| `footerHeight` | 36 | action-bar footer |
| `emptyGlyph` | 32 | empty-state SF Symbol point size |

---

## 3. Color — semantic roles

Never introduce a hex literal. Pick the role; the system resolves it per
appearance, accent, and contrast setting.

| Role (`NSColor`) | Used for |
|---|---|
| `labelColor` | titles, body, detail text, search input |
| `secondaryLabelColor` | subtitles, non-app glyph tint |
| `tertiaryLabelColor` | hints, section headers, search magnifier, empty glyph, accessory text |
| `quaternaryLabelColor` | key-cap chip fill |
| `controlAccentColor` | selection pill, matched-character highlight |
| `separatorColor` | key-cap chip border, hairline rules |
| `windowBackgroundColor` (0.92α) | toast banner fill |

**Selection pill** ([AppKitAdapters.swift](../Sources/VeeApp/AppKitAdapters.swift),
`drawSelection`): rounded rect inset `dx 6, dy 4` (≈32 pt tall in a 40 pt row),
radius 8, filled `controlAccentColor` at **0.13α light / 0.11α dark**, stroked at
**0.20α light / 0.16α dark**, 1 pt line. Tinted and translucent — never a solid
fill.

**Match highlight:** matched characters render semibold in `controlAccentColor`;
the rest of the title stays medium `labelColor`.

---

## 4. Typography

System font throughout. Three weights only.

| Element | Size | Weight | Notes |
|---|---|---|---|
| Search field | 20 | regular | the hero input |
| Detail title | 16 | semibold | |
| Empty-state title | 15 | semibold | |
| Row title | 13 | medium | |
| Row / detail subtitle | 12 | regular | secondary color |
| Section header · key caps | 11 | semibold | +0.5 pt tracking |

---

## 5. Components

- **Search field** — 20 pt regular, `labelColor`; placeholder
  "Search for apps and commands…"; leading SF Symbol magnifier (17 pt regular,
  tertiary). No box/border — it sits directly on the vibrant backdrop.
- **List row** — 40 pt tall; `gutter`-aligned 26 pt icon, then a title/subtitle
  vertical stack; right edge carries (mutually exclusive) accessory text *or*
  key-cap chips. App rows show real `NSWorkspace` icons; others use tinted SF
  Symbols.
- **Selection pill** — see §3.
- **Key-cap chip** (`KeyCapView`) — `quaternaryLabelColor` fill, 0.5 pt
  `separatorColor` border, 5 pt radius, 18 pt tall, width = `max(glyph + 10, 22)`
  so a single glyph hugs tight (parity floor for `↩` / `⌘K`); 11 pt medium
  secondary glyph. Multi-key shortcuts render as separate chips with 4 pt gaps.
- **Section header** — 11 pt semibold tertiary, +0.5 tracking, gutter-aligned.
- **Footer action bar** — 36 pt; left shows the selected item's primary action
  (`↩ Run`) or a muted contextual hint; right shows `Actions ⌘K`. Mirrors
  Raycast's bottom bar.
- **Empty state** — centered 32 pt SF Symbol (tertiary) + 15 pt semibold title
  (secondary) + description (tertiary).
- **Detail** — 16 pt semibold title + 12 pt subtitle + Markdown-rendered body.
- **Toast** — transient banner, `windowBackgroundColor` at 0.92α, 9 pt radius,
  SF-Symbol + tint by style (success / failure / info), auto-dismiss ~2.5 s.

---

## 6. Window chrome

A `KeyForwardingPanel` (`NSPanel`) configured as:
`styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView]`,
`level: .floating`, `backgroundColor: .clear`, `isOpaque: false`,
`hasShadow: true`, `isMovableByWindowBackground: true`. The content sits on an
`NSVisualEffectView` (`material: .sidebar`, `blendingMode: .behindWindow`, layer
`cornerRadius: 14`); the table view is clear-backed so vibrancy shows through.

---

## 7. Motion

Fast and subtle; always gated on `accessibilityDisplayShouldReduceMotion`.

| Transition | Default | Reduce Motion |
|---|---|---|
| Launcher show | ~0.12 s fade + slight upward settle (rise + scale), ease-out | ≤0.1 s crossfade, no movement |
| Launcher hide | quick fade | instant |
| Toast in / out | 0.12 s / 0.18 s | alpha only |

Nothing bouncy, nothing slow.

---

## 8. Iconography

SF Symbols for all UI glyphs (magnifier, empty state, section, toast, footer);
real per-app icons via `NSWorkspace.icon(forFile:)` (LRU-cached). Symbol glyphs
that aren't real app icons are tinted with secondary/tertiary label color so they
recede behind content.

---

## 9. Accessibility

Treated as part of the design, not an afterthought:

- Each row is a single VoiceOver element — `.button` role, a composed label
  ("Title, Subtitle, Accessory, ⟨spoken shortcut⟩"), and a role-description of
  "application" or "command". Decorative glyphs are marked non-accessibility.
- Key caps carry spoken labels ("Command", "Return").
- Reduce Motion is honored (§7); semantic colors deliver Increase Contrast for
  free.

---

## 10. Extending the language

- **New geometry?** Add/adjust a token in `enum UI` — don't scatter magic
  numbers in view code.
- **New color?** Use a semantic `NSColor` role. If you need emphasis, prefer
  `controlAccentColor` at low alpha (the selection-pill pattern) over a new hue.
- **New surface (screen or plugin view)?** Reuse the row, chip, footer, and
  empty-state components and the type ramp above. A plugin's render tree projects
  through the same `ListItemViewModel` / `DetailViewModel`, so it inherits this
  language automatically.
- The Settings window
  ([SettingsWindowController.swift](../Sources/VeeApp/SettingsWindowController.swift))
  is a standard AppKit window that follows the same system-font + semantic-color
  discipline.

Regression guard for the chip-hugging rule lives in
[KeyCapLayoutTests.swift](../Tests/VeeAppTests/KeyCapLayoutTests.swift); visual
states are verifiable via the offscreen snapshot harness (see
[MANUAL-VERIFY.md](MANUAL-VERIFY.md)).
