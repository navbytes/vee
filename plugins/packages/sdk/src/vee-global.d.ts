/**
 * Ambient typings for the globals the Vee host injects into a plugin's
 * JavaScriptCore context BEFORE the bundle is evaluated.
 *
 * The host MUST install these. See `plugins/RUNTIME.md` for the binding
 * contract. Importing `@vee/sdk` pulls these declarations in, so plugin code
 * sees a fully-typed `vee` and `console` with no extra setup.
 */

import type { VeeHost, RegisteredPlugin } from "./runtime.js";

declare global {
  /**
   * The host bridge. Injected by the host; present whenever a bundle runs
   * inside Vee. Undefined only when a bundle is evaluated outside the host
   * (e.g. unit tests that exercise builders without rendering).
   */
  // eslint-disable-next-line no-var
  var vee: VeeHost;

  /**
   * The reserved slot a bundle assigns its registration to (done for you by
   * `definePlugin` / `registerCommand`). The host reads it after eval to learn
   * the bundle's commands and to activate them.
   */
  // eslint-disable-next-line no-var
  var __veePlugin: RegisteredPlugin | undefined;

  /**
   * Console shim the host injects (forwarded to the host as `plugin.log`
   * notifications). Only the four leveled methods are guaranteed.
   */
  // eslint-disable-next-line no-var
  var console: {
    debug(...args: unknown[]): void;
    info(...args: unknown[]): void;
    log(...args: unknown[]): void;
    warn(...args: unknown[]): void;
    error(...args: unknown[]): void;
  };
}

export {};
