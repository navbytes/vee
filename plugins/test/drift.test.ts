// Drift guard: every example's build() output must match its committed golden
// fixture. Fixtures also feed the Swift parser tests (VeePluginFormat), so this
// keeps the SDK, the fixtures, and the parser in lockstep.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const examplesDir = join(here, "..", "examples");
const fixturesDir = join(here, "..", "fixtures");

for (const file of readdirSync(examplesDir).filter((f) => f.endsWith(".ts"))) {
  test(`fixture is up to date: ${file}`, async () => {
    const mod = await import(join(examplesDir, file));
    assert.equal(typeof mod.build, "function", `${file} must export build()`);
    const output: string = mod.build();
    const fixtureName = file.replace(/\.ts$/, ".txt");
    const expected = readFileSync(join(fixturesDir, fixtureName), "utf8").replace(/\n$/, "");
    assert.equal(
      output,
      expected,
      `${file} output drifted from fixtures/${fixtureName}. Regenerate with: node examples/${file} > fixtures/${fixtureName}`
    );
  });
}
