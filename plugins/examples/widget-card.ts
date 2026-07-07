#!/usr/bin/env node
// Example using the widget-card SDK: the rich, structured payload a plugin
// prints to stdout when invoked with VEE_TARGET=widget, instead of scraping
// its own menu-bar text. See docs/design/widget-surface-contract.md §4. This
// is the design doc's own worked example, built with the SDK.
import { fileURLToPath } from "node:url";
import { Stat } from "../src/vee.ts";

export function build(): string {
  return Stat({
    title: "Revenue",
    symbol: "chart.line.uptrend.xyaxis",
    tint: "green",
    value: "$18.2k",
    caption: "today",
    detail: "214 orders",
    status: "ok",
    progress: 0.72,
    trend: [12.1, 13.4, 12.9, 15.0, 18.2],
    items: [
      { label: "Orders", value: "214", symbol: "bag", tint: "blue" },
      { label: "Refunds", value: "3", symbol: "arrow.uturn.left", tint: "red" },
    ],
    actions: [
      { kind: "refresh", label: "Refresh" },
      { kind: "href", label: "Open", url: "https://dash.example.com" },
    ],
    refreshAfter: 900,
    staleAfter: 3600,
  }).toString();
}

// Print when run directly (as a real plugin), not when imported by the tests.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
