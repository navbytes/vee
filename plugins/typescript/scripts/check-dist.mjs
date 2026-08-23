// Assert the *compiled* SDK produces the same bytes as the source.
//
// The published package cannot ship vee.ts — Node refuses to strip types under
// node_modules — so npm consumers run `tsc` output while everyone else runs the
// original. That is a fourth copy of this SDK (source, the copy embedded in the
// CLI, the vendored sibling, and now the package), and the golden fixtures are
// what stop copies drifting. This runs every example's `build()` against dist/
// and diffs against the same fixtures the source is held to.
import { readFileSync, writeFileSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = resolve(import.meta.dirname, "..");
const dist = join(root, "dist", "vee.js");
const fixtures = resolve(root, "..", "fixtures");

try {
  readFileSync(dist);
} catch {
  console.error("dist/vee.js is missing — run `npm run build` first.");
  process.exit(1);
}

const work = mkdtempSync(join(tmpdir(), "vee-dist-"));
let failures = 0;

for (const file of readdirSync(join(root, "examples")).filter((f) => f.endsWith(".ts")).sort()) {
  const name = file.replace(/\.ts$/, "");
  const src = readFileSync(join(root, "examples", file), "utf8");
  // Point the example at the compiled module instead of the source. Keep the
  // .ts extension: the copy lands outside node_modules, so Node still strips
  // the example's own types.
  const runner = join(work, `${name}.ts`);
  writeFileSync(runner, src.replace(/from "\.\.\/vee\.ts"/, `from ${JSON.stringify(dist)}`));

  // Call build() rather than executing the file: the examples only print when
  // run directly, and that check compares import.meta.url to argv[1], which
  // disagree once the copy sits behind a symlinked temp path.
  const { build } = await import(pathToFileURL(runner).href);
  const got = build();
  const want = readFileSync(join(fixtures, `${name}.txt`), "utf8");
  if (got.replace(/\n$/, "") !== want.replace(/\n$/, "")) {
    failures++;
    console.error(`✗ ${name}: compiled output differs from fixtures/${name}.txt`);
  }
}

rmSync(work, { recursive: true, force: true });
if (failures) {
  console.error(`\n${failures} example(s) drifted. The published package would not match the source.`);
  process.exit(1);
}
console.log("ok: compiled SDK matches the golden fixtures");
