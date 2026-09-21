## Purpose

Keeps every pane of the consolidated Library window bound to one current plugin inventory while protecting draft edits and reporting persistence outcomes truthfully.

## ADDED Requirements

### Requirement: Library routing preserves the active session
The system SHALL reuse the active Library session when a menu command requests Installed, Discover, or General, changing only the selected section.

#### Scenario: Shortcut while Variables has a draft
- **WHEN** a user edits a Variables value without saving and invokes any Library menu shortcut
- **THEN** the requested section opens and the buffered Variables edit remains available when the user returns

### Requirement: Live inventory reconciliation is coherent
After an effective plugin inventory or header change, the system SHALL update Installed and Variables from the same current-directory snapshot without requiring the Library window to close.

#### Scenario: Discover installs a plugin
- **WHEN** installation succeeds in Discover
- **THEN** the plugin appears in Installed and its declared variables appear in Variables in the open Library session

#### Scenario: Files change outside Vee
- **WHEN** the directory watcher observes a plugin add, removal, or variable-header change
- **THEN** Installed and Variables reconcile to the resulting inventory

#### Scenario: Reconciliation preserves compatible drafts
- **WHEN** inventory reconciliation retains the same plugin and variable-field identities
- **THEN** buffered edits for those identities remain unchanged while new fields receive persisted/default values and removed identities disappear

### Requirement: Plugin folder changes rebind atomically
The system SHALL bind General, Installed, Variables, and Discover to one plugins directory and SHALL NOT expose a mixture of old- and new-directory state.

#### Scenario: Folder change with no draft
- **WHEN** a user confirms a different plugins folder
- **THEN** all Library panes switch to the new directory as one transition and subsequent Discover installs target it

#### Scenario: Folder change with unsaved drafts
- **WHEN** a folder change would discard buffered Variables edits, per-plugin values, or a typed but unapplied plugin hotkey combination
- **THEN** the system requests an explicit discard decision before changing directories
- **AND** cancellation leaves every Library pane bound to the original directory with its draft intact

#### Scenario: Folder change during Discover installation
- **WHEN** a Discover fetch, trust prompt, or install is pending
- **THEN** the system blocks the folder transition or invalidates the old operation before it can publish a prompt or write to disk

### Requirement: Per-plugin Settings reports persistence truthfully
The system SHALL treat a per-plugin Settings save as successful only after every requested sidecar and Keychain value persists, SHALL identify failed fields without displaying values or arbitrary underlying error text, and SHALL retain the draft after failure.

#### Scenario: In-pane save fails
- **WHEN** any settings value fails to persist
- **THEN** the pane remains open, shows a controlled plugin-and-field failure, retains all edits, and does not refresh the plugin

#### Scenario: Standalone save fails
- **WHEN** any settings value fails to persist from the standalone Settings window
- **THEN** the window remains open with the same controlled failure and retained edits

#### Scenario: Every settings value saves
- **WHEN** all settings values persist successfully
- **THEN** the failure state clears, the plugin refreshes, and the standalone window may close

### Requirement: Store removal requires informed confirmation
The system SHALL require confirmation before removing a custom Store and its saved token.

#### Scenario: Removal is cancelled
- **WHEN** a user cancels the store-named removal confirmation
- **THEN** the Store, enabled state, and saved token remain unchanged

#### Scenario: Removal is confirmed
- **WHEN** a user confirms removal after being told the saved token will be deleted
- **THEN** exactly that custom Store and its token are removed
- **AND** the destructive control and confirmation expose the Store name to accessibility clients

### Requirement: Library root panes expose their titles
The system SHALL expose the selected section name as the navigation title for Variables, Stores, and General.

#### Scenario: User selects a settings section
- **WHEN** Variables, Stores, or General is selected
- **THEN** its section name is exposed as the detail navigation title without adding a duplicate content heading

### Requirement: Discover card actions remain readable
The system SHALL display Installed, Install, Update, and Reinstall labels on one readable line at the Library window's default and minimum supported widths.

#### Scenario: Discover at constrained width
- **WHEN** Discover is shown at the Library window's default or minimum width
- **THEN** each visible card's status and action labels remain untruncated and do not wrap vertically
