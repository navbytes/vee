## ADDED Requirements

### Requirement: Published output is built, not committed

The rendered documentation site SHALL be produced by a build step and MUST NOT be
stored in version control. Only authored sources — the prose, the machine-readable
records it is generated from, and the static assets — belong in the repository.

The build MUST run on every pull request without publishing, so a change that
cannot be built fails before it is merged.

#### Scenario: A contributor edits a page

- **WHEN** a documentation page's source is edited
- **THEN** no rendered output appears in the change
- **AND** the change cannot be stale relative to its source, because no rendered
  output is stored

#### Scenario: A change breaks the build

- **WHEN** a documentation change cannot be built
- **THEN** the pull request fails
- **AND** nothing is published

#### Scenario: A published deploy fails

- **WHEN** a build fails after merge
- **THEN** the previously published site continues to be served

### Requirement: Published locations survive a change of renderer

A location that has been published SHALL continue to resolve after the site is
rebuilt with a different renderer. Where a page's location changes, the previous
location MUST resolve to the new one and MUST declare the new one as canonical.

Indexes the project publishes for machine consumption MUST name the new
locations directly rather than pointing through a redirect.

#### Scenario: A reader follows a link published before the change

- **WHEN** a previously published page location is requested
- **THEN** the reader arrives at that page's current location
- **AND** the current location is declared canonical

#### Scenario: A client reads the published index

- **WHEN** a client retrieves the index of pages
- **THEN** every location it names resolves directly, without redirection

### Requirement: Documentation and marketing surfaces are published together

The site SHALL publish both its documentation and its hand-authored marketing
pages from one origin, under one navigation, sharing one visual system. A change
to how the documentation is rendered MUST NOT alter what the marketing pages
render.

#### Scenario: The documentation renderer changes

- **WHEN** the documentation is rebuilt with a different renderer
- **THEN** the hand-authored pages are published unchanged

#### Scenario: A reader moves between the two

- **WHEN** a reader navigates from a marketing page into the documentation
- **THEN** navigation, typography, and color are continuous across the boundary

### Requirement: The site is legible in both color schemes

Every published page SHALL render legibly under both light and dark color scheme
preferences, including code blocks, tables, and diagrams, and SHALL respect the
reader's declared preference.

#### Scenario: A reader prefers a dark color scheme

- **WHEN** a reader whose system declares a dark color-scheme preference opens
  any published page
- **THEN** the page renders in that scheme
- **AND** every element on it, including code and tables, remains legible
