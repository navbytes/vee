#!/usr/bin/env node
// Encoder edge cases, as a golden fixture. Unlike the other examples this one
// is not a plausible plugin — it exists to pin down the parts of the encoding
// contract the realistic examples never reach, each of which was a real
// cross-SDK divergence:
//
//   * numbers at and past 1e6, where Go's default float verb switches to
//     exponent notation and JavaScript's does not;
//   * numbers at the notation boundaries (1e-7, 1e21) where all three
//     languages' native float formatting disagrees;
//   * values holding whitespace the three languages classify differently
//     (non-breaking space; carriage return is covered by the escaping unit
//     tests, since a golden fixture cannot portably hold a bare CR);
//   * values that begin with a quote character, which the parser reads as a
//     delimiter and which must therefore be emitted quoted.
//
// Its output is committed to plugins/fixtures/edges.txt and asserted by all
// three SDKs, so any of these regressing in one language fails that language's
// drift guard.
import { fileURLToPath } from "node:url";
import { Menu } from "../vee.ts";

export function build(): string {
  const menu = new Menu();
  menu.title("Edges");

  const d = menu.dropdown;
  // Plain decimal well past the point Go's 'g' verb would go exponential.
  d.item("large", { sparkline: [1000000, 1234567, 999999, 12000000] });
  // The two boundaries of JavaScript's plain-decimal range.
  d.item("boundaries", { sparkline: [1e-7, 0.000001, 1e20, 1e21] });
  // Negative zero normalizes to "0"; shortest round-trip digits are preserved.
  d.item("signs", { sparkline: [-0, -1.5, 0.30000000000000004] });
  // Whitespace each language's own class disagrees about.
  d.item("nbsp", { tooltip: "a b" });
  // A leading quote is a delimiter to the parser; a contained one is not.
  d.item("leading-double", { tooltip: `"quoted"` });
  d.item("leading-single", { tooltip: `'tis` });
  d.item("inner-quote", { tooltip: `has"inside` });
  // The two characters the format itself reserves.
  d.item("reserved", { tooltip: `a|b\\c` });
  return menu.toString();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
