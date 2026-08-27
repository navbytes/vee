# detached-plugin-windows Specification

## Purpose
Lets a user take a plugin's whole menu surface out of the menu bar and leave it
on the desktop as a live window, so output worth watching stays visible while
they work in another app. It is a second presentation of the plugin's existing
search panel, not a separate surface.

## Requirements

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

A window SHALL offer a filter over its plugin's rows, and the transient panel
SHALL offer the same one, so choosing either presentation gives up nothing the
other provides.

The filter SHALL preserve the plugin's structure rather than replace it. A query
narrows the menu to the rows that match and the ancestors needed to reach them,
and those ancestors SHALL be revealed automatically so every match is visible
without further interaction. Matching SHALL consider a row's own text and the
titles of its ancestors, so naming a group surfaces what is inside it.

Because the filtered result remains a structure, rows SHALL keep the order the
plugin authored. The filter SHALL NOT reorder rows by how well they match.

#### Scenario: Searching within a window

- **WHEN** the user types a query in an open window
- **THEN** only rows matching the query, and the ancestors needed to reach them,
  are shown
- **AND** those ancestors are revealed automatically

#### Scenario: Matching by ancestor name

- **WHEN** the user types the title of a group
- **THEN** the rows inside that group are surfaced

#### Scenario: Authored order is preserved

- **WHEN** a query matches several rows across different parts of the menu
- **THEN** they appear in the order the plugin emitted them
- **AND** they are not reordered by match quality

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

Nesting SHALL be presented as structure the user can open and close in place,
not as a flattened list annotated with the path to each row. More than one
branch MAY be open at a time, so values in different parts of the menu can be
watched together.

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
- **THEN** the window presents each level as structure the user can open in place
- **AND** every level is reachable

#### Scenario: More than one branch open

- **WHEN** the user opens two separate nested groups
- **THEN** both remain open at the same time
- **AND** the contents of both are visible together

#### Scenario: A row's ancestors are visible, not annotated

- **WHEN** a nested row is shown
- **THEN** its position is conveyed by where it sits in the structure
- **AND** it does not carry a textual path to itself

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

### Requirement: Open branches survive a refresh

A window updates on its plugin's own cadence, and that update SHALL NOT discard
what the user has opened. Branches the user opened SHALL remain open across
refreshes for as long as the plugin still emits them.

A branch that is no longer present after a refresh SHALL simply not be shown; it
MUST NOT cause unrelated branches to close. Where a branch cannot be recognised
across a refresh, the window SHALL degrade by closing only that branch.

#### Scenario: A refresh keeps branches open

- **WHEN** the user opens a nested group and the plugin refreshes with new
  values
- **THEN** the group is still open
- **AND** the new values are shown inside it

#### Scenario: A vanished branch closes alone

- **WHEN** a plugin stops emitting a group the user had opened
- **THEN** that group is no longer shown
- **AND** every other open group remains open

#### Scenario: Rapid refreshes do not fight the user

- **WHEN** a plugin refreshes repeatedly while the user has branches open
- **THEN** the branches stay open across every refresh

### Requirement: A window carries its plugin's controls

A window SHALL offer the same plugin controls its dropdown offers — refreshing
the plugin, opening its settings, showing its About information, revealing it in
the Finder, editing it, and opening its debug view — so a plugin can be operated
from the window it is being watched in.

These controls are chrome, not plugin output. They SHALL NOT appear among the
plugin's rows, and the filter SHALL NOT match them.

#### Scenario: Refreshing from a window

- **WHEN** the user invokes refresh from an open window
- **THEN** the plugin re-runs
- **AND** the window shows the new output

#### Scenario: Controls are excluded from the filter

- **WHEN** the user types a query that would match a control's name
- **THEN** no control appears among the filtered rows

#### Scenario: Controls are not plugin rows

- **WHEN** a window shows a plugin's menu
- **THEN** the controls are presented apart from the plugin's own rows
