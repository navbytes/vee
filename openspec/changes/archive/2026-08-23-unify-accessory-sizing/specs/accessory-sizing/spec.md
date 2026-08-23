## Purpose

Gives a plugin author one way to size whatever a menu row draws beside its
label — a gauge, a sparkline, a chart, or a live control. A row can only ever
carry one such accessory, so sizing it should not require knowing which kind it
turned out to be.

## ADDED Requirements

### Requirement: One parameter pair sizes any accessory

A row's inline accessory SHALL be sized by a single width parameter and a single
height parameter, whichever accessory the row carries.

The parameters SHALL apply to the accessory the row actually resolves to. A row
carrying no accessory SHALL ignore them rather than fail.

#### Scenario: Sizing a gauge

- **WHEN** a plugin declares a progress gauge and an accessory width
- **THEN** the gauge is drawn at that width

#### Scenario: Sizing a sparkline

- **WHEN** a plugin declares a sparkline and an accessory width and height
- **THEN** the sparkline is drawn at that size

#### Scenario: Sizing a chart

- **WHEN** a plugin declares a stacked bar and an accessory width
- **THEN** the bar is drawn at that width

#### Scenario: Sizing a control

- **WHEN** a plugin declares a slider and an accessory width
- **THEN** the slider is drawn at that width

#### Scenario: Sizing a row with no accessory

- **WHEN** a plugin declares an accessory width on a row carrying no accessory
- **THEN** the row renders normally and nothing fails

### Requirement: Each accessory keeps its own default size

Where a row declares no size, its accessory SHALL use the default for that kind
of accessory. A gauge, a sparkline, a circular chart and a stacked bar have
different natural proportions, so the shared parameter overrides a default
rather than replacing the idea of one.

Defaults SHALL be identical on every surface that draws the accessory.

#### Scenario: An undeclared size falls back per accessory

- **WHEN** a plugin declares an accessory but no size
- **THEN** that accessory is drawn at its own default size

#### Scenario: Defaults do not differ by surface

- **WHEN** the same accessory is drawn in the menu bar and in a window
- **THEN** both use the same default size

### Requirement: An accessory can stretch to the row's width

A width SHALL accept a value meaning "stretch to the row's leftover width"
rather than a fixed measurement, and every accessory that can meaningfully fill
a width SHALL honour it identically.

A circular chart SHALL refuse it with a diagnostic, since a circle can only fill
a width by growing the row's height with it. Refusal SHALL be reported once, by
the format, rather than left to each renderer.

#### Scenario: Stretching a gauge

- **WHEN** a plugin asks for a full-width gauge
- **THEN** the gauge takes the row's width less its label

#### Scenario: Stretching a stacked bar

- **WHEN** a plugin asks for a full-width stacked bar
- **THEN** the bar takes the same width the gauge would have taken

#### Scenario: A circular chart refuses to stretch

- **WHEN** a plugin asks for a full-width pie or donut
- **THEN** the chart is drawn at its declared or default size
- **AND** a diagnostic explains that full width applies to a stacked bar

#### Scenario: A row too narrow to stretch into

- **WHEN** a full-width accessory sits in a row narrower than its default size
- **THEN** it falls back to that default rather than collapsing to nothing

### Requirement: The per-accessory parameters remain accepted

The parameter names each accessory used before this SHALL keep working and
SHALL keep their previous effect, so no published plugin changes what it draws.

Using one SHALL produce a diagnostic naming the parameter that replaces it. A
row that declares both SHALL prefer the new parameter, so a plugin can migrate
without a flag day.

#### Scenario: An old parameter still sizes its accessory

- **WHEN** a plugin uses the parameter its accessory previously required
- **THEN** the accessory is drawn at that size

#### Scenario: An old parameter is reported as deprecated

- **WHEN** a plugin uses one of the previous parameters
- **THEN** a diagnostic names the parameter that replaces it
- **AND** the diagnostic does not change what is drawn

#### Scenario: The new parameter wins over an old one

- **WHEN** a row declares both the new parameter and the one it replaces
- **THEN** the new parameter's value is used

### Requirement: Structured output uses the same single pair

A plugin emitting structured output SHALL size an accessory with one width and
one height field, matching the text format's single pair.

The previous per-accessory fields SHALL keep working, with the same deprecation
reporting as the text format.

#### Scenario: Sizing from structured output

- **WHEN** a plugin emits an accessory with a width field in structured output
- **THEN** it is drawn at that width

#### Scenario: A previous structured field still works

- **WHEN** a plugin emits one of the previous per-accessory size fields
- **THEN** the accessory is drawn at that size
- **AND** a diagnostic names the field that replaces it
