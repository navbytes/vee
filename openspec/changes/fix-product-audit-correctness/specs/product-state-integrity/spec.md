## Purpose

Ensure Vee's management surfaces reflect durable system state, expose failures honestly, and remain identifiable to assistive technology.

## ADDED Requirements

### Requirement: Variable saves reflect persistence outcomes
The system SHALL show a successful Variables save only when every requested value is persisted, SHALL identify failed fields without revealing their values, and SHALL preserve the edited values for retry after failure.

#### Scenario: A variable cannot be persisted
- **WHEN** one or more variable writes fail
- **THEN** the system keeps the edits, identifies the affected plugin and field, and does not show a successful save

#### Scenario: Retrying a failed save succeeds
- **WHEN** the persistence problem is corrected and the user retries
- **THEN** the system persists the buffered edits and shows success

### Requirement: Installed state follows recoverable deletion
The system SHALL remove a plugin from Installed state only after it is successfully moved to Trash.

#### Scenario: Moving a plugin to Trash fails
- **WHEN** the operating system rejects the Trash operation
- **THEN** the plugin remains visible and active and the system presents an actionable failure

#### Scenario: Moving a plugin to Trash succeeds
- **WHEN** the Trash operation succeeds
- **THEN** the system removes the plugin and its associated running and satellite state

### Requirement: Store controls have specific accessible names
The system SHALL expose Store enable and remove controls with names that identify the affected Store.

#### Scenario: Assistive technology inspects Store controls
- **WHEN** a user navigates an editable Store row
- **THEN** the enable control announces the Store name and current state and the remove control announces the Store name

### Requirement: Launch-at-login controls share actual state
The system SHALL keep every visible launch-at-login control synchronized with the operating system's current registration state.

#### Scenario: Menu command changes launch-at-login
- **WHEN** the user changes launch-at-login from the menu while General settings are visible
- **THEN** the General control immediately reflects the resulting system state

#### Scenario: Registration change fails
- **WHEN** the operating system rejects a launch-at-login change
- **THEN** all controls retain the actual state and the failure is surfaced

### Requirement: Store identities remain unique after edits
The system SHALL reject an edit that would make one Store resolve to another registered Store's effective identity.

#### Scenario: Edited Store collides with another Store
- **WHEN** a Store edit resolves to an existing Store's effective identity
- **THEN** the edit fails and both prior Store records remain unchanged

### Requirement: Update status uses plugin-specific evidence
The system SHALL report an update only from evidence specific to the installed plugin version and SHALL NOT treat a catalog-wide timestamp as a per-plugin modification date.

#### Scenario: Manifest metadata changes without plugin-specific evidence
- **WHEN** only the catalog-wide timestamp changes for an installed plugin without comparable hashes or per-plugin timestamps
- **THEN** the system does not report that plugin as having an update
