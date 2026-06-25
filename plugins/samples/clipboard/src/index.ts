/**
 * Sample Vee plugin: "Clipboard History".
 *
 * On activation of the `view` command it pulls the recent clipboard items from
 * the host via `vee.clipboard.history()` (capability-gated by `clipboard:true`)
 * and renders them as a `root → list`. Each row's primary `action` ("Copy")
 * carries the item id; when invoked the host echoes it back via
 * `host.invokeAction`, and the registered handler calls `vee.clipboard.copy(...)`
 * to place that item back on the pasteboard.
 *
 * Failure handling: a denied/failed history call renders an empty-state list
 * and toasts — the command never throws/crashes.
 */

import {
  action,
  actionPanel,
  clipboard,
  definePlugin,
  empty,
  list,
  listItem,
  onInvokeAction,
  root,
  showToast,
  type ClipboardItem,
  type RenderNode,
} from "@vee/sdk";

const HISTORY_LIMIT = 20;

/** A single-line preview of clipboard text (collapse whitespace, truncate). */
export function preview(text: string): string {
  const oneLine = text.replace(/\s+/g, " ").trim();
  return oneLine.length > 60 ? oneLine.slice(0, 57) + "…" : oneLine;
}

/** Build a row for one clipboard item. Exported for the unit test. */
export function clipboardItemRow(item: ClipboardItem): RenderNode {
  return listItem(
    { key: item.id, id: item.id, title: preview(item.text), subtitle: item.copiedAt, icon: "doc.on.clipboard" },
    [
      actionPanel({}, [
        action({ actionId: item.id, title: "Copy", shortcut: "cmd+enter" }),
      ]),
    ],
  );
}

/** Build the list tree from history items. Exported for the unit test. */
export function historyTree(items: ClipboardItem[]): RenderNode {
  if (items.length === 0) {
    return root({}, [
      list({ key: "clipboard", filtering: false }, [
        empty({ key: "empty", title: "Clipboard is empty", description: "Copy something to see it here.", icon: "doc.on.clipboard" }),
      ]),
    ]);
  }
  return root({}, [list({ key: "clipboard", filtering: true }, items.map(clipboardItemRow))]);
}

/** Load history + render; render an empty state on any failure. */
async function loadHistory(ctx: { render: (n: RenderNode) => void }): Promise<void> {
  // Remember items by id so the Copy action can round-trip the exact item
  // (text + copiedAt) back to the host.
  const byId = new Map<string, ClipboardItem>();

  onInvokeAction(async (p) => {
    const item = byId.get(p.actionId);
    if (!item) return;
    try {
      await clipboard().copy(item);
      showToast("success", "Copied", preview(item.text));
    } catch (err) {
      showToast("failure", "Copy failed", String(err));
    }
  });

  try {
    const items = await clipboard().history("", HISTORY_LIMIT);
    for (const item of items) byId.set(item.id, item);
    ctx.render(historyTree(items));
  } catch (err) {
    showToast("failure", "Clipboard", "Could not read clipboard history.");
    ctx.render(historyTree([]));
    void err;
  }
}

definePlugin({
  commands: {
    view: (ctx) => loadHistory(ctx),
  },
});
