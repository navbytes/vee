#!/usr/bin/env node
// Example using the widget-card layout tree: the composable escape hatch
// alongside the five preset templates, for layouts the presets can't express.
// This builds a CPU tile as a tree — a header row (glyph + title + spacer), a
// big monospaced value that scales to fit, a circular gauge, and a share chart
// of where the time goes — to exercise stacks, the two pressure-test modifiers
// (monospaced_digit, min_scale), the circular gauge, and a chart leaf whose
// colors list is deliberately shorter than its values (the third segment takes
// its palette slot) and which subtracts itself from the small family.
// See docs/design/widget-surface-contract.md §"Layout tree".
//
// Using this outside the repository: run `vee sdk ts` to write vee.ts beside
// your copy, then change the import below to "./vee.ts".
import { fileURLToPath } from "node:url";
import { widgetCard, Node } from "../vee.ts";

export function build(): string {
  return widgetCard({
    layout: Node.VStack(
      [
        Node.HStack([
          Node.Image("cpu", { style: { tint: "blue" } }),
          Node.Text("CPU", { style: { font: { size: "caption", weight: "semibold" }, tint: "secondary" } }),
          Node.Spacer(),
        ], { spacing: 5 }),
        Node.Text("38%", {
          style: { font: { size: "title", design: "rounded" }, tint: "green", monospacedDigit: true, minScale: 0.6 },
        }),
        Node.Gauge(0.38, { gaugeStyle: "circular", style: { tint: "green" } }),
        Node.Chart("stackedbar", [62, 21, 17], {
          labels: ["User", "System", "Idle"],
          colors: ["blue", "orange"],
          families: ["medium", "large"],
        }),
      ],
      { align: "leading", spacing: 6 },
    ),
  }).toString();
}

// Print when run directly (as a real plugin), not when imported by the tests.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
