/**
 * Sample Vee plugin: "Hello List".
 *
 * On activation of the `view` command it renders a static tree:
 *   root → list → [list-item, list-item, list-item]
 *
 * It uses only the SDK builders (no React) and the `definePlugin` entry point.
 * The built single-file bundle (dist/com.vee.hello-list.js) is what the host
 * evaluates in JavaScriptCore; VeeEngineTests evaluate the committed fixture
 * copy and assert it yields the tree captured in hello-list.expected.json.
 */

import { definePlugin, list, listItem, root, type RenderNode } from "@vee/sdk";

/** Build the static render tree. Pure — also used to derive the test fixture. */
export function helloListTree(): RenderNode {
  return root({}, [
    list({ key: "main", filtering: true }, [
      listItem({ key: "1", id: "1", title: "First item", subtitle: "The first row" }),
      listItem({ key: "2", id: "2", title: "Second item", subtitle: "The second row" }),
      listItem({ key: "3", id: "3", title: "Third item", subtitle: "The third row" }),
    ]),
  ]);
}

definePlugin({
  commands: {
    view: (ctx) => {
      ctx.render(helloListTree());
    },
  },
});
