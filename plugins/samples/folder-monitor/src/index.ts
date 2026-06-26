/**
 * Sample Vee plugin: "Folder Monitor".
 *
 * A MENU-BAR command (mode `"menu-bar"`, `refreshIntervalSeconds: 30`) that
 * watches a user-chosen folder and surfaces its file count in the system status
 * bar, with the individual files listed in the dropdown.
 *
 * How the host projects a menu-bar render tree (the contract this targets):
 *   • the ROOT node's `title` prop becomes the status-bar text and its `icon`
 *     prop (an SF-Symbol name) the status icon;
 *   • each `list-item` descendant becomes a dropdown row (props `title`,
 *     optional `subtitle`, and `actionId` — echoed back via `onInvokeAction`
 *     when the row is clicked);
 *   • a node tagged `"separator"` becomes a divider.
 * So we render `root({title, icon}, [ list({}, [ listItem(...), ... ]) ])`.
 *
 * The folder is a plugin-DECLARED preference (see `preferences` in `vee.json`);
 * the user sets it once under Settings → Extensions → Folder Monitor and the
 * plugin reads it synchronously via `getPreferenceValues<{ folder?: string }>()`.
 *
 * Behavior:
 *   • folder UNSET → render a menu bar titled "Folder" whose single row points
 *     the user at the settings form (a required pref that is still unmet does
 *     not stop a menu-bar command from activating, so we handle it gracefully
 *     rather than crash);
 *   • folder SET   → `vee.fs.list(folder)` (capability-gated to the filesystem
 *     roots), count the non-directory entries, render the count as the status
 *     title and one dropdown row per file (capped) plus a "Refresh" row. Any
 *     filesystem error degrades to an empty listing rather than throwing.
 *
 * Change detection: the JS context is reused across the 30s refreshes, so a
 * module-scope `lastCount` persists. When the file count CHANGES between
 * refreshes (and a previous count was already recorded) we post a system
 * notification via `vee.notify(...)`.
 *
 * Actions: "refresh" reloads; "open:<name>" opens that file via `vee.open`;
 * "noop" does nothing (the empty-state row).
 */

import {
  definePlugin,
  el,
  fs,
  getPreferenceValues,
  list,
  listItem,
  notify,
  onInvokeAction,
  open,
  root,
  type RenderNode,
} from "@vee/sdk";

/** A directory entry as returned by `vee.fs.list`. */
interface FsEntry {
  name: string;
  isDirectory: boolean;
}

/** Cap the number of dropdown rows so a huge folder stays usable. */
const MAX_ROWS = 20;

/**
 * The menu bar shown when no folder is configured. The single dropdown row
 * points the user at the settings form. Exported for the unit test.
 */
export function noFolderTree(): RenderNode {
  return root({ title: "Folder", icon: "folder" }, [
    list({}, [
      listItem({ key: "noop", title: "Set a folder in Settings → Extensions", actionId: "noop" }),
    ]),
  ]);
}

/**
 * Build the menu-bar render tree for a folder's entries: the status title is the
 * non-directory file count, followed by one row per file (capped at MAX_ROWS), a
 * divider, then a "Refresh" row. Exported (pure) so the unit test can assert on
 * it without a host. Mirrors github's exported `pullRequestsTree`.
 */
export function monitorTree(folder: string, entries: FsEntry[]): RenderNode {
  void folder;
  const files = entries.filter((e) => !e.isDirectory);
  const fileCount = files.length;

  const rows: RenderNode[] = files.slice(0, MAX_ROWS).map((f) =>
    listItem({ key: "open:" + f.name, title: f.name, actionId: "open:" + f.name }),
  );

  // A divider is optional in the contract; emit one with the low-level element
  // constructor since the SDK has no dedicated `separator()` builder.
  rows.push(el("separator", { key: "sep" }));
  rows.push(listItem({ key: "refresh", title: "Refresh", subtitle: "Re-scan the folder", actionId: "refresh" }));

  return root({ title: String(fileCount), icon: "folder" }, [list({}, rows)]);
}

/** Count the non-directory entries in a listing. */
function countFiles(entries: FsEntry[]): number {
  return entries.filter((e) => !e.isDirectory).length;
}

// Module-scope: persists across the 30s menu-bar refreshes because the host
// reuses the JS context. `undefined` until the first successful scan.
let lastCount: number | undefined;

/**
 * Scan the folder and render. On any filesystem error the listing degrades to
 * `[]` (rendered as a zero count) rather than throwing — a menu-bar command must
 * never crash the status item. When the count changes between refreshes, post a
 * system notification.
 */
async function loadFolder(ctx: { render: (n: RenderNode) => void }): Promise<void> {
  const { folder } = getPreferenceValues<{ folder?: string }>();

  if (!folder) {
    ctx.render(noFolderTree());
    return;
  }

  let entries: FsEntry[] = [];
  try {
    entries = await fs().list(folder);
  } catch {
    entries = [];
  }

  const count = countFiles(entries);
  if (lastCount !== undefined && count !== lastCount) {
    notify("Folder Monitor", folder + " now has " + count + " files");
  }
  lastCount = count;

  ctx.render(monitorTree(folder, entries));
}

definePlugin({
  commands: {
    monitor: (ctx) => {
      // Wire the dropdown actions, then do the initial scan. The host calls the
      // command again on each refresh tick, so registering here is sufficient.
      onInvokeAction(async (p) => {
        if (p.actionId === "noop") return;
        if (p.actionId === "refresh") {
          await loadFolder(ctx);
          return;
        }
        if (p.actionId.startsWith("open:")) {
          const { folder } = getPreferenceValues<{ folder?: string }>();
          if (!folder) return;
          const name = p.actionId.slice("open:".length);
          await open("file://" + folder + "/" + name);
        }
      });

      return loadFolder(ctx);
    },
  },
});
