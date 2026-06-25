/**
 * Test helpers.
 *
 * The SDK is authored in TypeScript with NodeNext-style `.js` import specifiers
 * (the correct convention for tsc output). Node's built-in type-stripping does
 * NOT remap `.js`→`.ts`, so we load the SDK the same way the real pipeline does:
 * by bundling it with esbuild into an in-memory ESM module and importing that.
 * This means the unit tests exercise the exact code the shipped bundle contains.
 */

import * as esbuild from "esbuild";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SDK_ENTRY = resolve(__dirname, "../packages/sdk/src/index.ts");

let sdkPromise;

/** Load `@vee/sdk` as a live ESM module (bundled via esbuild, cached). */
export function loadSdk() {
  if (!sdkPromise) {
    sdkPromise = (async () => {
      const result = await esbuild.build({
        entryPoints: [SDK_ENTRY],
        bundle: true,
        format: "esm",
        platform: "neutral",
        target: ["es2021"],
        write: false,
      });
      const code = result.outputFiles[0].text;
      const dataUrl = "data:text/javascript;base64," + Buffer.from(code).toString("base64");
      return import(dataUrl);
    })();
  }
  return sdkPromise;
}
