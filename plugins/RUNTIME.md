# Vee plugin runtime contract (JS ↔ host)

This document specifies the **exact** contract between a built plugin bundle and
the Vee host (the JavaScriptCore embedder). The host side (`VeeEngine`)
implements every global, bridge, and lifecycle step described here. Every
global, signature, and lifecycle step is normative.

The companion TypeScript types live in `@vee/sdk` (`packages/sdk/src/`). The wire
shapes mirror `Sources/VeeProtocol/*.swift` byte-for-byte. Where this doc and the
Swift protocol disagree, the Swift protocol wins — file a fix here.

---

## 1. Execution model

- Each plugin runs in its own `JSContext` (ideally its own `JSVirtualMachine`),
  out of process from AppKit, exactly as `docs/ARCHITECTURE.md` §2–§3 prescribe.
- JSC has **no module loader and no DOM**. The bundle is a single self-contained
  **IIFE** (built by `bundle.mjs`: `format:"iife"`, `platform:"neutral"`,
  `target:"es2021"`, `bundle:true`, zero externals). There are **no `require`/
  `import` statements at runtime** — everything the plugin needs is either inside
  the IIFE or provided as an injected global.
- The host injects globals **before** evaluating the bundle, evaluates the IIFE,
  then reads the registration the bundle published (§4) and drives it (§5).
- **No React.** Plugins emit plain JSON component trees (`RenderNode`). React may
  later be layered on as an authoring convenience over the same wire format; the
  host contract does not change.

---

## 2. Globals the host MUST inject

Inject these into the context's global object **before** evaluating the bundle.

### 2.1 `console`

A leveled logger. Each call is forwarded to the host as a `plugin.log`
notification (`RPCMethods.log`, params `LogParams`) after stringifying args.

```ts
globalThis.console = {
  debug(...args: unknown[]): void;  // → LogParams.level = "debug"
  info(...args: unknown[]): void;   // → "info"
  log(...args: unknown[]): void;    // → "info"   (log aliases info)
  warn(...args: unknown[]): void;   // → "warn"
  error(...args: unknown[]): void;  // → "error"
};
```

The host SHOULD stringify each argument (objects via `JSON.stringify`, with a
fallback to `String(x)`), join with a space, and set `LogParams.message`.

### 2.2 `vee` — the host bridge

A single object named `vee` implementing the `VeeHost` interface
(`packages/sdk/src/runtime.ts`). **Every member below is required**, with these
exact names and signatures. All `Promise`-returning members settle when the
corresponding JSON-RPC response arrives (bridge calls) or immediately (fire-and-
forget notifications).

```ts
interface VeeHost {
  // Identity
  readonly pluginId: string;            // reverse-DNS id from the manifest

  // Resolved preference values for the active command (the Raycast model), keyed
  // by the `name` you declared in `vee.json`. The host fills this from the user's
  // saved settings + each preference's `default` before invoking the command.
  // Read it via the typed `getPreferenceValues()` accessor (see §2.3).
  readonly preferences: Record<string, JSONValue>;

  // ── Rendering (plugin → host) ────────────────────────────────────────────
  // Submit a complete render tree. The host diffs against the previously
  // rendered tree and emits a `plugin.render` JSON-Patch notification
  // (RPCMethods.render, params RenderParams). Accepts a RenderNode OR its
  // already-projected JSONValue (the SDK normalizes RenderNode → JSONValue
  // before calling this, so the host always receives the canonical wire shape).
  render(node: RenderNode | JSONValue): void;

  // Push the full candidate set for native fuzzy filtering
  // (RPCMethods.setCandidates, params SetCandidatesParams).
  setCandidates(candidates: Candidate[]): void;

  // ── Inbound event registration (host → plugin) ───────────────────────────
  // The host calls the registered handler when the corresponding host→plugin
  // notification arrives. Each returns an unsubscribe function. Registrations
  // are additive; if the plugin registers multiple handlers, the host invokes
  // all of them. See §6 for the dispatch mapping.
  onInvokeAction(handler: (p: InvokeActionParams) => void | Promise<void>): () => void;
  onSearchTextChange(handler: (query: string, p: SearchTextChangeParams) => void | Promise<void>): () => void;
  onSubmitForm(handler: (p: SubmitFormParams) => void | Promise<void>): () => void;

  // ── Bridges (plugin → host; capability-gated, async) ─────────────────────
  // All of the following are installed by the host (JSBridge.installVee) and
  // exposed via accessors in @vee/sdk. Each is gated by the matching field in
  // the plugin's Capabilities (vee.json); a denied call rejects with
  // JSONRPCError.capabilityDenied (-32001).

  readonly http: {
    // Capability-gated by Capabilities.network. The host performs the request
    // natively (URLSession) → bridge.http.fetch (FetchParams → FetchResult).
    // The SDK encodes the request body to base64 and decodes the response body
    // from base64; the plugin-facing façade speaks UTF-8 text / JSON.
    fetch(url: string, init?: {
      method?: string;
      headers?: Record<string, string>;
      body?: string;           // UTF-8; SDK base64-encodes for FetchParams.bodyBase64
    }): Promise<{
      status: number;
      headers: Record<string, string>;
      text(): Promise<string>; // decodes FetchResult.bodyBase64 as UTF-8
      json(): Promise<JSONValue>;
    }>;
  };

  readonly storage: {
    // SWR-backed key/value store. bridge.storage.get / bridge.storage.set
    // (StorageGetParams / StorageSetParams).
    get(key: string): Promise<JSONValue | undefined>;
    set(key: string, value: JSONValue, ttlSeconds?: number): Promise<void>;
  };

  readonly fs: {
    // Capability-gated by Capabilities.filesystem: the path must canonicalize
    // under a declared root (traversal → capabilityDenied). bridge.fs.read /
    // bridge.fs.write (FSReadParams / FSWriteParams). The façade speaks UTF-8;
    // the wire uses base64.
    read(path: string): Promise<string>;
    write(path: string, contents: string): Promise<void>;
    // List the entries directly under `dir` (basenames, not recursive). Same
    // capability gate as read/write. bridge.fs.list (FSListParams → [FSDirEntry]).
    list(dir: string): Promise<{ name: string; isDirectory: boolean }[]>;
  };

  readonly calendar: {
    // Capability-gated by Capabilities.calendar (the app handles the TCC
    // prompt). bridge.calendar.upcoming → CalendarEvent[], soonest first.
    upcoming(): Promise<CalendarEvent[]>;
  };

  readonly keychain: {
    // Capability-gated by Capabilities.keychainNamespaces: a plugin may only
    // touch namespaces it declared. Items are scoped (namespace, account) under
    // the plugin's own id, which is bound natively — never passed from JS.
    // bridge.keychain.get / set / delete (KeychainGet/Set/DeleteParams).
    get(namespace: string, account: string): Promise<string | null>;
    set(namespace: string, account: string, value: string): Promise<void>;
    delete(namespace: string, account: string): Promise<void>;
  };

  readonly clipboard: {
    // Capability-gated by the coarse Capabilities.clipboard boolean. The host
    // captures pasteboard changes behind a privacy filter (concealed /
    // transient / password-manager items are dropped at capture time) and
    // exposes the surviving history. bridge.clipboard.history / .copy
    // (ClipboardHistoryParams / ClipboardItem).
    history(query?: string, limit?: number): Promise<ClipboardItem[]>;
    copy(item: ClipboardItem): Promise<void>;
  };

  // ── System affordances (plugin → host; async) ────────────────────────────
  // open(url) opens a URL in the user's default handler; openApp(bundleId)
  // launches/activates an app. Backed by the host's OpenProviding. These are
  // gated by Capabilities.open (scheme allowlist for open; a "bundleId:"-
  // prefixed allowlist for openApp) — see "Capability enforcement" below.
  open(url: string): Promise<void>;
  openApp(bundleId: string): Promise<void>;

  // ── UI affordances ─────────────────────────────────────────────────────────
  // Show a transient toast (RPCMethods.toast = "plugin.showToast", ToastParams).
  showToast(style: "success" | "failure" | "info", title: string, message?: string): void;

  // Post a SYSTEM notification (RPCMethods.notify = "bridge.notify", NotifyParams).
  // Ungated, like showToast. Delivered to the host's NotificationProviding (a real
  // UNUserNotification on the desktop), NOT routed through the launcher window.
  notify(title: string, body?: string, subtitle?: string): void;
}
```

> **Capability enforcement.** Every bridge is gated by the plugin's
> `Capabilities` (`vee.json`). The host rejects a call to a disallowed resource
> with `JSONRPCError.capabilityDenied` (code `-32001`); the SDK surfaces that as
> a rejected Promise. Mapping:
>
> | Bridge | Capability field | Denied when |
> |---|---|---|
> | `http.fetch` | `network` | host not in the allowlist (`allowsNetworkHost`) |
> | `fs.read` / `fs.write` | `filesystem` | path canonicalizes outside the declared roots |
> | `calendar.upcoming` | `calendar` | `calendar` is `false` |
> | `keychain.*` | `keychainNamespaces` | namespace not declared |
> | `clipboard.*` | `clipboard` | `clipboard` is `false` |
> | `open` | `open` | URL scheme (and, for `http(s)`, host) not allowed (`allowsOpen`) |
> | `openApp` | `open` | bundle id not allowed (`allowsOpenApp`) |
>
> **`open`/`openApp` gating is being added** (closing SEC-1/SEC-2): the
> `Capabilities.open` allowlist and the `allowsOpen` / `allowsOpenApp` checks
> are the in-flight mechanism. Until that lands everywhere, treat `open` as
> default-deny and declare the schemes/bundle ids you need in the manifest.

> **Surface parity.** `@vee/sdk` ships an accessor for every member above
> (`http()`, `storage()`, `fs()` incl. `list`, `calendar()`, `keychain()`,
> `clipboard()`, `open()`, `openApp()`, `showToast()`, `notify()`,
> `getPreferenceValues()`), each typed against the `VeeHost` interface in
> `packages/sdk/src/runtime.ts`. The matching JSON-RPC method-name constants live
> in `RPCMethods` (`types.ts`).

### 2.4 Menu-bar commands (`mode: "menu-bar"`)

A command declared with `"mode": "menu-bar"` runs in the BACKGROUND and renders
into its OWN `NSStatusItem` — a Raycast-style menu-bar extra — not the launcher
window. The host activates it at startup and re-activates it every
`refreshIntervalSeconds` (a timer); the command re-renders on each tick. To update
between ticks, just call `render(...)` again.

The render tree is projected onto the status item like so:
>   • the ROOT node's `title` prop → the status-bar text; its `icon` prop (an
>     SF-Symbol name) → the status-button image;
>   • each `list-item` descendant → a dropdown row (`title`, optional `subtitle`,
>     `actionId`); a node with tag `"separator"` → a divider;
>   • choosing a row sends one `host.invokeAction` carrying that `actionId` —
>     handle it with `onInvokeAction`, exactly as in a launcher view.

Menu-bar commands do NOT appear in the launcher's command list (they live in the
menu bar). They may declare `preferences` and use any capability-gated bridge —
commonly `fs.list` (watch a folder), `http` (poll an API), `open` (act on a row),
and `notify` (surface a change). See `plugins/samples/folder-monitor` for a worked
example.

### 2.3 Preferences — plugin-declared configuration (the Raycast model)

A plugin OWNS its configuration. The host has no built-in notion of any API key
or service: a credential exists only because a plugin DECLARED a preference for
it. Declare preferences in `vee.json`, at the extension level and/or per command:

```json
{
  "id": "com.vee.github",
  "preferences": [
    { "name": "token", "type": "password", "title": "Personal Access Token",
      "description": "A GitHub PAT with the repo scope.", "required": true,
      "placeholder": "ghp_…" }
  ],
  "commands": [
    { "name": "view", "title": "Pull Requests", "mode": "view",
      "preferences": [ { "name": "limit", "type": "textfield", "title": "Max rows", "default": "25" } ] }
  ]
}
```

Each preference has a `name` (the key you read at runtime), a `type`
(`textfield` | `password` | `checkbox` | `dropdown`; `app-picker`/`file`/
`directory` are accepted and render as a textfield for now), a `title`, plus the
optional `description`, `required`, `default`, `placeholder`, `label` (checkbox),
and `data` (dropdown options `{title, value}`). Command preferences merge over
extension preferences of the same `name`.

The host renders a GENERIC form from these in **Settings → Extensions** — there
is no hardcoded, app-side credential roster. `password` values are stored in the
Keychain; everything else in a preferences store. The plugin reads the resolved
values synchronously:

```ts
import { getPreferenceValues } from "@vee/sdk";
const { token } = getPreferenceValues<{ token: string }>();
```

Values are merged with declared `default`s and delivered in
`ActivateParams.preferences` on every activate (also exposed as `ctx.preferences`).
If a command declares a `required` preference the user hasn't set, the host shows
a "Setup required" form (opening that extension's settings) INSTEAD of activating
— so inside a command body a `required` preference is always present.

---

## 3. The render tree (`RenderNode`)

A plugin describes its UI as a tree of `RenderNode`:

```ts
interface RenderNode {
  tag: string;                  // component kind; free string (forward-compatible)
  key?: string;                 // stable identity for keyed children (optional)
  props: { [k: string]: JSONValue };
  children: RenderNode[];
}
```

**Wire projection (canonical form the host receives and diffs):** identical to
Swift's `RenderNode.jsonValue` —

```json
{ "tag": "...", "props": { ... }, "children": [ ... ] }
```

plus `"key": "..."` **only when a key is present** (omitted when absent so a
missing key never produces a spurious JSON-Patch diff). The SDK's
`renderNodeToJSON()` produces exactly this, and `vee.render()` applies it before
handing the tree to the host. The host MUST treat this projection as the source
of truth for diffing.

Core tags (mirror `RenderNode.Tag`): `root`, `list`, `list-item`, `detail`,
`form`, `field`, `action`, `action-panel`, `text`, `empty-view`. Unknown tags
render as an inert container (forward-compatible).

The first render after activation is shipped by the host as a single JSON-Patch
`replace` at path `""` (whole tree); subsequent renders are minimal diffs. The
plugin always calls `vee.render(fullTree)` — diffing is the host's job.

---

## 4. How a bundle registers commands

The bundle calls **`definePlugin`** (or one or more **`registerCommand`** calls)
from `@vee/sdk` at top level. Both publish a registration object to a reserved
global slot the host reads after evaluation:

```ts
globalThis.__veePlugin: RegisteredPlugin | undefined
```

where

```ts
interface RegisteredPlugin {
  commandNames: string[];                                   // every registered command
  activateCommand(name: string, ctx: CommandContext): void | Promise<void>;
}
```

The constant name is exported as `PLUGIN_GLOBAL_KEY === "__veePlugin"`.

Authoring shape:

```ts
import { definePlugin, root, list, listItem } from "@vee/sdk";

definePlugin({
  commands: {
    view: (ctx) => {
      ctx.render(root({}, [ list({}, [ listItem({ id: "1", title: "Hello" }) ]) ]));
    },
  },
});
```

Command names MUST match the `commands[].name` entries in `vee.json`.

---

## 5. Activation lifecycle (host drives the bundle)

1. **Load.** Host creates the context, injects `console` + `vee` (§2), and
   evaluates the IIFE bundle. The bundle's top-level `definePlugin` call runs and
   sets `globalThis.__veePlugin`.
2. **Discover.** Host reads `globalThis.__veePlugin`. If absent, the bundle is
   malformed (raise `JSONRPCError.pluginError`). `commandNames` lists the
   commands available.
3. **Activate** (`plugin.activate`, `ActivateParams`). The host builds a
   `CommandContext` and calls `__veePlugin.activateCommand(commandName, ctx)`:

   ```ts
   interface CommandContext {
     pluginId: string;
     commandName: string;
     arguments: Record<string, JSONValue>;   // from ActivateParams.arguments
     render(node: RenderNode | JSONValue): void; // convenience === vee.render
   }
   ```

   The handler runs and typically calls `ctx.render(tree)` (and/or
   `vee.setCandidates(...)`, registers `vee.onInvokeAction(...)`, etc.). If it
   returns a Promise, the host awaits it before responding to `plugin.activate`.
   A throw/rejection becomes `JSONRPCError.pluginError` (the JS stack rides in
   `data` when available).
4. **Run.** The plugin reacts to host→plugin notifications (§6) by calling its
   registered handlers, re-rendering via `vee.render(...)` as needed.
5. **Deactivate** (`plugin.deactivate`, `DeactivateParams`). The host stops
   delivering events for that command. (The current SDK has no explicit
   deactivate hook; handlers simply stop being invoked. A future
   `onDeactivate` may be added here.)
6. **Reload** (`plugin.reload`, `ReloadParams`). On a rebuilt bundle the host
   tears down the context, creates a fresh one, re-injects globals, re-evaluates
   the new bundle, then re-activates. State is **not** carried as live values;
   persist via `vee.storage` and rehydrate from `ReloadParams.state` if provided
   (see `docs/ARCHITECTURE.md` §4).

---

## 6. Host → plugin event dispatch

When the host receives one of these (it ORIGINATES them toward the plugin), it
invokes the matching registered handlers:

| JSON-RPC method (`RPCMethods`)              | Params                    | Invokes                         |
| ------------------------------------------- | ------------------------- | ------------------------------- |
| `host.invokeAction` (`invokeAction`)        | `InvokeActionParams`      | every `onInvokeAction` handler  |
| `host.onSearchTextChange` (`onSearchTextChange`) | `SearchTextChangeParams` | every `onSearchTextChange` handler (passed `params.query`, then the full params) |
| `host.submitForm` (`submitForm`)            | `SubmitFormParams`        | every `onSubmitForm` handler    |

`InvokeActionParams.actionId` is the `actionId` prop the plugin set on an
`<action>` node (or a `CandidateAction.id`); `targetId` is the id of the
list-item/candidate it fired on, when applicable.

These are JSON-RPC **notifications** (no response). The host does not wait for
the handler's Promise to settle before continuing, but SHOULD surface a handler
rejection as a `plugin.log` error and/or a toast.

---

## 7. Worked example — `com.vee.hello-list`

`samples/hello-list/src/index.ts` registers one `view` command that renders a
static `root → list → 3 list-items` tree. Built to a single IIFE at
`dist/com.vee.hello-list.js` and committed (for the host's tests) at
`fixtures/hello-list.bundle.js`. The exact wire projection the host receives on
activation is captured in `fixtures/hello-list.expected.json`.

Host-side evaluation, end to end (this is precisely what `VeeEngineTests` does
and what `plugins/test/bundle.test.mjs` emulates with `node:vm`):

```
1. create context; inject console + vee (vee.render captures the tree)
2. evaluate dist/com.vee.hello-list.js   (the IIFE; sets __veePlugin)
3. read __veePlugin → commandNames === ["view"]
4. __veePlugin.activateCommand("view", { pluginId, commandName:"view",
                                         arguments:{}, render: vee.render })
5. captured tree === fixtures/hello-list.expected.json
```
