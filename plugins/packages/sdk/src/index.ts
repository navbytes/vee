/// <reference path="./vee-global.d.ts" />
/**
 * @vee/sdk — the TypeScript SDK for authoring Vee plugins.
 *
 * Re-exports the wire types (mirrors of `Sources/VeeProtocol`), the pure
 * `RenderNode` builder helpers, and the thin host runtime convention.
 * No React; plain JSON component trees. No runtime imports — bundles to nothing
 * but your own code. The triple-slash reference above pulls in the ambient
 * `vee`/`console` global declarations for any consumer that imports this entry.
 */

// Wire contract types + name constants.
export * from "./types.js";

// Pure RenderNode builders + the wire projection.
export * from "./dom.js";

// Host runtime convention: definePlugin/registerCommand + bridge accessors.
export * from "./runtime.js";
