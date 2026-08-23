## MODIFIED Requirements

### Requirement: The machine-readable forms are generated and verified

The Markdown mirrors, the index, and the full-text document SHALL be produced by
the same build that produces the published pages, never maintained by hand.

The build MUST fail when any of them cannot be produced, and MUST run in
continuous integration on every change to the documentation. Because the
published output is not stored in version control, these forms cannot be stale
with respect to their sources: the staleness this requirement previously guarded
with a separate verification mode is now prevented by construction, and the
guarantee is unchanged.

#### Scenario: Content changes without the machine-readable forms being regenerated

- **WHEN** a guide's content changes
- **THEN** the machine-readable forms published alongside it reflect that change,
  because they are produced by the build rather than committed
- **AND** there is no separate regeneration step that can be forgotten

#### Scenario: A newly published page

- **WHEN** a page is added to the published set
- **THEN** it appears in the index, in the full-text document, and as a Markdown
  mirror, without any of them being edited by hand

#### Scenario: A page cannot produce its machine-readable form

- **WHEN** a page's Markdown mirror, index entry, or full-text contribution
  cannot be produced
- **THEN** the build fails and nothing is published

#### Scenario: Everything is current

- **WHEN** the published pages and every machine-readable form agree
- **THEN** the build succeeds and reports nothing to attend to
