/**
 * Tests: `bundle.mjs --once` produces a single, non-empty, self-contained JS
 * bundle (no runtime `require(` / `import ` statements), the bundle evaluates
 * in a JSC-like sandbox and renders the expected tree, and the committed
 * fixture (hello-list.bundle.js + hello-list.expected.json) is in sync.
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
const PLUGIN_ID = "com.vee.hello-list";
const DIST_BUNDLE = resolve(ROOT, "dist", `${PLUGIN_ID}.js`);
const FIXTURE_BUNDLE = resolve(ROOT, "fixtures", "hello-list.bundle.js");
const EXPECTED_JSON = resolve(ROOT, "fixtures", "hello-list.expected.json");

/** Run `node bundle.mjs --once` from the plugins root. */
async function runBundleOnce() {
  return execFileP(process.execPath, ["bundle.mjs", "--once"], { cwd: ROOT });
}

/**
 * Evaluate a bundle exactly as the host would: fresh context, injected `vee`
 * global + console, run the IIFE, read `__veePlugin`, activate "view", and
 * return the captured render payload (already the wire JSONValue projection).
 */
function evaluateAndRender(code) {
  let rendered = null;
  const sandbox = {
    console: { debug() {}, info() {}, log() {}, warn() {}, error() {} },
    vee: {
      pluginId: PLUGIN_ID,
      render(node) {
        rendered = node;
      },
      setCandidates() {},
      onInvokeAction: () => () => {},
      onSearchTextChange: () => () => {},
      onSubmitForm: () => () => {},
      http: { fetch: async () => { throw new Error("no net"); } },
      storage: { get: async () => undefined, set: async () => {} },
      showToast() {},
    },
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: `${PLUGIN_ID}.js` });

  const reg = sandbox.__veePlugin;
  assert.ok(reg, "bundle must publish __veePlugin");
  reg.activateCommand("view", {
    pluginId: PLUGIN_ID,
    commandName: "view",
    arguments: {},
    render: (n) => sandbox.vee.render(n),
  });
  assert.ok(rendered, "activating the view command must render a tree");
  // Re-hydrate across the realm boundary: objects minted inside the vm context
  // carry that context's prototypes, which trips `deepStrictEqual`. Round-trip
  // through JSON (the wire is JSON anyway) to compare as plain data.
  return {
    rendered: JSON.parse(JSON.stringify(rendered)),
    commandNames: JSON.parse(JSON.stringify(reg.commandNames)),
  };
}

test("bundle --once builds a single non-empty JS file", async () => {
  await runBundleOnce();
  const code = await readFile(DIST_BUNDLE, "utf8");
  assert.ok(code.length > 0, "bundle must be non-empty");
  // It is an IIFE.
  assert.match(code, /\(\(\) => \{|\(function/);
});

test("bundle has no runtime require()/import statements (no externals)", async () => {
  const code = await readFile(DIST_BUNDLE, "utf8");
  // A real call to require(...) — allow a `.require` member access, reject a
  // bare/standalone require( call that would mean an unresolved external.
  assert.doesNotMatch(code, /(^|[^.\w])require\s*\(/m, "no runtime require() calls");
  // ESM import statement / dynamic import / export statement.
  assert.doesNotMatch(code, /^\s*import[\s{*'"]/m, "no static import statements");
  assert.doesNotMatch(code, /[^.\w]import\s*\(/m, "no dynamic import() calls");
  assert.doesNotMatch(code, /^\s*export[\s{*]/m, "no export statements");
});

test("dist bundle evaluates and renders root → list → 3 list-items", async () => {
  const code = await readFile(DIST_BUNDLE, "utf8");
  const { rendered, commandNames } = evaluateAndRender(code);
  assert.deepEqual(commandNames, ["view"]);
  assert.equal(rendered.tag, "root");
  const listNode = rendered.children[0];
  assert.equal(listNode.tag, "list");
  assert.equal(listNode.children.length, 3);
  for (const item of listNode.children) {
    assert.equal(item.tag, "list-item");
  }
});

test("committed fixture bundle matches a freshly built bundle", async () => {
  await runBundleOnce();
  const [fresh, fixture] = await Promise.all([
    readFile(DIST_BUNDLE, "utf8"),
    readFile(FIXTURE_BUNDLE, "utf8"),
  ]);
  assert.equal(
    fixture,
    fresh,
    "fixtures/hello-list.bundle.js is stale — re-copy dist/com.vee.hello-list.js",
  );
});

test("committed expected.json matches what the fixture bundle renders", async () => {
  const [code, expectedRaw] = await Promise.all([
    readFile(FIXTURE_BUNDLE, "utf8"),
    readFile(EXPECTED_JSON, "utf8"),
  ]);
  const { rendered } = evaluateAndRender(code);
  const expected = JSON.parse(expectedRaw);
  assert.deepEqual(rendered, expected);
});
