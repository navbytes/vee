# plugin-docs-integrity Specification

## Purpose
Keeps the plugin format's documented surface honest by making it machine-checkable:
the parameters and payload shapes a plugin author reads about are verified against
what Vee actually accepts, so the reference cannot silently fall behind the parser.

## Requirements

### Requirement: The documented parameter set matches the implementation

The set of menu-line parameters named in the published authoring reference SHALL be
verified against the set the parser recognises and the set the linter treats as known.
The verification MUST run in continuous integration and MUST fail when any of the three
sets disagree, reporting which parameters are missing from which set.

A parameter that is deliberately undocumented MUST be recorded as such in a single
declared exception list, so that an intentional omission is distinguishable from an
oversight and is visible in review.

#### Scenario: A new parameter ships without documentation

- **WHEN** the parser gains a menu-line parameter that the published reference does not
  name, and it is not in the declared exception list
- **THEN** the verification fails
- **AND** the failure names the parameter and the surface that is missing it

#### Scenario: The linter falls behind the parser

- **WHEN** the parser recognises a parameter that the linter does not
- **THEN** the verification fails
- **AND** the failure names the parameter and the surface that is missing it

#### Scenario: A documented parameter does not exist

- **WHEN** the published reference names a parameter the parser does not recognise
- **THEN** the verification fails, rather than leaving readers with a parameter that
  is silently ignored at runtime

#### Scenario: All three surfaces agree

- **WHEN** the parser, the linter, and the published reference name the same set of
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
the same generation step that produces the published pages, never maintained by
hand. That step MUST offer a verification mode that fails when any of them is
absent or does not match what the current content would produce, and that mode
MUST run in continuous integration.

#### Scenario: Content changes without the machine-readable forms being regenerated

- **WHEN** a guide's content changes and the generation step has not been re-run
- **THEN** the verification mode fails, naming what is out of date

#### Scenario: A newly published page

- **WHEN** a page is added to the published set
- **THEN** it appears in the index, in the full-text document, and as a Markdown
  mirror, without any of them being edited by hand

#### Scenario: Everything is current

- **WHEN** the published pages and every machine-readable form agree
- **THEN** the verification mode passes and reports nothing to attend to
