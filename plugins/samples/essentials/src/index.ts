/**
 * Sample Vee plugin: "Essentials".
 *
 * A STATIC list command that uses NO host bridges — on activation of the `view`
 * command it synchronously renders a `root → list` of six useful entries. Each
 * row is a `list-item` (id/title/subtitle/icon SF-symbol) wrapping an `action`
 * the host echoes back via `host.invokeAction`.
 *
 * Because it renders synchronously and deterministically on activate (no fetch,
 * no clipboard, no storage), it is safe to render live in the launcher and its
 * output is fully reproducible for the engine tests.
 */

import {
  action,
  actionPanel,
  definePlugin,
  list,
  listItem,
  root,
  showToast,
  onInvokeAction,
  type RenderNode,
} from "@vee/sdk";

/** One essential entry. `icon` is an SF Symbol name the host resolves. */
interface Essential {
  id: string;
  title: string;
  subtitle: string;
  icon: string;
}

/** The six static entries. Exported so the test fixture derives from the source. */
export const ESSENTIALS: Essential[] = [
  { id: "search-files", title: "Search Files", subtitle: "Find files by name", icon: "doc.text.magnifyingglass" },
  { id: "clipboard-history", title: "Clipboard History", subtitle: "Browse recent copies", icon: "doc.on.clipboard" },
  { id: "calculator", title: "Calculator", subtitle: "Quick math in the bar", icon: "function" },
  { id: "system-settings", title: "System Settings", subtitle: "Open macOS settings", icon: "gearshape" },
  { id: "screenshot", title: "Capture Screenshot", subtitle: "Snip part of the screen", icon: "camera.viewfinder" },
  { id: "lock-screen", title: "Lock Screen", subtitle: "Lock this Mac now", icon: "lock" },
];

/** Build the static render tree. Pure — also used to derive the test fixture. */
export function essentialsTree(): RenderNode {
  return root({}, [
    list(
      { key: "essentials", filtering: true },
      ESSENTIALS.map((e) =>
        listItem({ key: e.id, id: e.id, title: e.title, subtitle: e.subtitle, icon: e.icon }, [
          actionPanel({}, [
            action({ actionId: e.id, title: "Run", shortcut: "cmd+enter" }),
          ]),
        ]),
      ),
    ),
  ]);
}

definePlugin({
  commands: {
    view: (ctx) => {
      // Surface a toast when a row's action fires. Registration is additive and
      // does not affect the synchronous first render below.
      onInvokeAction((p) => {
        const item = ESSENTIALS.find((e) => e.id === p.actionId);
        showToast("info", item ? item.title : "Essentials", item ? item.subtitle : p.actionId);
      });
      // Synchronous, deterministic first render.
      ctx.render(essentialsTree());
    },
  },
});
