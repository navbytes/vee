#!/usr/bin/env node
// Example Vee plugin exercising the categorical share charts — pie, donut, and
// stacked bar. Doubles as a golden fixture: its `build()` output is committed
// to plugins/fixtures/charts.txt and checked for drift. The three language
// examples (TS/Python/Go) produce byte-identical output.
import { fileURLToPath } from "node:url";
import { Menu } from "../vee.ts";

export function build(): string {
  const menu = new Menu();
  menu.title("Disk", { sfimage: "chart.pie" });

  const d = menu.dropdown;
  // The same three shapes over the same kind of data: switching `kind` is the
  // only difference between them.
  d.item("By category", {
    chart: { kind: "pie", values: [45, 30, 25], labels: ["Documents", "Photos", "Apps"] },
  });
  // Named colors override the default palette, positionally.
  d.item("By volume", {
    chart: {
      kind: "donut",
      values: [512, 256, 128],
      labels: ["Macintosh HD", "Backup", "Scratch"],
      colors: ["blue", "teal", "orange"],
    },
    tooltip: "896 GB across 3 volumes",
  });
  d.item("Budget", {
    chart: { kind: "stackedbar", values: [60, 25, 15], labels: ["Used", "Cache", "Free"] },
  });
  return menu.toString();
}

// Print when run directly (as a real plugin), not when imported by the tests.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
