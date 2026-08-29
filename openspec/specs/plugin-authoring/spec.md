# plugin-authoring Specification

## Purpose
TBD - created by archiving change retire-plugin-sdks. Update Purpose after archive.

## Requirements

### Requirement: A plugin is a dependency-free executable

A Vee plugin SHALL be any executable that prints the text or JSON output
format to stdout, runnable identically under Vee, under a bare interpreter
(`python3 plugin.py`, `node plugin.ts`), and after a plain file copy — with no
library Vee must provision, inject, or resolve. The app's runtime SHALL NOT
modify a plugin's import environment.

#### Scenario: The same file runs everywhere

- **WHEN** a plugin scaffolded by `vee new` is run by Vee and by its bare
  interpreter in a terminal
- **THEN** both produce the same output with no Vee-supplied environment

### Requirement: Typed authoring without a dependency

`vee new` scaffolds SHALL carry their type vocabulary inline (a TypeScript
`interface` block, a Python `TypedDict` block) over the recommended JSON
output format, so editors provide autocomplete and type errors with nothing to
install. A drift guard SHALL fail when a template's type block disagrees with
the published JSON Schema.

#### Scenario: Template types cannot rot

- **WHEN** the JSON output schema gains or renames a property used by a
  template's type block
- **THEN** the template drift test fails until the template agrees

### Requirement: Retired SDK imports fail loudly, not mysteriously

`vee lint` SHALL detect imports of the retired SDKs (`vee` in Python,
`@navbytes/vee` or a `./vee.*` relative import in TypeScript/JavaScript). An
import with no sibling SDK file SHALL be an error naming the migration guide;
an import satisfied by a sibling copy SHALL be a warning that the copy is
frozen. Lint SHALL NOT rewrite plugin source.

#### Scenario: A stranded SDK import

- **WHEN** a plugin imports the retired SDK and no sibling SDK file exists
  beside it
- **THEN** lint reports an error explaining the SDK is retired and how to
  port

#### Scenario: A vendored sibling keeps working

- **WHEN** a plugin imports the SDK and a sibling `vee.py`/`vee.ts` exists
- **THEN** the plugin runs by plain language rules and lint reports only a
  frozen-copy warning

### Requirement: The format is documented for machine authors

The repository SHALL publish an LLM-facing authoring surface — `AGENTS.md`
and `llms.txt` carrying the parameter reference, the JSON Schema location,
and complete example plugins — kept alongside the human docs.

#### Scenario: An assistant writes a plugin from the published surface

- **WHEN** an AI assistant is pointed at the repository or docs site
- **THEN** the authoring reference it needs (format, schema, examples) is
  discoverable without reading source code
