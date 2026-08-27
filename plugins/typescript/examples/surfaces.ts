#!/usr/bin/env node
// Exercises the two surface-targeting axes — `visibleOn` (where a row exists)
// and `searchable` (whether a query can reach it) — so the fixture drift guard
// and the Swift parser tests cover both, in the three SDKs at once.
//
// Using this outside the repository: run `vee sdk ts` to write vee.ts beside
// your copy, then change the import below to "./vee.ts".
import { fileURLToPath } from "node:url";
import { Menu } from "../vee.ts";

export function build(): string {
  const menu = new Menu();
  menu.title("Deploy ✓", { color: "green" });

  const d = menu.dropdown;
  d.item("Open dashboard", { href: "https://deploy.example.com" });
  // Two surfaces named: the row exists on those and nowhere else. Copying to
  // the pasteboard means nothing in a terminal listing.
  d.item("Copy build ID", {
    shell: "/usr/bin/pbcopy",
    params: ["4210"],
    visibleOn: ["menu", "window"],
  });
  // Browsable, but never a search hit: one Return away is the wrong distance
  // for a destructive action. The ⌥ alternate inherits it from the primary.
  d.item("Roll back", {
    shell: "/usr/local/bin/deploy",
    params: ["rollback"],
    searchable: false,
  });
  d.item("Roll back (force)", {
    alternate: true,
    shell: "/usr/local/bin/deploy",
    params: ["rollback", "--force"],
  });
  d.separator();
  // Hiding takes the subtree with it: both children go wherever the parent does.
  const logs = d.submenu("Logs", { visibleOn: ["window", "cli"] });
  logs.item("Build log", { href: "https://deploy.example.com/4210/log" });
  logs.item("Test log", { href: "https://deploy.example.com/4210/tests" });
  return menu.toString();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
