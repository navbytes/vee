# item-surface-visibility Specification

## Purpose
Lets a plugin target individual menu rows at specific surfaces and keep
specific rows out of search's reach, with one inheritance rule, defined
interplay with alternates and structure, and identical semantics in every
authoring format.

## Requirements

### Requirement: A row can be targeted at specific surfaces

A menu item SHALL accept a `visibleOn` declaration listing the surfaces the row
exists on, drawn from: `menu` (the menu-bar dropdown), `search` (the transient
panel), `window` (a detached window), and `cli` (terminal presentations). A row
without the declaration SHALL exist on every surface. A surface not listed
SHALL omit the row entirely — it is not shown, not matched by that surface's
filtering, and not activatable there.

`widget` SHALL NOT be an accepted value: menu rows do not feed the widget
surface, which is targeted at plugin level. An unrecognized value SHALL produce
a parse diagnostic and be ignored, and a declaration whose values are all
unrecognized SHALL leave the row visible everywhere rather than hiding it.

#### Scenario: A row absent from one surface

- **WHEN** a row declares `visibleOn` without `search`
- **THEN** the transient panel never shows or matches it
- **AND** the dropdown, a detached window, and terminal presentations still
  show it

#### Scenario: No declaration means everywhere

- **WHEN** a row declares no `visibleOn`
- **THEN** every surface shows it as today

#### Scenario: An unknown surface value degrades safely

- **WHEN** a row declares a `visibleOn` value the parser does not recognize
- **THEN** a diagnostic is recorded for the plugin's debug surface
- **AND** the unknown value is ignored rather than failing the parse or hiding
  the row

### Requirement: A row can be kept out of query reach

A menu item SHALL accept a `searchable=false` declaration. Such a row SHALL
never be surfaced by a filter query — in the transient panel, in a detached
window's filter, or in terminal search — but SHALL remain visible and
activatable wherever its surface's listing is idle (no query active).

#### Scenario: Unmatchable but browsable

- **WHEN** a row declares `searchable=false` and the user types a query that
  would otherwise match it
- **THEN** no filtering presentation includes it in the results
- **AND** with no query active, the row is shown and activatable as normal

#### Scenario: Destructive action out of fuzzy reach

- **WHEN** a plugin marks a destructive row `searchable=false`
- **THEN** typing plus Return can never land on that row
- **AND** the user can still reach it by browsing to it deliberately

### Requirement: Visibility inherits by intersection

A row's effective visibility and searchability SHALL be the intersection of its
own declaration and every ancestor's: a descendant can narrow where it appears,
and SHALL NOT resurrect itself on a surface an ancestor is hidden from. A row
hidden on a surface SHALL take its entire subtree with it on that surface.

An `alternate` row SHALL inherit from its primary exactly as a child inherits
from a parent: a primary hidden on a surface hides the pair there, and the
alternate MAY narrow further — including `searchable=false`, in which case
filtering surfaces only the primary while the idle modifier swap still shows
the alternate.

#### Scenario: A hidden parent hides its subtree

- **WHEN** a row declaring children is targeted away from a surface
- **THEN** that surface shows neither the row nor any of its descendants

#### Scenario: A child cannot resurrect itself

- **WHEN** a child declares `visibleOn` including a surface its parent is
  hidden from
- **THEN** the child remains hidden on that surface

#### Scenario: An alternate narrows without breaking the pair

- **WHEN** a primary is visible on a surface and its alternate declares
  `searchable=false`
- **THEN** the idle presentation still swaps to the alternate under the
  modifier
- **AND** filter queries surface only the primary

### Requirement: Hiding leaves no structural debris

When targeting hides rows on a surface, that surface SHALL NOT render the holes:
separators left adjacent to each other, or leading or trailing in a listing,
SHALL be coalesced, and a section header whose every following row is hidden
SHALL be dropped with them. The same declared set SHALL produce the same repair
on every surface, so two surfaces given identical declarations still agree.

#### Scenario: Separators collapse around hidden rows

- **WHEN** hiding removes every row between two separators on a surface
- **THEN** that surface draws one separator, not two

#### Scenario: An emptied section disappears

- **WHEN** every row following a section header is hidden on a surface
- **THEN** that surface drops the header as well

### Requirement: The legacy dropdown flag remains honored

The existing `dropdown=false` declaration SHALL keep its meaning as a
compatibility alias, and its subtree semantics SHALL be the same as targeting:
a `dropdown=false` row and its descendants are absent from every dropdown
presentation, including terminal search. A row declaring both `dropdown` and
`visibleOn` SHALL follow `visibleOn`, and the conflict SHALL produce a
diagnostic.

#### Scenario: Existing plugins keep working

- **WHEN** a plugin declares `dropdown=false` on a row and nothing else
- **THEN** the row and its subtree are absent from the dropdown, panel, window,
  and terminal presentations exactly as a `visibleOn` targeting away from them
  would be

#### Scenario: Conflicting declarations resolve loudly

- **WHEN** a row declares both `dropdown=false` and a `visibleOn` list
- **THEN** the `visibleOn` list wins
- **AND** a diagnostic records the conflict

### Requirement: Both authoring formats express targeting identically

The `visibleOn` and `searchable` declarations SHALL be expressible in the
line-based format and the JSON output format, with identical semantics, and
SHALL be covered by the published schema and the parser-conformance fixtures
so the formats cannot diverge silently.

#### Scenario: JSON and line format agree

- **WHEN** the same menu is authored in the JSON output format and by hand in
  the line format using the same targeting declarations
- **THEN** every surface renders the two identically
