/**
 * Tests for the five additional sample plugins (github, jira, meetings, api,
 * snippets), mirroring `plugins.test.mjs`:
 *
 *   • each `dist/<id>.js` bundle is a single self-contained IIFE with NO runtime
 *     `require(` / `import ` (zero externals);
 *   • each bundle evaluates in a JSC-like `node:vm` sandbox (the host's exact
 *     load → read __veePlugin → activate("view") sequence) and renders the
 *     expected `RenderNode` tree for a representative state, exercising the
 *     bridge each plugin needs (vee.keychain / vee.http / vee.calendar /
 *     vee.storage / vee.clipboard / vee.open); and
 *   • each committed `fixtures/<id>.bundle.js` is in sync with a fresh build.
 *
 * The bridge fakes here mirror how the hacker-news/clipboard tests fake bridges,
 * extended with the NEW accessors the SDK now exposes.
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

const NEW_IDS = ["com.vee.github", "com.vee.jira", "com.vee.meetings", "com.vee.api", "com.vee.snippets"];

const distPath = (id) => resolve(ROOT, "dist", `${id}.js`);
const fixturePath = (id) => resolve(ROOT, "fixtures", `${id}.bundle.js`);

/** Run `node bundle.mjs --once` from the plugins root (builds every plugin). */
async function runBundleOnce() {
  return execFileP(process.execPath, ["bundle.mjs", "--once"], { cwd: ROOT });
}

/**
 * Evaluate a bundle exactly as the host would, with a fully-faked `vee` global.
 *
 * opts:
 *   canned     : { url: bodyString } served by vee.http.fetch (records requests).
 *   keychain   : { "namespace/account": value } seeding vee.keychain.get.
 *   preferences: plain { name: value } map the host resolves from the plugin's
 *                declared `preferences` (read via getPreferenceValues()).
 *   events     : CalendarEvent[] returned by vee.calendar.upcoming().
 *   storage    : initial { key: value } map for vee.storage (mutated on set).
 *   arguments  : activation arguments passed to the command.
 */
async function evaluateAndRender(id, opts = {}) {
  const code = await readFile(distPath(id), "utf8");
  const canned = opts.canned ?? {};
  const kc = { ...(opts.keychain ?? {}) };
  const prefs = { ...(opts.preferences ?? {}) };
  const kvStore = { ...(opts.storage ?? {}) };
  const observed = {
    requested: [],
    fetchInits: [],
    opened: [],
    openedApps: [],
    copied: null,
    toasts: [],
    invokeHandlers: [],
    submitHandlers: [],
    keychainSets: [],
    keychainDeletes: [],
    storageSets: [],
  };

  const sandbox = {
    console: { debug() {}, info() {}, log() {}, warn() {}, error() {} },
    vee: {
      pluginId: id,
      // Resolved preference values the host injects from the plugin's declared
      // `preferences` (the Raycast model). getPreferenceValues() reads this.
      preferences: prefs,
      render(node) {
        sandbox.__rendered = node;
      },
      setCandidates() {},
      onInvokeAction: (h) => {
        observed.invokeHandlers.push(h);
        return () => {};
      },
      onSearchTextChange: () => () => {},
      onSubmitForm: (h) => {
        observed.submitHandlers.push(h);
        return () => {};
      },
      http: {
        fetch: async (url, init) => {
          observed.requested.push(url);
          observed.fetchInits.push(init ?? null);
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
      storage: {
        get: async (key) => (key in kvStore ? kvStore[key] : undefined),
        set: async (key, value) => {
          kvStore[key] = value;
          observed.storageSets.push({ key, value });
        },
      },
      fs: {
        read: async () => "",
        write: async () => {},
      },
      calendar: {
        upcoming: async () => opts.events ?? [],
      },
      keychain: {
        get: async (namespace, account) => {
          const k = `${namespace}/${account}`;
          return k in kc ? kc[k] : null;
        },
        set: async (namespace, account, value) => {
          kc[`${namespace}/${account}`] = value;
          observed.keychainSets.push({ namespace, account, value });
        },
        delete: async (namespace, account) => {
          delete kc[`${namespace}/${account}`];
          observed.keychainDeletes.push({ namespace, account });
        },
      },
      clipboard: {
        history: async () => [],
        copy: async (item) => {
          observed.copied = item;
        },
      },
      open: async (url) => {
        observed.opened.push(url);
      },
      openApp: async (bundleId) => {
        observed.openedApps.push(bundleId);
      },
      showToast: (style, title, message) => observed.toasts.push({ style, title, message }),
    },
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: `${id}.js` });

  const reg = sandbox.__veePlugin;
  assert.ok(reg, `${id}: bundle must publish __veePlugin`);
  await reg.activateCommand("view", {
    pluginId: id,
    commandName: "view",
    arguments: opts.arguments ?? {},
    render: (n) => sandbox.vee.render(n),
  });
  assert.ok(sandbox.__rendered, `${id}: activating view must render a tree`);
  return {
    rendered: JSON.parse(JSON.stringify(sandbox.__rendered)),
    commandNames: JSON.parse(JSON.stringify(reg.commandNames)),
    observed,
    kc,
    kvStore,
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

/** Find the first list node under the rendered root. */
function listOf(rendered) {
  assert.equal(rendered.tag, "root");
  const node = rendered.children[0];
  assert.equal(node.tag, "list");
  return node;
}

// ── all five bundles are self-contained IIFEs ───────────────────────────────

test("bundle --once builds the five new sample plugins as self-contained IIFEs", async () => {
  await runBundleOnce();
  for (const id of NEW_IDS) {
    const code = await readFile(distPath(id), "utf8");
    assertSelfContainedIIFE(code, id);
  }
});

// ── com.vee.github — getPreferenceValues (token) + vee.http + vee.open ───────

test("github renders an add-token empty state when the token preference is blank", async () => {
  // A required preference is normally host-gated, but the plugin still keeps a
  // defensive empty state for a blank value.
  const { rendered, observed } = await evaluateAndRender("com.vee.github", {
    preferences: { token: "" },
  });
  const listNode = listOf(rendered);
  assert.equal(listNode.children[0].tag, "empty-view");
  assert.match(listNode.children[0].props.title, /Add a GitHub token/);
  // The empty state points users at the settings form, not the keychain.
  assert.match(listNode.children[0].props.description, /Settings → Extensions → GitHub/);
  // Never hits the network without a token.
  assert.deepEqual(observed.requested, []);
});

test("github also empty-states when no token preference is present at all", async () => {
  const { rendered, observed } = await evaluateAndRender("com.vee.github", { preferences: {} });
  const listNode = listOf(rendered);
  assert.equal(listNode.children[0].tag, "empty-view");
  assert.match(listNode.children[0].props.title, /Add a GitHub token/);
  assert.deepEqual(observed.requested, []);
});

test("github fetches open PRs with a Bearer token and Open invokes vee.open", async () => {
  const canned = {
    "https://api.github.com/search/issues?q=is:open+is:pr+author:@me": JSON.stringify({
      items: [
        {
          id: 101,
          number: 7,
          title: "Fix the thing",
          html_url: "https://github.com/acme/widgets/pull/7",
          repository_url: "https://api.github.com/repos/acme/widgets",
          draft: false,
        },
        {
          id: 102,
          number: 9,
          title: "WIP refactor",
          html_url: "https://github.com/acme/gadgets/pull/9",
          repository_url: "https://api.github.com/repos/acme/gadgets",
          draft: true,
        },
      ],
    }),
  };
  const { rendered, observed } = await evaluateAndRender("com.vee.github", {
    preferences: { token: "ghp_secret" },
    canned,
  });
  const listNode = listOf(rendered);
  assert.equal(listNode.children.length, 2);
  assert.deepEqual(
    listNode.children.map((c) => c.props.title),
    ["Fix the thing", "WIP refactor"],
  );
  assert.deepEqual(
    listNode.children.map((c) => c.props.subtitle),
    ["acme/widgets #7 · Open", "acme/gadgets #9 · Draft"],
  );
  // Sent the Authorization + Accept headers.
  const init = observed.fetchInits[0];
  assert.equal(init.headers.Authorization, "Bearer ghp_secret");
  assert.equal(init.headers.Accept, "application/vnd.github+json");

  // Fire the Open action for PR 102 → vee.open gets its html_url.
  await observed.invokeHandlers[0]({ pluginId: "com.vee.github", actionId: "102" });
  assert.deepEqual(observed.opened, ["https://github.com/acme/gadgets/pull/9"]);
});

test("github empty-states (and toasts) on a fetch failure", async () => {
  const { rendered, observed } = await evaluateAndRender("com.vee.github", {
    preferences: { token: "ghp_secret" },
    canned: {}, // fetch throws
  });
  const listNode = listOf(rendered);
  assert.equal(listNode.children[0].tag, "empty-view");
  assert.equal(observed.toasts.at(-1).style, "failure");
});

// ── com.vee.jira — getPreferenceValues (3 prefs) + vee.http (POST) + vee.open ─

test("jira empty-states when a required preference is blank", async () => {
  const { rendered, observed } = await evaluateAndRender("com.vee.jira", {
    preferences: { email: "me@x.com" }, // missing site + token
  });
  const listNode = listOf(rendered);
  assert.equal(listNode.children[0].tag, "empty-view");
  assert.match(listNode.children[0].props.title, /Add your Jira credentials/);
  // The empty state points users at the settings form, not the keychain.
  assert.match(listNode.children[0].props.description, /Settings → Extensions → Jira/);
  assert.deepEqual(observed.requested, []);
});

test("jira POSTs the JQL search with Basic auth and renders issues; Open works", async () => {
  const url = "https://acme.atlassian.net/rest/api/3/search/jql";
  const canned = {
    [url]: JSON.stringify({
      issues: [
        { id: "1001", key: "ENG-1", fields: { summary: "Build the widget", status: { name: "In Progress" } } },
        { id: "1002", key: "ENG-2", fields: { summary: "Ship the gadget", status: { name: "To Do" } } },
      ],
    }),
  };
  const { rendered, observed } = await evaluateAndRender("com.vee.jira", {
    preferences: { site: "acme.atlassian.net", email: "me@x.com", token: "tok" },
    canned,
  });
  const listNode = listOf(rendered);
  assert.equal(listNode.children.length, 2);
  assert.deepEqual(
    listNode.children.map((c) => c.props.title),
    ["Build the widget", "Ship the gadget"],
  );
  assert.deepEqual(
    listNode.children.map((c) => c.props.subtitle),
    ["ENG-1 · In Progress", "ENG-2 · To Do"],
  );
  // POST with a Basic auth header carrying base64(email:token) and JQL body.
  const init = observed.fetchInits[0];
  assert.equal(init.method, "POST");
  assert.equal(init.headers.Authorization, `Basic ${Buffer.from("me@x.com:tok").toString("base64")}`);
  assert.match(init.body, /statusCategory != Done/);

  // Open ENG-2 → /browse/ENG-2 on the configured site.
  await observed.invokeHandlers[0]({ pluginId: "com.vee.jira", actionId: "1002" });
  assert.deepEqual(observed.opened, ["https://acme.atlassian.net/browse/ENG-2"]);
});

// ── com.vee.meetings — vee.calendar + vee.open ───────────────────────────────

test("meetings renders events with a start subtitle and Join opens the meetingURL", async () => {
  const events = [
    { id: "e1", title: "Standup", start: "2026-06-25T14:05:00Z", end: "2026-06-25T14:20:00Z", meetingURL: "https://meet.example/abc" },
    { id: "e2", title: "Focus time", start: "2026-06-25T16:00:00Z", end: "2026-06-25T17:00:00Z" },
  ];
  const { rendered, observed } = await evaluateAndRender("com.vee.meetings", { events });
  const listNode = listOf(rendered);
  assert.equal(listNode.children.length, 2);
  assert.deepEqual(
    listNode.children.map((c) => c.props.title),
    ["Standup", "Focus time"],
  );
  // Deterministic UTC start label.
  assert.equal(listNode.children[0].props.subtitle, "Thu 14:05");
  // The event with a meetingURL has a Join action; the one without has none.
  assert.equal(listNode.children[0].children.length, 1);
  assert.equal(listNode.children[1].children.length, 0);

  // Join Standup → opens its meetingURL.
  await observed.invokeHandlers[0]({ pluginId: "com.vee.meetings", actionId: "e1" });
  assert.deepEqual(observed.opened, ["https://meet.example/abc"]);
});

test("meetings renders an empty state when there are no events", async () => {
  const { rendered } = await evaluateAndRender("com.vee.meetings", { events: [] });
  const listNode = listOf(rendered);
  assert.equal(listNode.children[0].tag, "empty-view");
});

// ── com.vee.api — vee.http (generic JSON) + vee.clipboard ────────────────────

test("api fetches the default endpoint and renders a row per JSON key; Copy works", async () => {
  const canned = {
    "https://api.github.com/": JSON.stringify({
      current_user_url: "https://api.github.com/user",
      emojis_url: "https://api.github.com/emojis",
    }),
  };
  const { rendered, observed } = await evaluateAndRender("com.vee.api", { canned });
  const listNode = listOf(rendered);
  assert.deepEqual(
    listNode.children.map((c) => c.props.title),
    ["current_user_url", "emojis_url"],
  );
  assert.deepEqual(
    listNode.children.map((c) => c.props.subtitle),
    ["https://api.github.com/user", "https://api.github.com/emojis"],
  );
  // Default endpoint was hit.
  assert.deepEqual(observed.requested, ["https://api.github.com/"]);

  // Copy the first row → its value goes to vee.clipboard.copy.
  await observed.invokeHandlers[0]({ pluginId: "com.vee.api", actionId: "current_user_url" });
  assert.equal(observed.copied.text, "https://api.github.com/user");
  assert.equal(observed.toasts.at(-1).style, "success");
});

test("api honors a configurable endpoint argument", async () => {
  const url = "https://api.github.com/zen";
  const canned = { [url]: JSON.stringify(["a", "b"]) };
  const { rendered, observed } = await evaluateAndRender("com.vee.api", { canned, arguments: { url } });
  assert.deepEqual(observed.requested, [url]);
  const listNode = listOf(rendered);
  assert.deepEqual(
    listNode.children.map((c) => c.props.title),
    ["[0]", "[1]"],
  );
});

test("api empty-states (and toasts) on a fetch failure", async () => {
  const { rendered, observed } = await evaluateAndRender("com.vee.api", { canned: {} });
  const listNode = listOf(rendered);
  assert.equal(listNode.children[0].tag, "empty-view");
  assert.equal(observed.toasts.at(-1).style, "failure");
});

// ── com.vee.snippets — vee.storage (persistence) + vee.clipboard ─────────────

test("snippets renders stored snippets and Copy round-trips to vee.clipboard.copy", async () => {
  const { rendered, observed } = await evaluateAndRender("com.vee.snippets", {
    storage: { snippets: [{ id: "a", title: "Greeting", text: "hello world" }] },
  });
  const listNode = listOf(rendered);
  // First child is the add-snippet form; then one row per snippet.
  assert.equal(listNode.children[0].tag, "form");
  const row = listNode.children[1];
  assert.equal(row.tag, "list-item");
  assert.equal(row.props.title, "Greeting");
  // Primary action is Copy carrying a "copy:<id>" actionId.
  assert.equal(row.children[0].children[0].props.actionId, "copy:a");

  await observed.invokeHandlers[0]({ pluginId: "com.vee.snippets", actionId: "copy:a" });
  assert.equal(observed.copied.text, "hello world");
  assert.equal(observed.toasts.at(-1).style, "success");
});

test("snippets renders an empty state and persists a new snippet on form submit", async () => {
  const { rendered, observed, kvStore } = await evaluateAndRender("com.vee.snippets", { storage: {} });
  const listNode = listOf(rendered);
  // Add form is present; an empty-view stands in for the (empty) snippet list.
  assert.equal(listNode.children[0].tag, "form");
  assert.equal(listNode.children[1].tag, "empty-view");

  // Submit the add form → snippet is appended and persisted to vee.storage.
  await observed.submitHandlers[0]({
    pluginId: "com.vee.snippets",
    actionId: "add",
    values: { title: "Sig", text: "Best,\nNav" },
  });
  assert.equal(observed.storageSets.length, 1);
  assert.equal(observed.storageSets[0].key, "snippets");
  assert.equal(kvStore.snippets.length, 1);
  assert.equal(kvStore.snippets[0].title, "Sig");
  assert.equal(observed.toasts.at(-1).style, "success");
});

test("snippets deletes a snippet and persists the smaller set", async () => {
  const { observed, kvStore } = await evaluateAndRender("com.vee.snippets", {
    storage: { snippets: [{ id: "a", title: "A", text: "aaa" }, { id: "b", title: "B", text: "bbb" }] },
  });
  await observed.invokeHandlers[0]({ pluginId: "com.vee.snippets", actionId: "delete:a" });
  // kvStore.snippets was minted inside the vm realm; round-trip to drop its
  // realm prototypes before comparing as plain data (deepStrictEqual is strict).
  const remainingIds = JSON.parse(JSON.stringify(kvStore.snippets)).map((s) => s.id);
  assert.deepEqual(remainingIds, ["b"]);
  assert.equal(observed.toasts.at(-1).style, "success");
});

// ── committed fixtures stay in sync with a fresh build ──────────────────────

test("committed fixture bundles match freshly built bundles (new plugins)", async () => {
  await runBundleOnce();
  for (const id of NEW_IDS) {
    const [fresh, fixture] = await Promise.all([
      readFile(distPath(id), "utf8"),
      readFile(fixturePath(id), "utf8"),
    ]);
    assert.equal(fixture, fresh, `fixtures/${id}.bundle.js is stale — re-copy dist/${id}.js`);
  }
});
