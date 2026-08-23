## Purpose

Guarantees that every way Vee shows a plugin's menu — the menu-bar dropdown, a
detached window, a transient panel — describes the same menu. One resolved
description of the plugin's output is the source of truth for all of them, so
two presentations cannot disagree about which rows exist, what a row means, or
what activating it does.

## ADDED Requirements

### Requirement: Presentations agree on which rows exist

Every presentation of a plugin's menu SHALL show the same set of rows, in the
same order, derived from the same output. A row visible in one presentation
SHALL be visible in every other, and a row omitted from one SHALL be omitted
from all.

Rows a plugin marks as menu-bar-only remain excluded from every dropdown
presentation, and section headers and separators SHALL appear where the plugin
placed them, without a presentation inserting, reordering, or repairing
structural elements the others do not.

#### Scenario: The same rows in every presentation

- **WHEN** a plugin's menu is shown in the menu bar and the same plugin's menu is
  shown in a window or panel
- **THEN** both present the same rows in the same order

#### Scenario: A row excluded from the dropdown

- **WHEN** a plugin emits a row marked as menu-bar-only
- **THEN** no dropdown presentation shows it

#### Scenario: Structural elements are not invented

- **WHEN** a plugin emits section headers and separators
- **THEN** every presentation places them exactly where the plugin placed them
- **AND** none adds, removes, or reorders them relative to the others

### Requirement: Presentations agree on whether a row acts

Whether activating a row does anything SHALL be decided once and hold in every
presentation. A row that is inert in the menu bar SHALL be inert everywhere, and
a row that acts in one presentation SHALL act in all of them.

A row that carries both nested children and its own command SHALL be treated as
inert on activation in every presentation, matching the menu bar's behavior of
opening the children instead of running the command. Such a row remains visible
and its children remain reachable.

#### Scenario: An inert row stays inert

- **WHEN** a row carries no command, or is marked disabled
- **THEN** activating it in any presentation runs nothing

#### Scenario: Children win over a command

- **WHEN** a row carries both nested children and a command
- **THEN** activating it runs nothing in any presentation
- **AND** its children are still reachable in every presentation

#### Scenario: An actionable row acts identically

- **WHEN** the user activates a row carrying a link, shell command, Shortcut,
  refresh request, web view, or control
- **THEN** the same action runs regardless of which presentation it was
  activated from

### Requirement: Presentations agree on a row's appearance

A row's rendered text, declared icon, checked state, tooltip, and inline graphic
SHALL be decided once for that row and applied by every presentation.

Where a row declares more than one display graphic — a progress gauge,
sparkline, or chart — the one shown SHALL be chosen by a single rule, so no
presentation advertises a different graphic than another. Text styling — colors,
ANSI runs, Markdown, inline symbols, truncation, and badges — SHALL be resolved
identically for all presentations.

A live control (`toggle=`/`slider=`) is not a display graphic. Whether it is
drawn inline is a property of the presentation: a presentation that can host a
live control MAY draw it in place of the row's display graphic, and one that
cannot SHALL draw the display graphic and offer the control on activation.
Either way the control remains what the row acts on.

#### Scenario: One display-graphic decision

- **WHEN** a row declares more than one of a progress gauge, sparkline, or chart
- **THEN** every presentation shows the same one

#### Scenario: A live control is presented per surface

- **WHEN** a row declares a control alongside a display graphic
- **THEN** a presentation that can host the control inline draws the control
- **AND** a presentation that cannot draws the display graphic and opens the
  control on activation
- **AND** activating the row acts on the control in both

#### Scenario: Styling does not diverge

- **WHEN** a row declares text color, ANSI styling, Markdown, inline symbols,
  truncation, or a badge
- **THEN** every presentation renders that row's text the same way

#### Scenario: State markers agree

- **WHEN** a row is marked checked or declares a tooltip or icon
- **THEN** every presentation reflects it

### Requirement: Presentation-only mechanics stay in their presentation

Behavior that only has meaning in one presentation SHALL NOT be part of the
shared description, and its absence elsewhere SHALL NOT change which rows exist
or what they do.

A presentation MAY differ from another in how it unfolds nesting, in its chrome,
and in the keyboard mechanics available to it. It SHALL NOT differ in row
identity, ordering, actionability, or effect.

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
