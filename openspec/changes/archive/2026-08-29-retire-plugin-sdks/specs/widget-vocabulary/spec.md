# widget-vocabulary Specification (delta)

## REMOVED Requirements

### Requirement: New vocabulary reaches every authoring format

**Reason**: The published SDKs are retired; the widget vocabulary is authored
through the JSON card schema. Replaced by "New vocabulary reaches the
published schema".

## ADDED Requirements

### Requirement: New vocabulary reaches the published schema

The chart leaf and item tap targets SHALL be expressible in the JSON card
schema with semantics identical to the parser's, covered by the
parser-conformance fixtures so schema and parser cannot diverge silently.

#### Scenario: Schema and parser agree

- **WHEN** the same card is authored against the published card schema using
  a chart leaf and tappable items
- **THEN** the parser accepts it and the widget renders the declared payload
