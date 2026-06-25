/**
 * Vee wire contract — TypeScript mirror of `Sources/VeeProtocol/*.swift`.
 *
 * These types are hand-written to match the FROZEN Swift wire format byte for
 * byte. They are the single source of truth on the JS side; if the Swift
 * protocol changes, change these in lockstep. Nothing here imports a runtime —
 * it is types + plain string/number constants only, so it bundles to nothing.
 *
 * Cross-references (Swift → TS):
 *   JSONValue.swift     → JSONValue
 *   RenderNode.swift    → RenderNode, Tags
 *   JSONPatch.swift     → PatchOp, PatchKind, JSONPatchDocument
 *   JSONRPC.swift       → JSONRPC* envelopes, JSONRPCID, JSONRPCError
 *   RPCMethods.swift    → RPCMethods + the *Params/*Result payloads
 *   Candidate.swift     → Candidate, CandidateAction
 *   Manifest.swift      → PluginManifest, PluginCommand, Capabilities
 */

// ───────────────────────────────────────────────────────────────────────────
// JSONValue  (Sources/VeeProtocol/JSONValue.swift)
// ───────────────────────────────────────────────────────────────────────────

/**
 * Any JSON value. Mirrors the Swift `JSONValue` enum, which encodes to natural
 * JSON with no type tags — so in TS it is just the structural JSON union.
 * NOTE: Swift stores every number as `Double`; integers round-trip exactly
 * within ±2^53. Do not rely on bigint precision across the wire.
 */
export type JSONValue =
  | null
  | boolean
  | number
  | string
  | JSONValue[]
  | { [key: string]: JSONValue };

/** A JSON object map, the shape of `RenderNode.props`. */
export type JSONObject = { [key: string]: JSONValue };

// ───────────────────────────────────────────────────────────────────────────
// RenderNode  (Sources/VeeProtocol/RenderNode.swift)
// ───────────────────────────────────────────────────────────────────────────

/**
 * One node in the declarative render tree a plugin emits. React-agnostic by
 * design: a `tag`, an optional stable `key`, a heterogeneous `props` bag, and
 * ordered `children`. The host never sees React — only this tree and JSON-Patch
 * diffs of its `jsonValue` projection.
 *
 * WIRE PROJECTION (must match `RenderNode.jsonValue` in Swift):
 *   `{ "tag": string, "props": {...}, "children": [...] }`
 *   plus `"key": string` ONLY when key is present (omitted when undefined so an
 *   absent/null key never produces a spurious JSON-Patch diff).
 * Use `renderNodeToJSON()` (dom.ts) to produce that exact projection.
 */
export interface RenderNode {
  /** Component kind. Free string so the wire never changes to add components. */
  tag: string;
  /** Stable identity for keyed children (maps to React `key`). Optional. */
  key?: string;
  /** Heterogeneous properties: title, subtitle, icon, actionId, placeholder… */
  props: JSONObject;
  /** Ordered children. */
  children: RenderNode[];
}

/**
 * Canonical core component tags. Mirrors `RenderNode.Tag` in Swift. Plugins MAY
 * emit other tags; the host renders unknown tags as an inert container
 * (forward-compatible).
 */
export const Tags = {
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
} as const;

export type Tag = (typeof Tags)[keyof typeof Tags];

// ───────────────────────────────────────────────────────────────────────────
// JSON Patch  (Sources/VeeProtocol/JSONPatch.swift)  — RFC 6902
// ───────────────────────────────────────────────────────────────────────────

/** RFC 6902 operation discriminator. Mirrors `PatchOp.Kind`. */
export type PatchKind = "add" | "remove" | "replace" | "move" | "copy" | "test";

/**
 * A single RFC 6902 operation over a JSONValue document. `path`/`from` are
 * RFC 6901 JSON Pointers (`""` = whole doc, trailing `/-` = array append).
 * `value` is required for add/replace/test; `from` for move/copy. Both are
 * omitted from the encoded form when undefined (Swift uses `encodeIfPresent`)
 * so patches stay minimal and compare cleanly.
 */
export interface PatchOp {
  op: PatchKind;
  path: string;
  value?: JSONValue;
  from?: string;
}

/** An ordered array of operations, applied in sequence. */
export type JSONPatchDocument = PatchOp[];

// ───────────────────────────────────────────────────────────────────────────
// JSON-RPC 2.0 envelopes  (Sources/VeeProtocol/JSONRPC.swift)
// ───────────────────────────────────────────────────────────────────────────

/** JSON-RPC id: string or integer per spec. */
export type JSONRPCID = string | number;

/** A method invocation expecting a response (`id` present). */
export interface JSONRPCRequest {
  jsonrpc: "2.0";
  id: JSONRPCID;
  method: string;
  params?: JSONValue;
}

/** A one-way message with no response (`id` absent). */
export interface JSONRPCNotification {
  jsonrpc: "2.0";
  method: string;
  params?: JSONValue;
}

/** JSON-RPC error object. */
export interface JSONRPCError {
  code: number;
  message: string;
  data?: JSONValue;
}

/** A response to a request. Exactly one of `result`/`error` is set. */
export interface JSONRPCResponse {
  jsonrpc: "2.0";
  /** null id permitted only for pre-id parse errors. */
  id: JSONRPCID | null;
  result?: JSONValue;
  error?: JSONRPCError;
}

/** Any inbound frame. Branch on the presence of fields to discriminate. */
export type JSONRPCMessage =
  | JSONRPCRequest
  | JSONRPCNotification
  | JSONRPCResponse;

/** Standard + Vee-reserved JSON-RPC error codes (mirror `JSONRPCError` statics). */
export const JSONRPCErrorCode = {
  parseError: -32700,
  invalidRequest: -32600,
  methodNotFound: -32601,
  invalidParams: -32602,
  internalError: -32603,
  /** Vee: a plugin threw / rejected. `data` carries the JS stack when available. */
  pluginError: -32000,
  /** Vee: a bridge call was denied by the capability manifest. */
  capabilityDenied: -32001,
} as const;

// ───────────────────────────────────────────────────────────────────────────
// RPC method names + payloads  (Sources/VeeProtocol/RPCMethods.swift)
// ───────────────────────────────────────────────────────────────────────────

/**
 * The frozen host↔plugin method catalog. Names are the wire contract. Comments
 * mark direction and whether the message is a request or a notification.
 */
export const RPCMethods = {
  // Host → Plugin (lifecycle)
  /** Request host→plugin. Params: ActivateParams. Result: empty. */
  activate: "plugin.activate",
  /** Request host→plugin. Params: DeactivateParams. */
  deactivate: "plugin.deactivate",
  /** Request host→plugin. Params: ReloadParams. Bundle re-eval'd; rehydrate. */
  reload: "plugin.reload",
  /** Notification host→plugin. Params: SearchTextChangeParams. */
  onSearchTextChange: "host.onSearchTextChange",
  /** Notification host→plugin. Params: InvokeActionParams. */
  invokeAction: "host.invokeAction",
  /** Notification host→plugin. Params: SubmitFormParams. */
  submitForm: "host.submitForm",

  // Plugin → Host
  /** Notification plugin→host. Params: RenderParams. THE hot path. */
  render: "plugin.render",
  /** Notification plugin→host. Params: SetCandidatesParams. */
  setCandidates: "plugin.setCandidates",
  /** Notification plugin→host. Params: LogParams. */
  log: "plugin.log",
  /** Notification plugin→host. Params: ToastParams. */
  toast: "plugin.showToast",

  // Plugin → Host (bridge requests — capability-gated, expect a response)
  /** Request plugin→host. Params: FetchParams. Result: FetchResult. */
  httpFetch: "bridge.http.fetch",
  fsRead: "bridge.fs.read",
  fsWrite: "bridge.fs.write",
  keychainGet: "bridge.keychain.get",
  keychainSet: "bridge.keychain.set",
  keychainDelete: "bridge.keychain.delete",
  clipboardHistory: "bridge.clipboard.history",
  clipboardCopy: "bridge.clipboard.copy",
  calendarUpcoming: "bridge.calendar.upcoming",
  storageGet: "bridge.storage.get",
  storageSet: "bridge.storage.set",
} as const;

export type RPCMethod = (typeof RPCMethods)[keyof typeof RPCMethods];

// ── Lifecycle payloads ──────────────────────────────────────────────────────

export interface ActivateParams {
  pluginId: string;
  commandName: string;
  /** Arguments passed from the launcher (e.g. a query argument). */
  arguments: Record<string, JSONValue>;
}

export interface DeactivateParams {
  pluginId: string;
  commandName: string;
}

export interface ReloadParams {
  pluginId: string;
  /** Opaque JSON state preserved across a context swap; rehydrate from it. */
  state?: JSONValue;
}

export interface SearchTextChangeParams {
  pluginId: string;
  query: string;
}

export interface InvokeActionParams {
  pluginId: string;
  /** The `actionId` prop the plugin attached to the `<action>` node. */
  actionId: string;
  /** The id of the candidate/list-item the action fired on, if any. */
  targetId?: string;
}

export interface SubmitFormParams {
  pluginId: string;
  actionId: string;
  /** Field name → submitted value. */
  values: Record<string, JSONValue>;
}

// ── Plugin → host payloads ───────────────────────────────────────────────────

export interface RenderParams {
  pluginId: string;
  /** Monotonic render sequence number; host ignores out-of-order frames. */
  revision: number;
  /** JSON-Patch diff against the previously-rendered tree (RFC 6902). */
  patch: JSONPatchDocument;
}

export interface SetCandidatesParams {
  pluginId: string;
  candidates: Candidate[];
}

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface LogParams {
  pluginId: string;
  level: LogLevel;
  message: string;
}

export type ToastStyle = "success" | "failure" | "info";

export interface ToastParams {
  pluginId: string;
  style: ToastStyle;
  title: string;
  message?: string;
}

// ── Bridge payloads ──────────────────────────────────────────────────────────

export interface FetchParams {
  url: string;
  method: string;
  headers: Record<string, string>;
  /** Base64-encoded body, or undefined. Base64 keeps binary bodies JSON-safe. */
  bodyBase64?: string;
}

export interface FetchResult {
  status: number;
  headers: Record<string, string>;
  bodyBase64: string;
}

export interface FSReadParams {
  path: string;
}
export interface FSWriteParams {
  path: string;
  contentsBase64: string;
}

export interface KeychainGetParams {
  /** Keychain namespace the plugin declared in `capabilities.keychainNamespaces`. */
  namespace: string;
  /** Account/key within the namespace. */
  account: string;
}
export interface KeychainSetParams {
  namespace: string;
  account: string;
  value: string;
}
export interface KeychainDeleteParams {
  namespace: string;
  account: string;
}

export interface ClipboardHistoryParams {
  query: string;
  limit: number;
}
export interface ClipboardItem {
  id: string;
  text: string;
  /** ISO-8601 date string (Swift encodes `Date`; host JSONEncoder dateStrategy). */
  copiedAt: string;
}

export interface CalendarEvent {
  id: string;
  title: string;
  start: string;
  end: string;
  meetingURL?: string;
}

export interface StorageGetParams {
  key: string;
}
export interface StorageSetParams {
  key: string;
  value: JSONValue;
  ttlSeconds?: number;
}

// ───────────────────────────────────────────────────────────────────────────
// Candidate  (Sources/VeeProtocol/Candidate.swift)
// ───────────────────────────────────────────────────────────────────────────

/**
 * A list item / candidate fed into the native fuzzy pipeline. The plugin pushes
 * `Candidate[]` once per open/refresh (`plugin.setCandidates`); the host filters
 * per keystroke natively and never crosses IPC on a keypress.
 */
export interface Candidate {
  /** Stable identity; used to diff candidate sets in place (preserve selection). */
  id: string;
  title: string;
  subtitle?: string;
  /** Optional icon hint (SF Symbol name, file path, or URL — host decides). */
  icon?: string;
  /** Extra match terms beyond `title` (acronyms, tags, repo names…). */
  keywords: string[];
  actions: CandidateAction[];
}

export interface CandidateAction {
  /** Echoed back to the plugin via `host.invokeAction`. */
  id: string;
  title: string;
  /** Optional shortcut hint, e.g. "cmd+enter". */
  shortcut?: string;
}

// ───────────────────────────────────────────────────────────────────────────
// Manifest  (Sources/VeeProtocol/Manifest.swift)
// ───────────────────────────────────────────────────────────────────────────

/** Command run mode. Mirrors `PluginCommand.Mode` (note the wire spellings). */
export type CommandMode = "view" | "menu-bar" | "no-view";

export interface PluginCommand {
  /** Stable command identifier within the plugin (passed in ActivateParams). */
  name: string;
  title: string;
  subtitle?: string;
  mode: CommandMode;
  /** Refresh interval (seconds) for menu-bar/background commands; null = manual. */
  refreshIntervalSeconds?: number;
  /** Hotkey action names this command exposes. */
  hotkeyActions?: string[];
}

/**
 * Capability manifest — the security surface. Default-deny: an all-empty value
 * grants nothing. The host checks every bridge call against this.
 */
export interface Capabilities {
  /** Allowed network hosts for `vee.http.fetch`. Exact or leading-dot suffix. */
  network: string[];
  /** Filesystem roots the plugin may read/write under. Empty = no fs access. */
  filesystem: string[];
  /** Whether `vee.clipboard.*` is permitted. */
  clipboard: boolean;
  /** Whether `vee.calendar.*` is permitted. */
  calendar: boolean;
  /** Keychain namespaces the plugin may use under its own id. */
  keychainNamespaces: string[];
  /** Hotkey action names the plugin declares for host binding. */
  hotkeyActions: string[];
}

/** A plugin's `vee.json` manifest: identity, entrypoint, commands, capabilities. */
export interface PluginManifest {
  /** Reverse-DNS unique id, e.g. "com.vee.github". */
  id: string;
  name: string;
  version: string;
  /** Path to the built single-file JS bundle, relative to the plugin folder. */
  entrypoint: string;
  commands: PluginCommand[];
  capabilities: Capabilities;
}

/** A default-deny Capabilities value (matches Swift `Capabilities()`). */
export function emptyCapabilities(): Capabilities {
  return {
    network: [],
    filesystem: [],
    clipboard: false,
    calendar: false,
    keychainNamespaces: [],
    hotkeyActions: [],
  };
}
