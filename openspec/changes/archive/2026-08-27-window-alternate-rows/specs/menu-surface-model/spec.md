# menu-surface-model Delta — window-alternate-rows

## MODIFIED Requirements

### Requirement: Presentation-only mechanics stay in their presentation

Behavior that only has meaning in one presentation SHALL NOT be part of the
shared description, and its absence elsewhere SHALL NOT change which rows exist
or what they do.

A presentation MAY differ from another in how it unfolds nesting, in its chrome,
and in the keyboard mechanics available to it. It SHALL NOT differ in row
identity, ordering, actionability, or effect.

Alternates are no longer optional mechanics: every presentation with live
access to modifier state — the menu-bar dropdown, the transient panel, and a
detached window — SHALL show only the primary of an alternate pair until the ⌥
modifier is held, and SHALL show the alternate in its place while it is held.
The swap is in place: row order does not change, and a keyboard selection
sitting on the row stays on it through the swap. A presentation without live
modifier state (a terminal) SHALL present the alternate as an ordinary row
after its primary instead, so it remains discoverable and activatable. While a
filter query is active, the modifier SHALL be inert and each half of the pair
SHALL be an independent match candidate.

#### Scenario: Nesting may unfold differently

- **WHEN** the menu bar presents nested children as a submenu and a window
  presents the same children inline
- **THEN** both expose the same children, in the same order, with the same
  actions

#### Scenario: Menu-scoped shortcuts do not travel

- **WHEN** a plugin declares a per-row key equivalent
- **THEN** the presentation that supports menu-scoped shortcuts binds it
- **AND** a presentation that does not still shows the row and keeps it
  activatable by other means

#### Scenario: An alternate replaces its row under the modifier

- **WHEN** a plugin declares a row with an alternate and the row is shown in
  the menu-bar dropdown, the transient panel, or a detached window with no
  filter query active
- **THEN** only the primary row is shown until ⌥ is held
- **AND** holding ⌥ shows the alternate in its place
- **AND** releasing ⌥ restores the primary

#### Scenario: An alternate of a row that declares a key equivalent

- **WHEN** the row carrying the alternate also declares a key equivalent
- **THEN** the alternate still replaces it under the modifier
- **AND** the two are never shown at the same time

#### Scenario: Selection survives the swap

- **WHEN** the keyboard selection sits on a row with an alternate and ⌥ is
  pressed or released
- **THEN** the selection remains on that row's position through the swap

#### Scenario: Filtering surfaces both halves

- **WHEN** a filter query is active in a presentation showing a row that
  declares an alternate
- **THEN** the primary and the alternate each appear exactly when they match
  the query
- **AND** holding or releasing ⌥ does not change the result list

#### Scenario: A terminal shows the alternate as a row

- **WHEN** a plugin's menu is presented where no live modifier state exists
- **THEN** the alternate appears as an ordinary row after its primary
