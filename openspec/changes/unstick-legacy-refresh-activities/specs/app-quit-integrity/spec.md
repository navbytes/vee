## Purpose

Guarantees that quitting Vee is final. A menu-bar app the user cannot close is
worse than one that is missing a feature, so any mechanism capable of relaunching
Vee on its own must be removed on sight, whatever left it behind.

## ADDED Requirements

### Requirement: Quitting Vee is final

When the user quits Vee, it SHALL stay quit until the user launches it again. No
scheduling, refresh, or background-work mechanism SHALL be able to cause the
system to relaunch it.

#### Scenario: Quitting from the menu

- **WHEN** the user quits Vee
- **THEN** Vee exits and does not reappear

#### Scenario: Quitting with long-interval plugins installed

- **WHEN** the user quits Vee with plugins scheduled at any interval, including
  intervals of ten minutes or more
- **THEN** Vee exits and does not reappear

### Requirement: Legacy relaunch registrations are cleared on every launch

Vee SHALL clear background-activity registrations left by earlier versions on
every launch, for **every plugin it has ever loaded** — not only those installed
now.

The registration outlives the app, so a plugin deleted, renamed, disabled, or
moved out of the plugins folder before the clearing shipped is precisely the case
that keeps an install broken. Clearing SHALL therefore not depend on any plugin
being present, enabled, or starting successfully, and SHALL NOT be skipped on the
grounds that it has run before.

#### Scenario: A plugin that registered an activity has since been deleted

- **WHEN** Vee launches and a previously loaded plugin that once registered a
  background activity is no longer installed
- **THEN** that plugin's registration is still cleared
- **AND** the user can quit Vee and it stays quit

#### Scenario: No plugins are installed at all

- **WHEN** Vee launches with an empty plugins folder
- **THEN** any legacy registrations from previously loaded plugins are still
  cleared

#### Scenario: A plugin fails to start

- **WHEN** a plugin is present but cannot be started
- **THEN** legacy registrations are cleared regardless

#### Scenario: Clearing repeats on later launches

- **WHEN** Vee has already cleared registrations on a previous launch
- **THEN** it clears them again on the next launch
- **AND** clearing a registration that does not exist changes nothing

#### Scenario: The user changes plugin folders

- **WHEN** the user points Vee at a different plugins folder
- **THEN** plugins loaded from the previous folder are still cleared

### Requirement: Plugins Vee has loaded are remembered

Vee SHALL record the identifier of every plugin it loads, and that record SHALL
persist across launches. It exists so a plugin's legacy registration can be
cleared after the plugin itself is gone.

#### Scenario: A newly loaded plugin is recorded

- **WHEN** Vee loads a plugin for the first time
- **THEN** its identifier is remembered for future launches

#### Scenario: The record outlives the plugin

- **WHEN** a plugin Vee has previously loaded is deleted
- **THEN** its identifier is still remembered

### Requirement: A detected relaunch registration is surfaced

Where Vee detects that it has cleared a legacy registration, it SHALL make that
visible to the user rather than recovering silently, so someone whose app would
not quit can tell what happened.

Recovery itself SHALL NOT require any user action.

#### Scenario: Reporting a cleared registration

- **WHEN** Vee clears a legacy registration at launch
- **THEN** the user can discover that this happened
- **AND** no action is required of them for the fix to take effect
