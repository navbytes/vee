# widget-vocabulary Specification (delta)

## MODIFIED Requirements

### Requirement: New vocabulary reaches every authoring format

The chart leaf and item tap targets SHALL be expressible in the JSON card
schema and the line-based format where applicable, with identical semantics,
covered by the parser-conformance fixtures so the formats cannot diverge
silently.

#### Scenario: Schema and parser agree

- **WHEN** the same card is authored against the published card schema using
  a chart leaf and tappable items
- **THEN** the parser accepts it and the widget renders the declared payload
