#!/usr/bin/env node
// Example Vee plugin exercising the typed rich-param builders — sparkline,
// toggle, slider, and progress. Doubles as a golden fixture: its `build()`
// output is committed to plugins/fixtures/controls.txt and checked for drift.
// The three language examples (TS/Python/Go) produce byte-identical output.
//
// Using this outside the repository: run `vee sdk ts` to write vee.ts beside
// your copy, then change the import below to "./vee.ts".
import { fileURLToPath } from "node:url";
import { Menu } from "../vee.ts";

export function build(): string {
  const menu = new Menu();
  menu.title("Controls", { sfimage: "slider.horizontal.3" });

  const d = menu.dropdown;
  // progress given as {value,max} → emitted as the format's two-argument
  // form `progress=72,100`, which Vee divides on parse,
  // with a track color and explicit size. The tooltip has spaces to prove the
  // shared quote() helper flows through the rich-param path.
  d.item("Disk usage", {
    color: "green",
    progress: { value: 72, max: 100 },
    progressTrackColor: "#333333",
    progressW: 80,
    progressH: 6,
    tooltip: "72 GB of 100 GB used",
  });
  d.item("Notifications", { toggle: true });
  d.item("Volume", { slider: { min: 0, max: 100, value: 40 } });
  // The sparkline takes the same size/colour vocabulary as progress= and the
  // chart shapes: <control>w / <control>h / <control>color.
  d.item("Load history", {
    sparkline: [1, 2, 3, 5, 8, 13],
    sparklineW: 120,
    sparklineH: 18,
    sparklineColor: "teal",
  });
  return menu.toString();
}

// Print when run directly (as a real plugin), not when imported by the tests.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
