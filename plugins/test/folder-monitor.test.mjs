/**
 * Unit tests for the "Folder Monitor" menu-bar sample (com.vee.folder-monitor).
 *
 * These exercise the EXPORTED PURE tree-builders (`monitorTree`, `noFolderTree`)
 * directly — no host, no JSC sandbox — exactly like the github sample exports
 * and tests `pullRequestsTree`. We bundle the sample's TypeScript entry in-memory
 * with esbuild (the same technique `test-support/helpers.mjs` uses for the SDK,
 * since Node's type-stripping does not remap the SDK's `.js` import specifiers)
 * and import the result. The bundle's top-level `definePlugin(...)` only REGISTERS
 * command handlers (it never activates them or touches the host), so importing it
 * is side-effect-free and needs no `vee` global.
 *
 * The host projects a menu-bar tree as: ROOT.props.title → status-bar text,
 * ROOT.props.icon → status icon, each `list-item` descendant → a dropdown row
 * (props title/subtitle/actionId), a `"separator"` node → a divider. The asserts
 * below check that projection contract.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import * as esbuild from "esbuild";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ENTRY = resolve(__dirname, "../samples/folder-monitor/src/index.ts");
const SDK_ENTRY = resolve(__dirname, "../packages/sdk/src/index.ts");

let modPromise;

/** Load the sample's exports as a live ESM module (bundled via esbuild, cached). */
function loadFolderMonitor() {
  if (!modPromise) {
    modPromise = (async () => {
      const result = await esbuild.build({
        entryPoints: [ENTRY],
        bundle: true,
        format: "esm",
        platform: "neutral",
        target: ["es2021"],
        write: false,
        // Map `@vee/sdk` to its source so esbuild inlines it (mirrors bundle.mjs).
        plugins: [
          {
            name: "vee-sdk-alias",
            setup(build) {
              build.onResolve({ filter: /^@vee\/sdk$/ }, () => ({ path: SDK_ENTRY }));
            },
          },
        ],
      });
      const code = result.outputFiles[0].text;
      const dataUrl = "data:text/javascript;base64," + Buffer.from(code).toString("base64");
      return import(dataUrl);
    })();
  }
  return modPromise;
}

/** Collect every `list-item` descendant of a node (depth-first). */
function listItemsOf(node) {
  const out = [];
  const walk = (n) => {
    if (n.tag === "list-item") out.push(n);
    for (const c of n.children ?? []) walk(c);
  };
  walk(node);
  return out;
}

// ── (a) no-folder state ──────────────────────────────────────────────────────

test("noFolderTree: title 'Folder' + a single 'Set a folder' row", async () => {
  const { noFolderTree } = await loadFolderMonitor();
  const tree = noFolderTree();

  // ROOT carries the status-bar text + icon.
  assert.equal(tree.tag, "root");
  assert.equal(tree.props.title, "Folder");
  assert.equal(tree.props.icon, "folder");

  // Exactly one dropdown row, pointing at the settings form, with the noop action.
  const rows = listItemsOf(tree);
  assert.equal(rows.length, 1);
  assert.match(rows[0].props.title, /Set a folder in Settings → Extensions/);
  assert.equal(rows[0].props.actionId, "noop");
});

// ── (b) populated state: 3 files + 1 directory ───────────────────────────────

test("monitorTree: 3 files + 1 dir → title '3', 3 file rows (open:) + a Refresh row", async () => {
  const { monitorTree } = await loadFolderMonitor();
  const entries = [
    { name: "a.txt", isDirectory: false },
    { name: "b.txt", isDirectory: false },
    { name: "c.txt", isDirectory: false },
    { name: "subdir", isDirectory: true },
  ];
  const tree = monitorTree("/Users/you/Downloads", entries);

  // ROOT.title is the non-directory file count (the directory is excluded).
  assert.equal(tree.tag, "root");
  assert.equal(tree.props.title, "3");
  assert.equal(tree.props.icon, "folder");

  const rows = listItemsOf(tree);
  // 3 file rows + the Refresh row (the directory contributes no row).
  assert.equal(rows.length, 4);

  const fileRows = rows.filter((r) => String(r.props.actionId).startsWith("open:"));
  assert.deepEqual(
    fileRows.map((r) => r.props.title),
    ["a.txt", "b.txt", "c.txt"],
  );
  assert.deepEqual(
    fileRows.map((r) => r.props.actionId),
    ["open:a.txt", "open:b.txt", "open:c.txt"],
  );

  // A Refresh row is present with the "refresh" action.
  const refresh = rows.find((r) => r.props.actionId === "refresh");
  assert.ok(refresh, "expected a Refresh row");
  assert.equal(refresh.props.title, "Refresh");

  // A divider separates the files from the Refresh row.
  const list = tree.children[0];
  assert.equal(list.tag, "list");
  assert.ok(
    list.children.some((c) => c.tag === "separator"),
    "expected a separator divider",
  );
});

test("monitorTree: empty folder → title '0' and just the Refresh row", async () => {
  const { monitorTree } = await loadFolderMonitor();
  const tree = monitorTree("/tmp/empty", []);
  assert.equal(tree.props.title, "0");
  const rows = listItemsOf(tree);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].props.actionId, "refresh");
});
