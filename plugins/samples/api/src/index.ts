/**
 * Sample Vee plugin: "API Monitor" (generic).
 *
 * Demonstrates the generic "fetch a JSON endpoint → render a list" pattern. On
 * activation of the `view` command it GETs a configurable JSON endpoint
 * (`ctx.arguments.url`, defaulting to the public, no-auth GitHub API root) via
 * `vee.http.fetch` and renders the result as a `root → list`:
 *   • a JSON object → one row per key ("key" title, stringified value subtitle);
 *   • a JSON array  → one row per element (index title, stringified value).
 * Each row's primary `action` copies the value via `vee.clipboard.copy` — i.e.
 * the result is inspectable without leaving the launcher.
 *
 * The default endpoint must lie within `capabilities.network` (`api.github.com`);
 * pointing it elsewhere requires widening the manifest. Any network/parse error
 * renders an empty-state list AND toasts — the command never throws/crashes.
 */

import {
  action,
  actionPanel,
  clipboard,
  definePlugin,
  empty,
  http,
  list,
  listItem,
  onInvokeAction,
  root,
  showToast,
  type JSONValue,
  type RenderNode,
} from "@vee/sdk";

/** Public, no-auth JSON endpoint: the GitHub API root (a map of endpoint URLs). */
const DEFAULT_URL = "https://api.github.com/";

/** A flattened (title, value) pair derived from the fetched JSON. */
interface Row {
  id: string;
  title: string;
  value: string;
}

/** One-line preview of a value string (collapse whitespace, truncate). */
export function preview(value: string): string {
  const oneLine = value.replace(/\s+/g, " ").trim();
  return oneLine.length > 80 ? oneLine.slice(0, 77) + "…" : oneLine;
}

/** Stringify a JSON value for display (scalars as-is, objects/arrays as JSON). */
function stringify(value: JSONValue): string {
  if (value === null) return "null";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return JSON.stringify(value);
}

/**
 * Flatten a fetched JSON value into display rows. Objects → key rows; arrays →
 * indexed rows; a bare scalar → a single "value" row. Exported for the test.
 */
export function rowsFromJSON(data: JSONValue): Row[] {
  if (Array.isArray(data)) {
    return data.map((v, i) => ({ id: String(i), title: `[${i}]`, value: stringify(v) }));
  }
  if (data !== null && typeof data === "object") {
    return Object.entries(data).map(([k, v]) => ({ id: k, title: k, value: stringify(v) }));
  }
  return [{ id: "value", title: "value", value: stringify(data) }];
}

/** Build a row. Exported for the unit test. */
export function resultRow(row: Row): RenderNode {
  return listItem(
    { key: row.id, id: row.id, title: row.title, subtitle: preview(row.value), icon: "curlybraces" },
    [
      actionPanel({}, [
        action({ actionId: row.id, title: "Copy Value", shortcut: "cmd+enter" }),
      ]),
    ],
  );
}

/** Build the list tree from rows. Exported for the unit test. */
export function resultTree(rows: Row[]): RenderNode {
  if (rows.length === 0) {
    return root({}, [
      list({ key: "api", filtering: false }, [
        empty({
          key: "empty",
          title: "No data",
          description: "The endpoint returned nothing to display.",
          icon: "antenna.radiowaves.left.and.right.slash",
        }),
      ]),
    ]);
  }
  return root({}, [list({ key: "api", filtering: true }, rows.map(resultRow))]);
}

async function parseJsonOk(res: { status: number; text(): Promise<string> }): Promise<JSONValue | undefined> {
  if (res.status < 200 || res.status >= 300) return undefined;
  const body = (await res.text()).trim();
  if (body.length === 0) return undefined;
  try {
    return JSON.parse(body) as JSONValue;
  } catch {
    return undefined;
  }
}

/** Fetch the endpoint + render; render an empty state on any failure. */
async function loadEndpoint(ctx: {
  arguments: Record<string, JSONValue>;
  render: (n: RenderNode) => void;
}): Promise<void> {
  const url = typeof ctx.arguments.url === "string" ? ctx.arguments.url : DEFAULT_URL;
  let rows: Row[] = [];

  onInvokeAction(async (p) => {
    const row = rows.find((r) => r.id === p.actionId);
    if (!row) return;
    try {
      await clipboard().copy({ id: row.id, text: row.value, copiedAt: new Date().toISOString() });
      showToast("success", "Copied", preview(row.value));
    } catch (err) {
      showToast("failure", "Copy failed", String(err));
    }
  });

  try {
    const res = await http().fetch(url, { headers: { Accept: "application/json" } });
    const data = await parseJsonOk(res);
    if (data === undefined) {
      showToast("failure", "API Monitor", `Failed to fetch ${url}`);
      ctx.render(resultTree([]));
      return;
    }
    rows = rowsFromJSON(data);
    ctx.render(resultTree(rows));
  } catch (err) {
    showToast("failure", "API Monitor", `Failed to fetch ${url}`);
    ctx.render(resultTree([]));
    void err;
  }
}

definePlugin({
  commands: {
    view: (ctx) => loadEndpoint(ctx),
  },
});
