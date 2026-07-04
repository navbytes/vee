#!/usr/bin/env node
// Example using the optional structured-JSON protocol instead of the text
// format. A plugin opts in by printing a `{"vee":1,…}` object.
import { fileURLToPath } from "node:url";

export function build(): string {
  const menu = {
    vee: 1,
    title: [{ text: "JSON ✓", color: "green", sfimage: "curlybraces" }],
    items: [
      { text: "Structured item", href: "https://example.com" },
      { separator: true },
      { text: "Submenu", submenu: [{ text: "Child", color: "blue" }] },
    ],
  };
  return JSON.stringify(menu);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
