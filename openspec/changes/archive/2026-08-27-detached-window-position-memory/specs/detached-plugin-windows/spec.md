# detached-plugin-windows Delta — detached-window-position-memory

## MODIFIED Requirements

### Requirement: Opening a plugin in a window

Vee SHALL offer, in each plugin's dropdown, an action that opens that plugin's
entire menu tree as a resizable window. The action MUST be available for every
plugin, with no declaration or opt-in required of the plugin itself.

Each plugin's window SHALL remember its frame — position and size — and reopen
with it, both within a session and across relaunches. Vee places a window
itself only when that plugin has no remembered frame. A remembered frame whose
screen is no longer present SHALL open fully visible on a screen that is.

#### Scenario: Opening a plugin's window

- **WHEN** the user invokes "Open in Window" from a plugin's dropdown
- **THEN** a window opens showing that plugin's current menu content
- **AND** the plugin's menu-bar item remains present and functional

#### Scenario: Promoting the transient panel

- **WHEN** the plugin's transient search panel is open and the user invokes its
  "keep open" control
- **THEN** the panel is replaced by a window showing the same plugin
- **AND** the content is not shown twice

#### Scenario: The transient panel is unchanged

- **WHEN** the user opens a plugin's search panel as before
- **THEN** it behaves exactly as it did — anchored near the pointer, dismissed
  by Escape, by activating a row, or by clicking outside
- **AND** its content remains frozen for as long as it is open

#### Scenario: Re-invoking for a plugin that already has a window

- **WHEN** the user invokes "Open in Window" for a plugin whose window is
  already open
- **THEN** the existing window is brought to the front and made key
- **AND** no second window is created for that plugin

#### Scenario: Several plugins at once

- **WHEN** the user opens windows for more than one plugin
- **THEN** each plugin has its own independent window
- **AND** each window updates on its own plugin's refresh cadence

#### Scenario: Windows do not survive a relaunch

- **WHEN** the user quits Vee with one or more windows open, and launches it
  again
- **THEN** no windows are restored

#### Scenario: Reopening restores the window's place

- **WHEN** the user moves or resizes a plugin's window, closes it, and opens
  that plugin's window again in the same session
- **THEN** it opens with the frame it last had

#### Scenario: The frame survives a relaunch

- **WHEN** the user quits Vee and, in a later launch, opens a plugin's window
  that had been placed before
- **THEN** it opens with the frame it last had in the earlier session

#### Scenario: A first-ever window is placed by Vee

- **WHEN** the user opens a window for a plugin that has never had one
- **THEN** Vee places it itself, stepped away from other detached windows so
  several opened together do not stack into one

#### Scenario: A remembered screen is gone

- **WHEN** a window's remembered frame lies on a screen that is no longer
  connected
- **THEN** the window opens fully visible on a screen that is present

### Requirement: Window level is the user's choice

Each window SHALL offer a control that switches it between floating above other
applications and behaving as an ordinary window. New windows SHALL default to
floating, and a plugin whose window the user unpinned SHALL stay unpinned —
within the session and across relaunches alike.

A floating window MUST remain visible when the user switches Spaces and when
another application is full-screen — the case the floating mode exists to serve
is watching a value while working elsewhere, and that includes working
full-screen.

#### Scenario: Default state

- **WHEN** a window is opened
- **THEN** it floats above windows of other applications

#### Scenario: Unpinning

- **WHEN** the user turns the floating control off
- **THEN** the window is ordered among ordinary application windows
- **AND** it can be covered by other applications' windows
- **AND** it appears in Mission Control

#### Scenario: Floating window and a full-screen app

- **WHEN** a floating window is open and the user switches to a full-screen
  application or to another Space
- **THEN** the floating window remains visible

#### Scenario: Floating state is remembered for the session

- **WHEN** the user unpins a plugin's window, closes it, and opens that
  plugin's window again in the same session
- **THEN** the window opens unpinned

#### Scenario: Floating state survives a relaunch

- **WHEN** the user unpins a plugin's window, quits Vee, and opens that
  plugin's window in a later launch
- **THEN** the window opens unpinned
