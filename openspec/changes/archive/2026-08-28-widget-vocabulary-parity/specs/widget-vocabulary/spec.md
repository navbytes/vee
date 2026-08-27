# widget-vocabulary Specification

## Purpose

Defines what the widget surface can express — extending its bounded vocabulary
with category charts and tappable rows — and guarantees that every menu display
graphic and action kind has a recorded, build-enforced widget disposition, so
the widget can lag the menu only on purpose, never silently.

## ADDED Requirements

### Requirement: The layout tree renders category charts

The widget layout tree SHALL accept a `chart` leaf carrying a chart kind (pie,
donut, or stacked bar), a series of values, and optional per-segment labels and
colors — the same chart kinds the menu surface draws. Values SHALL be sanitized
the way existing numeric leaves are: non-finite entries dropped, counts capped,
and an unknown chart kind SHALL degrade to a recorded diagnostic rather than
failing the card.

#### Scenario: A share chart on a widget

- **WHEN** a plugin's widget card declares a `chart` leaf with kind pie, donut,
  or stacked bar and a series of values
- **THEN** the widget renders that chart natively, with declared segment colors
  honored

#### Scenario: A malformed chart degrades safely

- **WHEN** a `chart` leaf declares an unknown kind or contains non-finite
  values
- **THEN** the card still renders, the offending kind or values are dropped,
  and a diagnostic is recorded for the plugin's debug surface

### Requirement: List and board items can be tapped

An item in a `list` or `board` card SHALL accept an optional link or Shortcut
declaration, making that row a tap target: tapping it opens the link or runs
the named Shortcut. An item without a declaration SHALL render as today,
inert. Arbitrary shell commands SHALL NOT be expressible from a widget item,
matching the widget action contract.

#### Scenario: A list row opens its link

- **WHEN** a `list` card item declares a link and the user taps that row
- **THEN** the link opens

#### Scenario: A board row runs its Shortcut

- **WHEN** a `board` card item declares a Shortcut name and the user taps that
  row
- **THEN** that Shortcut runs

#### Scenario: Shell stays unexpressible

- **WHEN** a plugin attempts to declare a shell command on a widget item
- **THEN** no shell runs from the widget, and the declaration is rejected with
  a diagnostic

### Requirement: Menu vocabulary carries a widget disposition

Every display graphic the menu surface can draw and every action kind the menu
can dispatch SHALL have a recorded widget disposition: supported on the widget,
or excluded with a stated reason. Introducing a new menu display graphic or
action kind without recording its disposition SHALL fail the build, and the
recorded dispositions SHALL be published in a human-readable parity ledger.

#### Scenario: A new menu graphic demands an answer

- **WHEN** a new display-graphic kind is added to the menu vocabulary and no
  widget disposition is recorded for it
- **THEN** the build fails until one is recorded

#### Scenario: Deliberate exclusions are legible

- **WHEN** a vocabulary item is excluded from the widget (such as shell
  actions or live sliders)
- **THEN** the parity ledger states the exclusion and its reason

### Requirement: New vocabulary reaches every authoring format

The chart leaf and item tap targets SHALL be expressible in every published
SDK and the JSON card schema, with identical semantics, covered by the shared
fixtures so the formats cannot diverge silently.

#### Scenario: SDKs express the new vocabulary

- **WHEN** the same card is authored with each published SDK using a chart leaf
  and tappable items
- **THEN** each SDK emits the same card payload
