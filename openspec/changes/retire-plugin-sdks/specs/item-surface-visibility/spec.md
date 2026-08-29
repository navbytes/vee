# item-surface-visibility Specification (delta)

## REMOVED Requirements

### Requirement: Every authoring format expresses targeting identically

**Reason**: The published SDKs are retired; the authoring formats are the
line-based format and the JSON output format. Replaced by "Both authoring
formats express targeting identically".

## ADDED Requirements

### Requirement: Both authoring formats express targeting identically

The `visibleOn` and `searchable` declarations SHALL be expressible in the
line-based format and the JSON output format, with identical semantics, and
SHALL be covered by the published schema and the parser-conformance fixtures
so the formats cannot diverge silently.

#### Scenario: JSON and line format agree

- **WHEN** the same menu is authored in the JSON output format and by hand in
  the line format using the same targeting declarations
- **THEN** every surface renders the two identically
