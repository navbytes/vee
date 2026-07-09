#!/usr/bin/env node
// Example using the widget-card layout tree: the composable escape hatch
// alongside the five preset templates, for layouts the presets can't express.
// This builds a CPU tile as a tree — a header row (glyph + title + spacer), a
// big monospaced value that scales to fit, and a circular gauge — to exercise
// stacks, the two pressure-test modifiers (monospaced_digit, min_scale), and
// the circular gauge. See docs/design/widget-surface-contract.md §"Layout tree".
import { fileURLToPath } from "node:url";
import { widgetCard, Node } from "../src/vee.ts";

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
      ],
      { align: "leading", spacing: 6 },
    ),
  }).toString();
}

// Print when run directly (as a real plugin), not when imported by the tests.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
