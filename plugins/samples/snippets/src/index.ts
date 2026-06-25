/**
 * Sample Vee plugin: "Snippets".
 *
 * Demonstrates persistence via `vee.storage`. On activation of the `view`
 * command it loads the saved snippets from storage (key `"snippets"`) and
 * renders them as a `root → list`. Each row's primary `action` ("Copy") puts the
 * snippet text on the pasteboard via `vee.clipboard.copy`; a secondary "Delete"
 * action removes it and persists the new set back to `vee.storage`. A `form`
 * row at the top lets the user add a new snippet — on submit it is appended and
 * persisted, then the list re-renders.
 *
 * Failure handling: a storage read failure falls back to an empty set (and
 * toasts); the command never throws/crashes.
 */

import {
  action,
  actionPanel,
  definePlugin,
  empty,
  field,
  form,
  list,
  listItem,
  onInvokeAction,
  onSubmitForm,
  root,
  showToast,
  storage,
  type RenderNode,
} from "@vee/sdk";

const STORAGE_KEY = "snippets";

/** A persisted snippet. */
interface Snippet {
  id: string;
  title: string;
  text: string;
}

/** One-line preview of snippet text (collapse whitespace, truncate). */
export function preview(text: string): string {
  const oneLine = text.replace(/\s+/g, " ").trim();
  return oneLine.length > 60 ? oneLine.slice(0, 57) + "…" : oneLine;
}

/** Coerce an arbitrary stored value into a Snippet[] (defensive). */
export function coerceSnippets(value: unknown): Snippet[] {
  if (!Array.isArray(value)) return [];
  const out: Snippet[] = [];
  for (const v of value) {
    if (v && typeof v === "object") {
      const o = v as Record<string, unknown>;
      if (typeof o.id === "string" && typeof o.text === "string") {
        out.push({ id: o.id, title: typeof o.title === "string" ? o.title : preview(o.text), text: o.text });
      }
    }
  }
  return out;
}

/** Build a row for one snippet. Exported for the unit test. */
export function snippetRow(snippet: Snippet): RenderNode {
  return listItem(
    { key: snippet.id, id: snippet.id, title: snippet.title, subtitle: preview(snippet.text), icon: "text.quote" },
    [
      actionPanel({}, [
        action({ actionId: `copy:${snippet.id}`, title: "Copy", shortcut: "cmd+enter" }),
        action({ actionId: `delete:${snippet.id}`, title: "Delete", shortcut: "cmd+backspace" }),
      ]),
    ],
  );
}

/** The "add a snippet" form row, shown at the top of the list. */
export function addSnippetForm(): RenderNode {
  return form({ key: "add", actionId: "add", title: "New Snippet" }, [
    field({ key: "title", name: "title", label: "Title", placeholder: "Short name" }),
    field({ key: "text", name: "text", label: "Snippet", placeholder: "Text to save" }),
  ]);
}

/** Build the full list tree from snippets. Exported for the unit test. */
export function snippetsTree(snippets: Snippet[]): RenderNode {
  const children: RenderNode[] = [addSnippetForm()];
  if (snippets.length === 0) {
    children.push(
      empty({
        key: "empty",
        title: "No snippets yet",
        description: "Add one above to save reusable text.",
        icon: "text.quote",
      }),
    );
  } else {
    for (const s of snippets) children.push(snippetRow(s));
  }
  return root({}, [list({ key: "snippets", filtering: snippets.length > 0 }, children)]);
}

declare const vee: {
  clipboard: { copy(item: { id: string; text: string; copiedAt: string }): Promise<void> };
};

/** Load snippets from storage, defaulting to an empty set on any failure. */
async function readSnippets(): Promise<Snippet[]> {
  try {
    const raw = await storage().get(STORAGE_KEY);
    return coerceSnippets(raw);
  } catch {
    showToast("failure", "Snippets", "Could not read saved snippets.");
    return [];
  }
}

/** Load + render; wire copy/delete actions and the add-snippet form. */
async function loadSnippets(ctx: { render: (n: RenderNode) => void }): Promise<void> {
  let snippets = await readSnippets();
  const rerender = () => ctx.render(snippetsTree(snippets));

  const persist = async () => {
    try {
      await storage().set(STORAGE_KEY, snippets as unknown as never);
    } catch (err) {
      showToast("failure", "Snippets", "Could not save snippets.");
      void err;
    }
  };

  onInvokeAction(async (p) => {
    const [verb, id] = p.actionId.split(":");
    const snippet = snippets.find((s) => s.id === id);
    if (!snippet) return;
    if (verb === "copy") {
      try {
        await vee.clipboard.copy({ id: snippet.id, text: snippet.text, copiedAt: new Date().toISOString() });
        showToast("success", "Copied", preview(snippet.text));
      } catch (err) {
        showToast("failure", "Copy failed", String(err));
      }
    } else if (verb === "delete") {
      snippets = snippets.filter((s) => s.id !== id);
      await persist();
      rerender();
      showToast("success", "Deleted", snippet.title);
    }
  });

  onSubmitForm(async (p) => {
    if (p.actionId !== "add") return;
    const title = typeof p.values.title === "string" ? p.values.title.trim() : "";
    const text = typeof p.values.text === "string" ? p.values.text : "";
    if (text.trim().length === 0) {
      showToast("failure", "Snippets", "Snippet text is required.");
      return;
    }
    const id = `s_${Date.now()}_${snippets.length}`;
    snippets = [{ id, title: title || preview(text), text }, ...snippets];
    await persist();
    rerender();
    showToast("success", "Saved", title || preview(text));
  });

  rerender();
}

definePlugin({
  commands: {
    view: (ctx) => loadSnippets(ctx),
  },
});
