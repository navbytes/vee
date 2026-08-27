# Tasks: detached-window-position-memory

## 1. Frame memory

- [x] 1.1 In `DetachedPluginWindows.show()`: per-plugin frame autosave with the
  restore-before-name order (`setFrameUsingName` → center/cascade only when it
  returns false → `setFrameAutosaveName`), replacing the unconditional
  center/cascade and its "no frame autosave" comment

## 2. Pin persistence

- [x] 2.1 Persist the per-plugin pin preference through `VeePreferences`
  following the existing `AppPreferences` pattern (default pinned), replacing
  the session dictionary as the source of truth — with a unit test covering
  the set → reload → read round-trip and the default
- [x] 2.2 Wire `DetachedPluginWindows` (`isPinned`, `setPinned`, `show`) to the
  persisted preference; windowless-seam tests keep passing unchanged

## 3. Verify and document

- [x] 3.1 Manual QA: move/resize → close → reopen restores (same session);
  quit → relaunch → reopen restores; first-ever open still centers/cascades;
  unpin → quit → relaunch → reopen opens unpinned; a frame saved on a
  disconnected display reopens fully visible
- [x] 3.2 Docs: the window section of `plugin-authoring.md` notes that each
  plugin's window remembers its position, size, and floating state
