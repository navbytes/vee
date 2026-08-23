## MODIFIED Requirements

### Requirement: The window keeps the panel's search

A window SHALL offer a filter over its plugin's rows, and the transient panel
SHALL offer the same one, so choosing either presentation gives up nothing the
other provides.

The filter SHALL preserve the plugin's structure rather than replace it. A query
narrows the menu to the rows that match and the ancestors needed to reach them,
and those ancestors SHALL be revealed automatically so every match is visible
without further interaction. Matching SHALL consider a row's own text and the
titles of its ancestors, so naming a group surfaces what is inside it.

Because the filtered result remains a structure, rows SHALL keep the order the
plugin authored. The filter SHALL NOT reorder rows by how well they match.

#### Scenario: Searching within a window

- **WHEN** the user types a query in an open window
- **THEN** only rows matching the query, and the ancestors needed to reach them,
  are shown
- **AND** those ancestors are revealed automatically

#### Scenario: Matching by ancestor name

- **WHEN** the user types the title of a group
- **THEN** the rows inside that group are surfaced

#### Scenario: Authored order is preserved

- **WHEN** a query matches several rows across different parts of the menu
- **THEN** they appear in the order the plugin emitted them
- **AND** they are not reordered by match quality

#### Scenario: Empty query shows everything

- **WHEN** a window's query is empty
- **THEN** the plugin's full menu structure is shown, including section headers
  and separators

#### Scenario: Search does not freeze a window

- **WHEN** a refresh arrives while a query is active in a window
- **THEN** the window reflects the new output, filtered by the same query

### Requirement: Window content fidelity

A window SHALL reproduce the content of its plugin's dropdown, including nested
submenus, separators, section headers, per-row text styling and colors, declared
icons, disabled and checked state, tooltips, and every rich row Vee renders:
progress gauges, sparklines, share charts, toggles, and sliders.

Nesting SHALL be presented as structure the user can open and close in place,
not as a flattened list annotated with the path to each row. More than one
branch MAY be open at a time, so values in different parts of the menu can be
watched together.

A window SHALL NOT reproduce mechanics that only have meaning inside an open
menu. An `⌥` alternate SHALL be presented as an ordinary row of its own rather
than as a modifier-hold state, so its content is visible and activatable instead
of unreachable. Per-row `key=` equivalents SHALL NOT be bound, since they are
scoped to an open menu.

#### Scenario: Rich rows render

- **WHEN** a plugin emits rows carrying progress gauges, sparklines, share
  charts, toggles, or sliders
- **THEN** the window renders each with the same visual treatment the dropdown
  gives it

#### Scenario: Nested submenus

- **WHEN** a plugin emits nested submenu levels
- **THEN** the window presents each level as structure the user can open in place
- **AND** every level is reachable

#### Scenario: More than one branch open

- **WHEN** the user opens two separate nested groups
- **THEN** both remain open at the same time
- **AND** the contents of both are visible together

#### Scenario: A row's ancestors are visible, not annotated

- **WHEN** a nested row is shown
- **THEN** its position is conveyed by where it sits in the structure
- **AND** it does not carry a textual path to itself

#### Scenario: Alternate rows appear as ordinary rows

- **WHEN** a plugin emits a row with an alternate
- **THEN** the window renders both the primary row and its alternate as
  ordinary rows
- **AND** neither requires holding a modifier to see

#### Scenario: Key equivalents are not bound

- **WHEN** a plugin emits a row declaring a `key=` equivalent
- **THEN** the window renders the row normally
- **AND** pressing that combination while the window is focused does not
  activate it

#### Scenario: A row excluded from the dropdown

- **WHEN** a plugin emits a row marked as menu-bar-only
- **THEN** the window omits it, exactly as the dropdown does

## ADDED Requirements

### Requirement: Open branches survive a refresh

A window updates on its plugin's own cadence, and that update SHALL NOT discard
what the user has opened. Branches the user opened SHALL remain open across
refreshes for as long as the plugin still emits them.

A branch that is no longer present after a refresh SHALL simply not be shown; it
MUST NOT cause unrelated branches to close. Where a branch cannot be recognised
across a refresh, the window SHALL degrade by closing only that branch.

#### Scenario: A refresh keeps branches open

- **WHEN** the user opens a nested group and the plugin refreshes with new
  values
- **THEN** the group is still open
- **AND** the new values are shown inside it

#### Scenario: A vanished branch closes alone

- **WHEN** a plugin stops emitting a group the user had opened
- **THEN** that group is no longer shown
- **AND** every other open group remains open

#### Scenario: Rapid refreshes do not fight the user

- **WHEN** a plugin refreshes repeatedly while the user has branches open
- **THEN** the branches stay open across every refresh

### Requirement: A window carries its plugin's controls

A window SHALL offer the same plugin controls its dropdown offers — refreshing
the plugin, opening its settings, showing its About information, revealing it in
the Finder, editing it, and opening its debug view — so a plugin can be operated
from the window it is being watched in.

These controls are chrome, not plugin output. They SHALL NOT appear among the
plugin's rows, and the filter SHALL NOT match them.

#### Scenario: Refreshing from a window

- **WHEN** the user invokes refresh from an open window
- **THEN** the plugin re-runs
- **AND** the window shows the new output

#### Scenario: Controls are excluded from the filter

- **WHEN** the user types a query that would match a control's name
- **THEN** no control appears among the filtered rows

#### Scenario: Controls are not plugin rows

- **WHEN** a window shows a plugin's menu
- **THEN** the controls are presented apart from the plugin's own rows
