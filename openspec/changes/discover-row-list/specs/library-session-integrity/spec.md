## RENAMED Requirements

- FROM: `### Requirement: Discover card actions remain readable`
- TO: `### Requirement: Discover row actions remain readable`

## MODIFIED Requirements

### Requirement: Discover row actions remain readable
The system SHALL display Installed, Install, Update, and Reinstall labels on one readable line at the Library window's default and minimum supported widths.

#### Scenario: Discover at constrained width
- **WHEN** Discover is shown at the Library window's default or minimum width
- **THEN** each visible row's status and action labels remain untruncated and do not wrap vertically

## ADDED Requirements

### Requirement: Discover presents the catalog as uniform rows
The system SHALL present Discover entries as full-width rows in a grouped list so that a row's height does not depend on whether an entry declares a screenshot, and so that its action controls are never displaced or truncated by other metadata.

#### Scenario: Entries with and without screenshots
- **WHEN** the catalog contains one entry that declares a preview image and one that does not
- **THEN** both render as full-width rows of the same height and neither is vertically offset relative to its neighbors

#### Scenario: Metadata does not displace the actions
- **WHEN** an entry shows its store, author, description, and several status badges
- **THEN** its Install/Update/Reinstall and View source controls remain fully visible and readable on the same row

#### Scenario: Category grouping
- **WHEN** All Categories is selected
- **THEN** entries are grouped under category section headers that name the category and show its entry count

### Requirement: Discover screenshots render at a fixed thumbnail size
The system SHALL render an entry's declared preview image, when present, as a fixed-size thumbnail that fills a fixed frame without changing its row's height, and SHALL allow the user to open it enlarged.

#### Scenario: Opening a thumbnail
- **WHEN** a user clicks an entry's screenshot thumbnail
- **THEN** the image opens enlarged in a dismissible view

#### Scenario: No declared screenshot
- **WHEN** an entry declares no preview image or its image is refused
- **THEN** its row renders with no thumbnail and at the same height as a row that has one
