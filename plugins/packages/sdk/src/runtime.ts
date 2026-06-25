/**
 * The thin JS-side runtime a plugin uses to talk to the host.
 *
 * Vee runs each plugin bundle inside a JavaScriptCore context. JSC has no module
 * loader and no DOM — so the host injects a single global object named `vee`
 * (plus a `console`) BEFORE evaluating the bundle. This file:
 *   1. declares the shape of that injected global (`VeeHost`), and
 *   2. provides the authoring entry points (`definePlugin`, `registerCommand`)
 *      and ergonomic re-exports of the bridge (`render`, `http`, `storage`…).
 *
 * IMPORTANT: nothing here imports a runtime or touches Node/DOM APIs. The only
 * ambient dependency is the injected `vee` global. See `plugins/RUNTIME.md` for
 * the full host-side contract (Wave 2a implements the host from that doc).
 */

import type {
  CalendarEvent,
  Candidate,
  InvokeActionParams,
  JSONValue,
  RenderNode,
  SearchTextChangeParams,
  SubmitFormParams,
  ToastStyle,
} from "./types.js";
import { renderNodeToJSON } from "./dom.js";

// ───────────────────────────────────────────────────────────────────────────
// The injected `vee` global — the host↔plugin bridge surface.
// ───────────────────────────────────────────────────────────────────────────

/** A command handler: invoked by the host on `plugin.activate`. */
export type CommandHandler = (ctx: CommandContext) => void | Promise<void>;

/** Handler for an action the user invoked (host.invokeAction). */
export type ActionHandler = (params: InvokeActionParams) => void | Promise<void>;

/** Handler for a search-text change (host.onSearchTextChange). */
export type SearchTextHandler = (query: string, params: SearchTextChangeParams) => void | Promise<void>;

/** Handler for a form submission (host.submitForm). */
export type SubmitFormHandler = (params: SubmitFormParams) => void | Promise<void>;

/** A disposer returned by the `on*` registrars; call it to unsubscribe. */
export type Unsubscribe = () => void;

/**
 * The HTTP bridge (`vee.http`). Capability-gated by `capabilities.network`.
 * A fetch-like façade; the host performs the request natively (URLSession) and
 * returns a decoded response. Bodies are passed/returned as UTF-8 text or JSON
 * for convenience (the underlying wire uses base64 — the SDK hides that).
 */
export interface VeeHttp {
  fetch(url: string, init?: VeeFetchInit): Promise<VeeResponse>;
}

export interface VeeFetchInit {
  method?: string;
  headers?: Record<string, string>;
  /** Request body as a string (UTF-8). Omit for GET. */
  body?: string;
}

export interface VeeResponse {
  status: number;
  headers: Record<string, string>;
  /** Response body decoded as UTF-8 text. */
  text(): Promise<string>;
  /** Response body parsed as JSON. */
  json(): Promise<JSONValue>;
}

/** The SWR-backed key/value store (`vee.storage`). */
export interface VeeStorage {
  get(key: string): Promise<JSONValue | undefined>;
  set(key: string, value: JSONValue, ttlSeconds?: number): Promise<void>;
}

/**
 * The filesystem bridge (`vee.fs`). Capability-gated by `capabilities.filesystem`
 * (the plugin may only read/write under its allowed roots). The host reads/writes
 * the file natively; the plugin-facing façade speaks UTF-8 text (the wire uses
 * base64 — `FSReadParams` / `FSWriteParams` — and the SDK hides that).
 */
export interface VeeFs {
  /** Read a UTF-8 text file. Rejects if the path is outside the allowed roots. */
  read(path: string): Promise<string>;
  /** Write a UTF-8 text file. Rejects if the path is outside the allowed roots. */
  write(path: string, contents: string): Promise<void>;
}

/**
 * The calendar bridge (`vee.calendar`). Capability-gated by `capabilities.calendar`.
 * `upcoming()` returns the user's near-future events (the host decides the window).
 */
export interface VeeCalendar {
  /** Upcoming calendar events, soonest first. */
  upcoming(): Promise<CalendarEvent[]>;
}

/**
 * The keychain bridge (`vee.keychain`). Capability-gated by
 * `capabilities.keychainNamespaces`: a plugin may only touch namespaces it
 * declared. Items are scoped `(namespace, account)` under the plugin's own id.
 */
export interface VeeKeychain {
  /** Read a secret, or `null` when the item is absent. */
  get(namespace: string, account: string): Promise<string | null>;
  /** Create or update a secret. */
  set(namespace: string, account: string, value: string): Promise<void>;
  /** Delete a secret. No-op when the item is absent. */
  delete(namespace: string, account: string): Promise<void>;
}

/**
 * The full surface the host injects as the global `vee`. Wave 2a MUST provide
 * every member below with these exact signatures. All async members return
 * Promises the host settles when the corresponding JSON-RPC response arrives.
 */
export interface VeeHost {
  /** Reverse-DNS id of the running plugin (from the manifest). */
  readonly pluginId: string;

  // ── Rendering (plugin → host) ──────────────────────────────────────────────
  /**
   * Submit a complete render tree. The host diffs it against the previous tree
   * and ships a `plugin.render` JSON-Patch notification. Accepts a `RenderNode`
   * OR its already-projected `JSONValue`. Idempotent: re-rendering an identical
   * tree produces an empty patch (no-op on the native side).
   */
  render(node: RenderNode | JSONValue): void;

  /**
   * Push the full candidate set for native fuzzy filtering
   * (`plugin.setCandidates`). The host filters per keystroke without IPC.
   */
  setCandidates(candidates: Candidate[]): void;

  // ── Inbound event registration (host → plugin) ─────────────────────────────
  /**
   * Register the handler the host calls when the user invokes an `<action>`.
   * Returns an unsubscribe. Multiple registrations are additive.
   */
  onInvokeAction(handler: ActionHandler): Unsubscribe;
  /** Register the handler for search-field changes. Returns an unsubscribe. */
  onSearchTextChange(handler: SearchTextHandler): Unsubscribe;
  /** Register the handler for form submissions. Returns an unsubscribe. */
  onSubmitForm(handler: SubmitFormHandler): Unsubscribe;

  // ── Bridges (plugin → host; capability-gated, async) ───────────────────────
  readonly http: VeeHttp;
  readonly storage: VeeStorage;
  readonly fs: VeeFs;
  readonly calendar: VeeCalendar;
  readonly keychain: VeeKeychain;

  // ── System affordances (plugin → host; async) ──────────────────────────────
  /**
   * Open a URL in the user's default handler (web link, `mailto:`, custom
   * scheme…). Resolves once the host has dispatched the open.
   */
  open(url: string): Promise<void>;
  /** Launch (or activate) an application by its bundle id, e.g. `com.apple.Safari`. */
  openApp(bundleId: string): Promise<void>;

  // ── UI affordances ─────────────────────────────────────────────────────────
  /** Show a transient toast (`plugin.showToast`). */
  showToast(style: ToastStyle, title: string, message?: string): void;
}

// ───────────────────────────────────────────────────────────────────────────
// Authoring entry points
// ───────────────────────────────────────────────────────────────────────────

/** The context handed to a command handler when the host activates it. */
export interface CommandContext {
  pluginId: string;
  /** The command name the host activated (matches a manifest command). */
  commandName: string;
  /** Launcher-supplied arguments (e.g. a query argument). */
  arguments: Record<string, JSONValue>;
  /** Convenience: same as `vee.render`. */
  render(node: RenderNode | JSONValue): void;
}

/** The shape a bundle passes to `definePlugin`. */
export interface PluginDefinition {
  /** Map of command name → handler. Names must match the `vee.json` manifest. */
  commands: Record<string, CommandHandler>;
}

/**
 * What the host looks for after evaluating the bundle. The bundle MUST assign
 * this object to `globalThis.__veePlugin` (the IIFE build does this for you via
 * `definePlugin`). The host then calls `activateCommand(name, ctx)` on
 * `plugin.activate`.
 */
export interface RegisteredPlugin {
  /** Names of every command the bundle registered. */
  commandNames: string[];
  /** Host entry: invoke a command by name with an activation context. */
  activateCommand(name: string, ctx: CommandContext): void | Promise<void>;
}

/** The reserved global slot where a bundle exposes its registration. */
export const PLUGIN_GLOBAL_KEY = "__veePlugin" as const;

// Internal registry so `registerCommand` and `definePlugin` interoperate.
const commandRegistry = new Map<string, CommandHandler>();

function buildRegisteredPlugin(): RegisteredPlugin {
  return {
    get commandNames() {
      return [...commandRegistry.keys()];
    },
    activateCommand(name, ctx) {
      const handler = commandRegistry.get(name);
      if (!handler) {
        throw new Error(`vee: no command registered named "${name}"`);
      }
      return handler(ctx);
    },
  };
}

function publish(): RegisteredPlugin {
  const reg = buildRegisteredPlugin();
  // Expose to the host. JSC evaluates the IIFE; the host reads this slot after.
  (globalThis as Record<string, unknown>)[PLUGIN_GLOBAL_KEY] = reg;
  return reg;
}

/**
 * Register a single command handler. Lower-level than `definePlugin`; useful
 * when you build commands programmatically. The registration is published to
 * the host immediately, so calling this once is sufficient.
 */
export function registerCommand(name: string, handler: CommandHandler): void {
  commandRegistry.set(name, handler);
  publish();
}

/**
 * The primary entry point. Call once at the top level of your bundle:
 *
 *   definePlugin({ commands: { view: (ctx) => { ctx.render(root(...)); } } });
 *
 * Registers every command and publishes the plugin to the host global.
 * Returns the `RegisteredPlugin` (mostly for tests).
 */
export function definePlugin(def: PluginDefinition): RegisteredPlugin {
  for (const [name, handler] of Object.entries(def.commands)) {
    commandRegistry.set(name, handler);
  }
  return publish();
}

// ───────────────────────────────────────────────────────────────────────────
// Ergonomic accessors over the injected `vee` global.
// ───────────────────────────────────────────────────────────────────────────

/**
 * Access the injected host bridge. Throws a clear error if `vee` is missing,
 * which only happens when a bundle is run outside the Vee host (e.g. in a unit
 * test). Builder/`definePlugin` code does NOT need the host, so it stays
 * testable; only the bridge accessors below require it.
 */
export function host(): VeeHost {
  const v = (globalThis as { vee?: VeeHost }).vee;
  if (!v) {
    throw new Error(
      "vee: the host global `vee` is not present. " +
        "This bundle must be evaluated inside the Vee host.",
    );
  }
  return v;
}

/** Submit a render tree to the host (accepts a RenderNode or its JSON form). */
export function render(node: RenderNode | JSONValue): void {
  // Normalize a RenderNode to its wire projection so the host always receives
  // the canonical `{tag,props,children,(key)}` shape. A plain JSONValue passes
  // through untouched.
  const payload = isRenderNode(node) ? renderNodeToJSON(node) : node;
  host().render(payload);
}

/** Push candidates for native fuzzy filtering. */
export function setCandidates(candidates: Candidate[]): void {
  host().setCandidates(candidates);
}

/** Show a transient toast. */
export function showToast(style: ToastStyle, title: string, message?: string): void {
  host().showToast(style, title, message);
}

/** The HTTP bridge. */
export function http(): VeeHttp {
  return host().http;
}

/** The key/value storage bridge. */
export function storage(): VeeStorage {
  return host().storage;
}

/** The filesystem bridge. */
export function fs(): VeeFs {
  return host().fs;
}

/** The calendar bridge. */
export function calendar(): VeeCalendar {
  return host().calendar;
}

/** The keychain bridge. */
export function keychain(): VeeKeychain {
  return host().keychain;
}

/** Open a URL in the user's default handler. */
export function open(url: string): Promise<void> {
  return host().open(url);
}

/** Launch (or activate) an application by its bundle id. */
export function openApp(bundleId: string): Promise<void> {
  return host().openApp(bundleId);
}

/** Register an action handler. */
export function onInvokeAction(handler: ActionHandler): Unsubscribe {
  return host().onInvokeAction(handler);
}

/** Register a search-text handler. */
export function onSearchTextChange(handler: SearchTextHandler): Unsubscribe {
  return host().onSearchTextChange(handler);
}

/** Register a form-submission handler. */
export function onSubmitForm(handler: SubmitFormHandler): Unsubscribe {
  return host().onSubmitForm(handler);
}

/** Structural check: does this value look like an in-memory RenderNode? */
function isRenderNode(v: unknown): v is RenderNode {
  return (
    typeof v === "object" &&
    v !== null &&
    typeof (v as RenderNode).tag === "string" &&
    typeof (v as RenderNode).props === "object" &&
    Array.isArray((v as RenderNode).children)
  );
}
