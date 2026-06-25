/**
 * Tests: the SDK builders produce the correct RenderNode JSON, and the
 * `renderNodeToJSON` projection matches the frozen Swift `RenderNode.jsonValue`
 * shape (tag/props/children always present; key omitted unless set).
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { loadSdk } from "../test-support/helpers.mjs";

test("leaf builder: in-memory RenderNode shape", async () => {
  const { listItem } = await loadSdk();
  const n = listItem({ id: "1", title: "A", subtitle: "row" });
  assert.deepEqual(n, {
    tag: "list-item",
    props: { id: "1", title: "A", subtitle: "row" },
    children: [],
  });
  // No `key` field when none supplied.
  assert.ok(!("key" in n));
});

test("key is lifted out of props onto RenderNode.key", async () => {
  const { listItem } = await loadSdk();
  const n = listItem({ key: "k1", id: "1", title: "A" });
  assert.equal(n.key, "k1");
  // key must NOT remain duplicated inside props.
  assert.ok(!("key" in n.props));
  assert.deepEqual(n.props, { id: "1", title: "A" });
});

test("container builders nest children (single or array)", async () => {
  const { root, list, listItem } = await loadSdk();
  const single = list({}, listItem({ title: "only" }));
  assert.equal(single.children.length, 1);

  const tree = root({}, [list({}, [listItem({ title: "a" }), listItem({ title: "b" })])]);
  assert.equal(tree.tag, "root");
  assert.equal(tree.children[0].tag, "list");
  assert.equal(tree.children[0].children.length, 2);
});

test("Tags constants mirror the frozen core tag set", async () => {
  const { Tags } = await loadSdk();
  assert.deepEqual(Tags, {
    root: "root",
    list: "list",
    listItem: "list-item",
    detail: "detail",
    form: "form",
    field: "field",
    action: "action",
    actionPanel: "action-panel",
    text: "text",
    empty: "empty-view",
  });
});

test("renderNodeToJSON matches Swift RenderNode.jsonValue projection", async () => {
  const { root, list, listItem, renderNodeToJSON } = await loadSdk();
  const tree = root({}, [
    list({ key: "main", filtering: true }, [
      listItem({ key: "1", id: "1", title: "First item", subtitle: "The first row" }),
    ]),
  ]);
  const json = renderNodeToJSON(tree);

  // Root: tag/props/children present, key OMITTED (was never set).
  assert.deepEqual(Object.keys(json).sort(), ["children", "props", "tag"]);
  assert.equal(json.tag, "root");

  // List: key PRESENT (was set); props carry only non-key props.
  const listJson = json.children[0];
  assert.equal(listJson.key, "main");
  assert.deepEqual(listJson.props, { filtering: true });

  // Leaf: children is an empty array (always present), key present.
  const itemJson = listJson.children[0];
  assert.deepEqual(itemJson.children, []);
  assert.equal(itemJson.key, "1");
  assert.deepEqual(itemJson.props, { id: "1", title: "First item", subtitle: "The first row" });
});

test("action builder carries actionId for host echo-back", async () => {
  const { action } = await loadSdk();
  const a = action({ actionId: "open", title: "Open", shortcut: "cmd+enter" });
  assert.equal(a.tag, "action");
  assert.equal(a.props.actionId, "open");
});

test("definePlugin publishes __veePlugin with command names", async () => {
  const sdk = await loadSdk();
  // Emulate the host global so render() inside a command does not throw.
  let rendered = null;
  globalThis.vee = {
    pluginId: "test",
    render: (n) => {
      rendered = n;
    },
    setCandidates() {},
    onInvokeAction: () => () => {},
    onSearchTextChange: () => () => {},
    onSubmitForm: () => () => {},
    http: { fetch: async () => { throw new Error("no net"); } },
    storage: { get: async () => undefined, set: async () => {} },
    showToast() {},
  };
  try {
    const reg = sdk.definePlugin({
      commands: {
        view: (ctx) => ctx.render(sdk.root({}, [sdk.text({ value: "hi" })])),
      },
    });
    assert.deepEqual(reg.commandNames, ["view"]);
    assert.equal(globalThis.__veePlugin, reg);

    await reg.activateCommand("view", {
      pluginId: "test",
      commandName: "view",
      arguments: {},
      render: (n) => globalThis.vee.render(n),
    });
    assert.equal(rendered.tag, "root");
    assert.equal(rendered.children[0].tag, "text");
  } finally {
    delete globalThis.vee;
    delete globalThis.__veePlugin;
  }
});
