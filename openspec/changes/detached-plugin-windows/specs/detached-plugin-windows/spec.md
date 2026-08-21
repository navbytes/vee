## Purpose

Lets a user take a plugin's whole menu surface out of the menu bar and leave it
on the desktop as a live window, so output worth watching stays visible while
they work in another app. It is a second presentation of the plugin's existing
search panel, not a separate surface.

## ADDED Requirements

### Requirement: Opening a plugin in a window

Vee SHALL offer, in each plugin's dropdown, an action that opens that plugin's
entire menu tree as a resizable window. The action MUST be available for every
plugin, with no declaration or opt-in required of the plugin itself.

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

### Requirement: Windows stay live

A window SHALL reflect its plugin's latest output, updating on the plugin's own
refresh cadence. It MUST NOT be a static capture of the moment it was opened.

Liveness applies to the window presentation only. The transient panel SHALL keep
its content frozen while open, so rows never reorder under the pointer or the
keyboard selection while the user is searching.

#### Scenario: Plugin refreshes while its window is open

- **WHEN** a plugin produces new output
- **THEN** its open window shows the new content
- **AND** the update is visible without the user reopening the window or the
  dropdown

#### Scenario: Structure changes between refreshes

- **WHEN** a refresh changes which rows the plugin emits, or their order or
  nesting
- **THEN** the window renders the new tree as given
- **AND** no row from the previous output is retained

### Requirement: Windows disclose staleness

When Vee can no longer produce fresh output for a plugin, its window SHALL
continue to display the last output it received and SHALL indicate that the
content is no longer current. Blanking the window or silently freezing it are
both prohibited: noticing that a watched value stopped reporting is the reason
the window exists.

#### Scenario: Plugin is disabled or removed

- **WHEN** a plugin with an open window is disabled or removed
- **THEN** the window continues to show the last output received
- **AND** the window indicates that the content is stale

#### Scenario: Plugin begins failing

- **WHEN** a plugin with an open window starts erroring or timing out
- **THEN** the window continues to show the last successful output
- **AND** the window indicates that the content is stale

#### Scenario: Plugin recovers

- **WHEN** a plugin marked stale produces successful output again
- **THEN** the window shows the new content
- **AND** the stale indication is cleared

### Requirement: Window level is the user's choice

Each window SHALL offer a control that switches it between floating above other
applications and behaving as an ordinary window. New windows SHALL default to
floating.

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

### Requirement: Open windows are listed and retrievable

Vee SHALL provide, from its menu-bar item, a list of every open detached window,
and selecting an entry SHALL bring that window to the front. This list is the
guaranteed retrieval path: Vee runs as an accessory application, so a
non-floating window that is covered has no Dock icon and no App Exposé route
back to it.

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

### Requirement: A plugin's hotkey can open either presentation

A plugin that declares a global hotkey SHALL let the user choose which
presentation that hotkey opens: the transient panel, or the window. The
transient panel SHALL remain the default, so a plugin that declared a hotkey
before this choice existed keeps behaving as it did.

The choice SHALL NOT require a new declaration from the plugin, and SHALL be
subject to the same user control every plugin hotkey already has — it can be
turned off, rebound, and reports the same collision and validity states.

#### Scenario: Default presentation is unchanged

- **WHEN** a plugin declares a hotkey and the user has not chosen a presentation
- **THEN** pressing the hotkey opens the transient panel as before

#### Scenario: Hotkey opens the window

- **WHEN** the user sets a plugin's hotkey to open its window, and presses it
- **THEN** that plugin's window opens

#### Scenario: Hotkey retrieves an open window

- **WHEN** the hotkey is set to open the window, the window is already open,
  and it is covered by another application
- **THEN** pressing the hotkey brings the existing window to the front
- **AND** no second window is created

#### Scenario: Hotkey control still applies

- **WHEN** the hotkey is set to open the window and the user disables or
  rebinds it
- **THEN** the change takes effect the same way it does for the transient panel
- **AND** the same status is reported for an unavailable or invalid combination

#### Scenario: Plugin declares no hotkey

- **WHEN** a plugin declares no hotkey
- **THEN** no presentation choice is offered for it
- **AND** its window remains reachable from its dropdown and from the list of
  open windows

### Requirement: The window keeps the panel's search

A window SHALL offer the same search over its plugin's rows that the transient
panel offers, so choosing the window presentation gives up nothing the panel
provided.

#### Scenario: Searching within a window

- **WHEN** the user types a query in an open window
- **THEN** the rows are filtered and ranked exactly as they are in the panel

#### Scenario: Empty query shows everything

- **WHEN** a window's query is empty
- **THEN** the plugin's full menu structure is shown, including section headers
  and separators

#### Scenario: Search does not freeze a window

- **WHEN** a refresh arrives while a query is active in a window
- **THEN** the window reflects the new output, filtered by the same query

### Requirement: Window content fidelity

A window SHALL reproduce the content of its plugin's dropdown, including nested
submenus, separators, section headers, per-row text styling and colors, declared
icons, disabled and checked state, tooltips, and every rich row Vee renders:
progress gauges, sparklines, share charts, toggles, and sliders.

A window SHALL NOT reproduce mechanics that only have meaning inside an open
menu. An `⌥` alternate SHALL be presented as an ordinary row of its own rather
than as a modifier-hold state, so its content is visible and activatable instead
of unreachable. Per-row `key=` equivalents SHALL NOT be bound, since they are
scoped to an open menu.

#### Scenario: Rich rows render

- **WHEN** a plugin emits rows carrying progress gauges, sparklines, share
  charts, toggles, or sliders
- **THEN** the window renders each with the same visual treatment the dropdown
  gives it

#### Scenario: Nested submenus

- **WHEN** a plugin emits nested submenu levels
- **THEN** the window presents the nesting and lets the user reach every level

#### Scenario: Alternate rows appear as ordinary rows

- **WHEN** a plugin emits a row with an alternate
- **THEN** the window renders both the primary row and its alternate as
  ordinary rows
- **AND** neither requires holding a modifier to see

#### Scenario: Key equivalents are not bound

- **WHEN** a plugin emits a row declaring a `key=` equivalent
- **THEN** the window renders the row normally
- **AND** pressing that combination while the window is focused does not
  activate it

#### Scenario: A row excluded from the dropdown

- **WHEN** a plugin emits a row marked as menu-bar-only
- **THEN** the window omits it, exactly as the dropdown does

### Requirement: Window rows are actionable

Activating a row in a window SHALL perform the same action activating it in the
dropdown performs, and SHALL be indistinguishable in effect from doing so.
Committing a value on a detached toggle or slider SHALL re-invoke the row's
command exactly as the dropdown's control does.

#### Scenario: Activating an action row

- **WHEN** the user activates a row carrying a link, a shell command, a
  Shortcut, a refresh request, or a web view
- **THEN** the same action runs as when that row is activated from the dropdown

#### Scenario: Committing a control

- **WHEN** the user changes a toggle or slider in a window and the value settles
- **THEN** the row's command is re-invoked with that value
- **AND** the plugin refreshes afterwards if the row requested it

#### Scenario: A control's command changes between refreshes

- **WHEN** a window has been open across refreshes that changed the command a
  control row declares, and the user then commits a value
- **THEN** the command the row declares now is the one invoked

#### Scenario: Decorative rows stay inert

- **WHEN** the user clicks a row that carries no action
- **THEN** nothing runs
