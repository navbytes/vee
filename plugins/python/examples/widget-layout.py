#!/usr/bin/env python3
# Example Vee plugin using the widget-card layout tree: the composable escape
# hatch alongside the five preset templates (see the design doc §"Layout tree").
# Builds a CPU tile as a tree — a header row, a big monospaced value that scales
# to fit, and a circular gauge. Doubles as a golden fixture, byte-identical to
# the TypeScript/Go widget-layout examples.
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from vee import Node, widget_card  # noqa: E402


def build() -> str:
    card = widget_card(
        layout=Node.VStack(
            [
                Node.HStack(
                    [
                        Node.Image("cpu", style={"tint": "blue"}),
                        Node.Text("CPU", style={"font": {"size": "caption", "weight": "semibold"}, "tint": "secondary"}),
                        Node.Spacer(),
                    ],
                    spacing=5,
                ),
                Node.Text(
                    "38%",
                    style={"font": {"size": "title", "design": "rounded"}, "tint": "green", "monospaced_digit": True, "min_scale": 0.6},
                ),
                Node.Gauge(0.38, gauge_style="circular", style={"tint": "green"}),
            ],
            align="leading",
            spacing=6,
        ),
    )
    return card.to_string()


if __name__ == "__main__":
    sys.stdout.write(build() + "\n")
