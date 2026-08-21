## ADDED Requirements

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
