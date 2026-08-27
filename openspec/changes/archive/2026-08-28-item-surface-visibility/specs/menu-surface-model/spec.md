# menu-surface-model Delta — item-surface-visibility

## MODIFIED Requirements

### Requirement: Presentations agree on which rows exist

Every presentation of a plugin's menu SHALL show the same set of rows, in the
same order, derived from the same output — except where the plugin explicitly
targets a row away from a surface (see `item-surface-visibility`). For every
row without such a declaration, a row visible in one presentation SHALL be
visible in every other, and a row omitted from one SHALL be omitted from all.

Rows a plugin marks as menu-bar-only remain excluded from every dropdown
presentation, and section headers and separators SHALL appear where the plugin
placed them, without a presentation inserting, reordering, or repairing
structural elements the others do not. Repair triggered by declared hiding is
the one exception, and it SHALL follow a single rule shared by all surfaces, so
two surfaces given the same declarations still agree.

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

#### Scenario: Divergence only by declaration

- **WHEN** a row is explicitly targeted away from one surface
- **THEN** that surface omits it while the others show it
- **AND** no surface ever omits a row the plugin did not target away from it
