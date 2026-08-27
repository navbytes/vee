# detached-plugin-windows Delta — focus-all-windows-hotkey

## MODIFIED Requirements

### Requirement: Open windows are listed and retrievable

Vee SHALL provide, from its menu-bar item, a list of every open detached window,
and selecting an entry SHALL bring that window to the front. This list is the
guaranteed retrieval path: Vee runs as an accessory application, so a
non-floating window that is covered has no Dock icon and no App Exposé route
back to it.

Beyond one-at-a-time retrieval, Vee SHALL offer a single action that brings
**every** open detached window to the front at once, one of them made key.
The action SHALL be available as a row in the detached-windows list, and as an
app-level global hotkey that is unbound by default. The hotkey's combination is
configured in Vee's preferences with the same combination format, immediate
apply, and validity and collision reporting that per-plugin hotkeys have. With
no windows open, the action SHALL do nothing — it retrieves windows, it never
opens them.

#### Scenario: Listing open windows

- **WHEN** the user opens Vee's menu with detached windows open
- **THEN** every open window is listed, identified by its plugin

#### Scenario: Retrieving a covered window

- **WHEN** the user selects a listed window that is covered by another
  application
- **THEN** that window is brought to the front and made key

#### Scenario: No windows open

- **WHEN** the user opens Vee's menu with no detached windows open
- **THEN** the list is not shown

#### Scenario: Closing a window

- **WHEN** the user closes a window by any means, including the title-bar
  control
- **THEN** it is removed from the list
- **AND** invoking "Open in Window" for that plugin afterwards opens a new
  window rather than focusing the closed one

#### Scenario: One gesture retrieves every window

- **WHEN** several detached windows are open, some covered by other
  applications' windows, and the user presses the configured hotkey or picks
  the bring-all row from the detached-windows list
- **THEN** every open detached window is brought in front of other
  applications' windows
- **AND** one of them is made key

#### Scenario: The hotkey with nothing open

- **WHEN** the user presses the configured hotkey while no detached window is
  open
- **THEN** nothing happens — no window opens and no app activates

#### Scenario: Configuring the hotkey

- **WHEN** the user sets, changes, or clears the combination in Vee's
  preferences
- **THEN** the change applies immediately, without relaunching
- **AND** an invalid or already-claimed combination is reported the same way a
  per-plugin hotkey reports it

#### Scenario: Unbound by default

- **WHEN** the user has never configured the combination
- **THEN** no app-level hotkey is registered
- **AND** the bring-all row in the detached-windows list still works
