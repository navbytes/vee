# plugin-docs-integrity Specification

## Purpose
Keeps the plugin format's documented surface honest by making it machine-checkable:
the parameters and payload shapes a plugin author reads about are verified against
what Vee actually accepts, so the reference cannot silently fall behind the parser.

## Requirements

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

### Requirement: The machine-readable payload formats have published schemas

Vee SHALL publish a machine-readable schema for each structured payload a plugin can
print: the widget-card payload and the JSON menu-output format. Each schema MUST be
versioned in step with the version marker its payload already carries, MUST be
retrievable at a stable location, and MUST be usable by a plugin author's editor to
validate a payload while it is being written.

A schema MUST describe every field the corresponding parser reads, including which
fields are optional and what values are accepted, so that the schema is sufficient on
its own to construct a valid payload.

#### Scenario: An author validates a payload while writing it

- **WHEN** a plugin author references the published schema from a JSON payload they are
  authoring
- **THEN** their editor reports unknown fields and invalid values against that schema
- **AND** the reported constraints match what Vee accepts at runtime

#### Scenario: A payload uses a field the parser reads

- **WHEN** the parser reads a field from a structured payload
- **THEN** that field is described in the corresponding published schema

### Requirement: Published schemas are verified against the shipped examples

The published schemas SHALL be validated against the example payloads the project already
ships as golden fixtures. The validation MUST run in continuous integration and MUST fail
when a fixture does not satisfy its schema, so a schema and the implementation that
produced those fixtures cannot diverge.

#### Scenario: A schema drifts from the payloads Vee produces

- **WHEN** a golden fixture payload does not validate against its published schema
- **THEN** the validation fails
- **AND** the failure names the fixture and the constraint it violated

#### Scenario: A new payload example is added

- **WHEN** a new structured-payload fixture is added to the project
- **THEN** it is validated against its schema by the same check, without that check
  needing to be told about the new fixture individually

### Requirement: The documentation is reachable in a machine-readable form

Every published guide page SHALL also be retrievable as its source Markdown, at a
location derivable from the page's own URL, and served with a Markdown content
type. The HTML page MUST declare that alternate form, so a client that has only
the page can discover it without guessing.

The documentation set SHALL additionally publish, at conventional well-known
locations, an index of every page with a one-line description, and a single
document containing the full text of every page. The single document exists so a
client can obtain the complete plugin format in one retrieval rather than by
crawling, and MUST link the published payload schemas alongside the prose.

#### Scenario: A client retrieves a page's source rather than its rendering

- **WHEN** a client derives the Markdown location from a published page's URL
- **THEN** the page's source Markdown is returned, with a Markdown content type
- **AND** it contains the same content as the rendered page, without navigation,
  search, or other page furniture

#### Scenario: A client discovers the alternate form from the page

- **WHEN** a client retrieves a published page and inspects its declared
  alternates
- **THEN** the location of that page's Markdown form is among them

#### Scenario: A client obtains the whole format in one request

- **WHEN** a client retrieves the full-text document
- **THEN** it contains the text of every published guide page
- **AND** it names the locations of the published payload schemas

#### Scenario: A client starts from the index

- **WHEN** a client retrieves the index document
- **THEN** every published guide page appears, each with its location and a
  one-line description of what it covers

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
