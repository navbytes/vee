#!/usr/bin/env node
// Example Vee plugin exercising the typed rich-param builders — sparkline,
// toggle, slider, and progress. Doubles as a golden fixture: its `build()`
// output is committed to plugins/fixtures/controls.txt and checked for drift.
// The three language examples (TS/Python/Go) produce byte-identical output.
import { fileURLToPath } from "node:url";
import { Menu } from "../src/vee.ts";

export function build(): string {
  const menu = new Menu();
  menu.title("Controls", { sfimage: "slider.horizontal.3" });

  const d = menu.dropdown;
  // progress given as {value,max} → normalized to the single fraction 0.72,
  // with a track color and explicit size. The tooltip has spaces to prove the
  // shared quote() helper flows through the rich-param path.
  d.item("Disk usage", {
    color: "green",
    progress: { value: 72, max: 100 },
    trackColor: "#333333",
    progressW: 80,
    progressH: 6,
    tooltip: "72 GB of 100 GB used",
  });
  d.item("Notifications", { toggle: true });
  d.item("Volume", { slider: { min: 0, max: 100, value: 40 } });
  d.item("Load history", { sparkline: [1, 2, 3, 5, 8, 13] });
  return menu.toString();
}

// Print when run directly (as a real plugin), not when imported by the tests.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
