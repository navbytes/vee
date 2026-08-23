#!/usr/bin/env node
// Example using the optional structured-JSON protocol instead of the text
// format. A plugin opts in by printing a `{"vee":1,…}` object.
//
// `JSONMenu` mirrors `Menu` method for method, so the only thing that changes
// between the two wire formats is which builder you construct. Its `build()`
// output is committed to plugins/fixtures/json-demo.txt and checked for drift.
//
// Using this outside the repository: run `vee sdk ts` to write vee.ts beside
// your copy, then change the import below to "./vee.ts".
import { fileURLToPath } from "node:url";
import { JSONMenu } from "../vee.ts";

export function build(): string {
  const menu = new JSONMenu();
  menu.title("JSON ✓", { color: "green", sfimage: "curlybraces" });

  const d = menu.dropdown;
  d.item("Structured item", { href: "https://example.com" });
  d.separator();
  d.submenu("Submenu").item("Child", { color: "blue" });
  // Characters the three languages' JSON encoders disagree about by default:
  // Python escapes non-ASCII, Go escapes <, > and & for HTML embedding. Pinned
  // here so any of them regressing fails the drift guard.
  d.item("R&D <beta> ✓", { tooltip: "a & b" });
  return menu.toString();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
