#!/usr/bin/env node
// Example Vee plugin built with the SDK. Doubles as a golden fixture: its
// `build()` output is committed to plugins/fixtures/cpu.txt and checked for
// drift by the test suite.
import { fileURLToPath } from "node:url";
import { Menu } from "../src/vee.ts";

export function build(): string {
  const menu = new Menu();
  menu.title("CPU 12%", { color: "green", sfimage: "cpu" });

  const d = menu.dropdown;
  d.item("Top processes", { href: "https://example.com/procs" });
  d.separator();

  const details = d.submenu("Details");
  details.item("Load: 1.20");
  details.item("Cores: 8");

  d.item("Refresh", { refresh: true });
  return menu.toString();
}

// Print when run directly (as a real plugin), not when imported by the tests.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
