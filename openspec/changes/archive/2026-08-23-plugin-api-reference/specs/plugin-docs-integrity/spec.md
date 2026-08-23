## ADDED Requirements

### Requirement: The parameter reference is generated from machine-readable data

The published parameter reference SHALL be generated from a single
machine-readable record of the plugin format's parameters, never written by
hand. Each record MUST carry the parameter's key and any aliases, the shape of
the value it accepts, its default, the group it belongs to, what it applies to,
and where it is explained at length.

That record MUST itself be published, so a client can obtain the parameter
surface as data rather than by parsing a rendered table.

The generation step MUST offer a verification mode that fails when a published
table does not match what the record would currently produce, and that mode MUST
run in continuous integration.

#### Scenario: A parameter's documented default changes

- **WHEN** a parameter's record is edited and the published tables are not
  regenerated
- **THEN** the verification mode fails, naming the table that is out of date

#### Scenario: A client reads the parameter surface as data

- **WHEN** a client retrieves the published parameter record
- **THEN** every documented parameter appears, with its accepted values, its
  default, and the group it belongs to
- **AND** no rendered-table parsing is required to obtain them

#### Scenario: The published table is hand-edited

- **WHEN** a generated table is edited directly instead of its source record
- **THEN** the verification mode fails rather than accepting the edit

### Requirement: Documented constants are verified against the implementation

Where the documentation states a numeric limit, default, or capacity that the
implementation defines, that value SHALL be recorded once and verified against
the declaration it mirrors. The verification MUST run in continuous integration
and MUST fail when the two disagree, naming the symbol, both values, and the
file each was read from.

The verified set MUST cover every such value the documentation states, and MUST
NOT be required to cover values the documentation does not state.

#### Scenario: An implementation limit changes without the docs following

- **WHEN** a constant the documentation states is changed in the implementation
- **THEN** the verification fails, naming the symbol and both values

#### Scenario: A newly documented limit

- **WHEN** the documentation begins stating a limit it did not state before
- **THEN** that limit is recorded with the symbol it mirrors and verified by the
  same check

### Requirement: Every chart surface is indexed in one place

The documentation SHALL publish a single page that lists every chart the plugin
format can produce. For each chart it MUST give the spelling on every entry path
that can produce it, the values it accepts, which options apply to it, the
limits it is subject to, and its behavior when a reader clicks it.

That index MUST be generated from the same record as the parameter reference, so
a chart cannot be added to the format and omitted from the index.

#### Scenario: A reader asks what charts exist

- **WHEN** a reader opens the chart index
- **THEN** every chart the format supports is listed, with the options that
  apply to each
- **AND** no chart requires knowing its name in advance to find it

#### Scenario: A chart is spelled differently on different entry paths

- **WHEN** a chart can be produced from more than one entry path
- **THEN** the index gives its spelling on each of them

#### Scenario: An option applies to only some charts

- **WHEN** an option applies to a subset of the charts
- **THEN** the index states which charts it applies to, rather than listing it
  as generally available

### Requirement: Documented links resolve

Every repository-relative and same-site link in the documentation SHALL resolve
to something that exists. The verification MUST run in continuous integration
and MUST fail when a link's target is absent, naming the link and the file that
contains it.

Links to external hosts are outside this requirement.

#### Scenario: A file is moved or renamed

- **WHEN** a file the documentation links to is moved and the link is not
  updated
- **THEN** the verification fails, naming the link and its source file

#### Scenario: A link is added to a page

- **WHEN** a new repository-relative link is added
- **THEN** it is checked by the same verification without that check needing to
  be told about it

## MODIFIED Requirements

### Requirement: The documented parameter set matches the implementation

The set of menu-line parameters named in the published parameter record SHALL be
verified against the set the parser recognises and the set the linter treats as
known. The verification MUST run in continuous integration and MUST fail when any
of the three sets disagree, reporting which parameters are missing from which set.

A parameter that is deliberately undocumented MUST be recorded as such in a single
declared exception list, so that an intentional omission is distinguishable from an
oversight and is visible in review.

The documentation surface of this verification MUST be the machine-readable
record, not a rendered table, so that the check reads structured data rather than
recovering it from prose.

#### Scenario: A new parameter ships without documentation

- **WHEN** the parser gains a menu-line parameter that the published record does not
  name, and it is not in the declared exception list
- **THEN** the verification fails
- **AND** the failure names the parameter and the surface that is missing it

#### Scenario: The linter falls behind the parser

- **WHEN** the parser recognises a parameter that the linter does not
- **THEN** the verification fails
- **AND** the failure names the parameter and the surface that is missing it

#### Scenario: A documented parameter does not exist

- **WHEN** the published record names a parameter the parser does not recognise
- **THEN** the verification fails, rather than leaving readers with a parameter that
  is silently ignored at runtime

#### Scenario: All three surfaces agree

- **WHEN** the parser, the linter, and the published record name the same set of
  parameters, allowing for declared exceptions
- **THEN** the verification passes and produces no output requiring attention
