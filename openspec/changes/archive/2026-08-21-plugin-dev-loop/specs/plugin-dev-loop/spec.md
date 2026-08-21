## Purpose

Gives a plugin author a save-driven feedback loop: edit a script or a block of
protocol text, save it, and immediately see the menu Vee would build from it,
along with any authoring mistakes — from whatever editor they already use.

## ADDED Requirements

### Requirement: A save-driven watch loop

Vee SHALL provide a command that watches a single file and, on every change to
that file, produces a fresh view of the menu Vee would build from it. The view
MUST include the parsed menu tree and any authoring diagnostics, and MUST replace
the previous view rather than appending to it, so what is on screen is always the
result of the most recent save.

#### Scenario: Saving a watched script

- **WHEN** the author saves a file that the watch loop is watching
- **THEN** the file is re-run and the view is replaced with the new result
- **AND** the author did not have to re-issue any command

#### Scenario: A save that introduces an authoring mistake

- **WHEN** a save produces output containing an authoring mistake the linter
  detects
- **THEN** the diagnostic appears in the same view as the menu tree
- **AND** the best-effort menu tree is still shown alongside it

#### Scenario: A save that makes the script fail

- **WHEN** a save produces a non-zero exit, a timeout, or output on standard
  error
- **THEN** the view reports which of these occurred
- **AND** the loop keeps watching rather than exiting

#### Scenario: Rapid successive saves

- **WHEN** the file changes several times in quick succession
- **THEN** the loop does not start a new run for every individual change event
- **AND** the view converges on the content of the final save

#### Scenario: The watched file is replaced rather than written in place

- **WHEN** the editor saves by writing a temporary file and renaming it over the
  watched path
- **THEN** the loop still detects the change and keeps watching the path
- **AND** it does not go inert for the remainder of the session

#### Scenario: Leaving the loop

- **WHEN** the author asks the loop to stop
- **THEN** it exits and leaves the terminal in the state it found it

### Requirement: Previewing protocol text without executing it

The watch loop SHALL offer a mode that treats the watched file's contents as
plugin output directly and does not execute it. In this mode no process is
spawned for the watched file, so the file needs no execute permission, no
shebang, and carries no risk of running arbitrary code on save.

#### Scenario: Watching a file of protocol text

- **WHEN** the author watches a file in non-executing mode and saves it
- **THEN** the contents are parsed as plugin output and the resulting menu tree
  is shown
- **AND** the file is not executed

#### Scenario: The file is not executable

- **WHEN** the watched file has no execute permission and no shebang
- **THEN** non-executing mode still previews it successfully

### Requirement: Diagnostics an editor can place on a line

Vee SHALL be able to emit authoring diagnostics in a machine-parseable form
carrying a path, a line, a severity, and a message, so that an editor can render
them as inline diagnostics without any Vee-specific editor plugin. The
human-readable form MUST remain the default, so existing output is unchanged for
anyone who has not asked for the parseable form.

#### Scenario: Requesting the parseable form

- **WHEN** the author requests the machine-parseable diagnostic form
- **THEN** each finding is emitted on one line carrying its path, line number,
  severity, and message
- **AND** a file with no findings emits no diagnostic lines

#### Scenario: The default form is unchanged

- **WHEN** the author does not request the parseable form
- **THEN** diagnostics are emitted in the existing human-readable form

#### Scenario: Diagnostics that carry no line number

- **WHEN** a finding has no line number associated with it
- **THEN** it is still reported in the parseable form
- **AND** it is attributed to a line that exists, so no editor is asked to place
  it out of range

### Requirement: Line numbers must not be attributed to a source they do not describe

Authoring diagnostics are computed over a plugin's **output**, not its source. For
an executed script there is no recoverable mapping from an output line back to
the source line that emitted it, because one statement may emit many lines.
Vee's parseable diagnostics MUST therefore attribute a finding to the author's
file **only** when the finding's line number is a line of that file. When the
diagnostics describe the output of an executed script, they MUST be attributed to
a path that no editor will resolve to the script.

#### Scenario: Diagnostics for protocol text authored directly

- **WHEN** parseable diagnostics are emitted for a file being previewed without
  execution
- **THEN** each finding names that file's path
- **AND** the line number identifies the line in that file that must be fixed

#### Scenario: Diagnostics for the output of an executed script

- **WHEN** parseable diagnostics are emitted for a script that was executed
- **THEN** the findings are not attributed to the script's path
- **AND** an editor consuming them does not mark any line of the script

### Requirement: Previewing a save as a real menu-bar item

The watch loop SHALL offer, on request, to render each save as a real status item
in the running Vee app, so the author sees Vee's true native render and not only
a textual tree. This MUST be opt-in: the loop MUST NOT add a status item to the
user's menu bar unless the author asked for it.

#### Scenario: Previewing in the menu bar

- **WHEN** the author runs the watch loop with menu-bar preview requested and
  saves the file
- **THEN** a status item in the running Vee app shows the menu built from that
  save
- **AND** the item updates on each subsequent save rather than accumulating a new
  item per save

#### Scenario: Preview is not requested

- **WHEN** the author runs the watch loop without requesting menu-bar preview
- **THEN** no status item is created
- **AND** the author's existing menu bar is untouched

#### Scenario: Vee is not already running

- **WHEN** menu-bar preview is requested and the Vee app is not running
- **THEN** Vee is started without taking focus away from the author's editor
- **AND** the loop says that it started Vee, rather than doing so silently

#### Scenario: Vee cannot be reached at all

- **WHEN** menu-bar preview is requested and no installed Vee can handle it
- **THEN** the loop reports that the preview could not be shown
- **AND** the textual view continues to work on every save

#### Scenario: Executable actions cannot be fired from a preview

- **WHEN** a previewed menu contains a row carrying an executable action
- **THEN** the row is still visible in the preview so the author can confirm they
  wrote it
- **AND** the author is told that executable actions do not fire in a preview,
  rather than the row silently doing nothing

#### Scenario: The preview does not outlive the loop

- **WHEN** the watch loop exits
- **THEN** the preview status item is removed
- **AND** no file was written to the plugins folder at any point

### Requirement: Prompt detection of edits to installed plugins

Vee SHALL detect an edit to an already-installed plugin file promptly, whether
the editor writes the file in place or replaces it, so that an author editing a
plugin that is already in the plugins folder sees the menu bar update shortly
after saving rather than after a fixed polling delay.

#### Scenario: Editing an installed plugin in place

- **WHEN** the contents of an installed plugin file are modified in place
- **THEN** Vee re-reads that plugin promptly
- **AND** the author does not wait for a fixed polling interval to elapse

#### Scenario: Adding and removing plugins still works

- **WHEN** a plugin file is added to, removed from, or renamed within the plugins
  folder
- **THEN** Vee reacts as it does today

#### Scenario: The plugins folder is replaced

- **WHEN** the watched plugins folder is itself deleted and recreated, or the
  configured folder changes
- **THEN** Vee recovers and continues detecting changes without a relaunch

#### Scenario: An unchanged file does not cause work

- **WHEN** a change is detected but the plugin's content signature is unchanged
- **THEN** Vee does not rebuild or re-run the plugin
