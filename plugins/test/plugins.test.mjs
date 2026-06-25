/**
 * Tests for the three real sample plugins (essentials, hacker-news, clipboard):
 *
 *   • each `dist/<id>.js` bundle is a single self-contained IIFE with NO runtime
 *     `require(` / `import ` (i.e. zero externals), exactly like hello-list;
 *   • each bundle evaluates in a JSC-like `node:vm` sandbox (the host's exact
 *     load → read __veePlugin → activate("view") sequence) and renders the
 *     expected `RenderNode` tree, exercising the bridge each plugin needs
 *     (none / vee.http.fetch / vee.clipboard.*); and
 *   • each committed `fixtures/<id>.bundle.js` is in sync with a fresh build.
 *
 * These mirror `bundle.test.mjs` (hello-list) for the new plugins.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const execFileP = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");

const distPath = (id) => resolve(ROOT, "dist", `${id}.js`);
const fixturePath = (id) => resolve(ROOT, "fixtures", `${id}.bundle.js`);

/** Run `node bundle.mjs --once` from the plugins root (builds every plugin). */
async function runBundleOnce() {
  return execFileP(process.execPath, ["bundle.mjs", "--once"], { cwd: ROOT });
}

/**
 * Evaluate a bundle exactly as the host would: fresh context, injected `vee`
 * global + console, run the IIFE, read `__veePlugin`, activate "view", and
 * return the captured render payload plus anything the bridge fakes observed.
 *
 * `opts.canned`    : { url: bodyString } served by vee.http.fetch (records URLs).
 * `opts.clipItems` : items returned by vee.clipboard.history (records copies).
 */
async function evaluateAndRender(id, opts = {}) {
  const code = await readFile(distPath(id), "utf8");
  const canned = opts.canned ?? {};
  const observed = { requested: [], copied: null, toasts: [], invokeHandlers: [] };

  const sandbox = {
    console: { debug() {}, info() {}, log() {}, warn() {}, error() {} },
    vee: {
      pluginId: id,
      render(node) {
        sandbox.__rendered = node;
      },
      setCandidates() {},
      onInvokeAction: (h) => {
        observed.invokeHandlers.push(h);
        return () => {};
      },
      onSearchTextChange: () => () => {},
      onSubmitForm: () => () => {},
      http: {
        fetch: async (url) => {
          observed.requested.push(url);
          const body = canned[url];
          if (body === undefined) throw new Error(`no canned response for ${url}`);
          return {
            status: 200,
            headers: {},
            text: async () => body,
            json: async () => JSON.parse(body),
          };
        },
      },
      storage: { get: async () => undefined, set: async () => {} },
      clipboard: {
        history: async () => opts.clipItems ?? [],
        copy: async (item) => {
          observed.copied = item;
        },
      },
      showToast: (style, title, message) => observed.toasts.push({ style, title, message }),
    },
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: `${id}.js` });

  const reg = sandbox.__veePlugin;
  assert.ok(reg, `${id}: bundle must publish __veePlugin`);
  // The activate handler may be async (fetch/clipboard); await it.
  await reg.activateCommand("view", {
    pluginId: id,
    commandName: "view",
    arguments: {},
    render: (n) => sandbox.vee.render(n),
  });
  assert.ok(sandbox.__rendered, `${id}: activating view must render a tree`);
  // Round-trip through JSON to drop vm-realm prototypes before comparing.
  return {
    rendered: JSON.parse(JSON.stringify(sandbox.__rendered)),
    commandNames: JSON.parse(JSON.stringify(reg.commandNames)),
    observed,
  };
}

/** Assert a built bundle is an IIFE with no runtime require/import. */
function assertSelfContainedIIFE(code, id) {
  assert.ok(code.length > 0, `${id}: bundle must be non-empty`);
  assert.match(code, /\(\(\) => \{|\(function/, `${id}: bundle must be an IIFE`);
  assert.doesNotMatch(code, /(^|[^.\w])require\s*\(/m, `${id}: no runtime require() calls`);
  assert.doesNotMatch(code, /^\s*import[\s{*'"]/m, `${id}: no static import statements`);
  assert.doesNotMatch(code, /[^.\w]import\s*\(/m, `${id}: no dynamic import() calls`);
  assert.doesNotMatch(code, /^\s*export[\s{*]/m, `${id}: no export statements`);
}

// Build all bundles once before the suite touches dist/.
test("bundle --once builds the sample plugins", async () => {
  await runBundleOnce();
  for (const id of ["com.vee.essentials", "com.vee.hacker-news", "com.vee.clipboard"]) {
    const code = await readFile(distPath(id), "utf8");
    assertSelfContainedIIFE(code, id);
  }
});

// ── com.vee.essentials — static list, NO bridges ────────────────────────────

test("essentials renders a static six-item list with expected titles", async () => {
  const { rendered, commandNames } = await evaluateAndRender("com.vee.essentials");
  assert.deepEqual(commandNames, ["view"]);
  assert.equal(rendered.tag, "root");
  const listNode = rendered.children[0];
  assert.equal(listNode.tag, "list");
  assert.equal(listNode.children.length, 6);
  assert.deepEqual(
    listNode.children.map((c) => c.props.title),
    ["Search Files", "Clipboard History", "Calculator", "System Settings", "Capture Screenshot", "Lock Screen"],
  );
  // Each row carries an SF-symbol icon and an action-panel → action with actionId.
  for (const item of listNode.children) {
    assert.equal(item.tag, "list-item");
    assert.equal(typeof item.props.icon, "string");
    const act = item.children[0].children[0];
    assert.equal(act.tag, "action");
    assert.equal(act.props.actionId, item.props.id);
  }
});

// ── com.vee.hacker-news — vee.http.fetch ────────────────────────────────────

test("hacker-news fetches top stories and renders title + score/host", async () => {
  const canned = {
    "https://hacker-news.firebaseio.com/v0/topstories.json": JSON.stringify([1, 2]),
    "https://hacker-news.firebaseio.com/v0/item/1.json": JSON.stringify({
      id: 1, title: "Story One", url: "https://github.com/foo/bar", score: 111, by: "alice",
    }),
    "https://hacker-news.firebaseio.com/v0/item/2.json": JSON.stringify({
      id: 2, title: "Story Two", score: 42, by: "bob",
    }),
  };
  const { rendered, observed } = await evaluateAndRender("com.vee.hacker-news", { canned });
  const listNode = rendered.children[0];
  assert.equal(listNode.children.length, 2);
  assert.deepEqual(
    listNode.children.map((c) => c.props.title),
    ["Story One", "Story Two"],
  );
  assert.deepEqual(
    listNode.children.map((c) => c.props.subtitle),
    ["111 points · github.com", "42 points · news.ycombinator.com"],
  );
  // The story with no url falls back to its HN item permalink in the action.
  assert.match(listNode.children[1].children[0].children[0].props.url, /news\.ycombinator\.com\/item\?id=2/);
  // It really called the API (topstories then each item).
  assert.deepEqual(observed.requested, [
    "https://hacker-news.firebaseio.com/v0/topstories.json",
    "https://hacker-news.firebaseio.com/v0/item/1.json",
    "https://hacker-news.firebaseio.com/v0/item/2.json",
  ]);
});

test("hacker-news renders an empty state (and toasts) on fetch failure", async () => {
  // No canned responses → fetch throws → empty-state + failure toast, no crash.
  const { rendered, observed } = await evaluateAndRender("com.vee.hacker-news", { canned: {} });
  const listNode = rendered.children[0];
  assert.equal(listNode.children[0].tag, "empty-view");
  assert.equal(observed.toasts.length, 1);
  assert.equal(observed.toasts[0].style, "failure");
});

// ── com.vee.clipboard — vee.clipboard.* ─────────────────────────────────────

test("clipboard renders recent items and Copy round-trips to vee.clipboard.copy", async () => {
  const clipItems = [
    { id: "c1", text: "hello clipboard", copiedAt: "2026-06-25T10:00:00Z" },
    { id: "c2", text: "second   item", copiedAt: "2026-06-25T09:00:00Z" },
  ];
  const { rendered, observed } = await evaluateAndRender("com.vee.clipboard", { clipItems });
  const listNode = rendered.children[0];
  assert.equal(listNode.children.length, 2);
  assert.deepEqual(
    listNode.children.map((c) => c.props.title),
    ["hello clipboard", "second item"], // whitespace collapsed in the preview
  );
  // Primary action is "Copy" and carries the item id as actionId.
  const firstAction = listNode.children[0].children[0].children[0];
  assert.equal(firstAction.props.title, "Copy");
  assert.equal(firstAction.props.actionId, "c1");

  // Fire the Copy action for c2 → the EXACT item (original text + copiedAt) is
  // handed to vee.clipboard.copy.
  await observed.invokeHandlers[0]({ pluginId: "com.vee.clipboard", actionId: "c2" });
  assert.deepEqual(observed.copied, { id: "c2", text: "second   item", copiedAt: "2026-06-25T09:00:00Z" });
  assert.equal(observed.toasts.at(-1).style, "success");
});

test("clipboard renders an empty state when history is empty", async () => {
  const { rendered } = await evaluateAndRender("com.vee.clipboard", { clipItems: [] });
  const listNode = rendered.children[0];
  assert.equal(listNode.children[0].tag, "empty-view");
});

// ── committed fixtures stay in sync with a fresh build ──────────────────────

test("committed fixture bundles match freshly built bundles", async () => {
  await runBundleOnce();
  for (const id of ["com.vee.essentials", "com.vee.hacker-news", "com.vee.clipboard"]) {
    const [fresh, fixture] = await Promise.all([
      readFile(distPath(id), "utf8"),
      readFile(fixturePath(id), "utf8"),
    ]);
    assert.equal(fixture, fresh, `fixtures/${id}.bundle.js is stale — re-copy dist/${id}.js`);
  }
});
