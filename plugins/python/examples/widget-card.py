#!/usr/bin/env python3
# Example Vee plugin using the widget-card SDK: the rich, structured
# VEE_TARGET=widget stdout payload described in
# docs/design/widget-surface-contract.md §4. Doubles as a golden fixture,
# byte-identical to the TypeScript/Go widget-card examples.
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from vee import Stat  # noqa: E402


def build() -> str:
    card = Stat(
        title="Revenue",
        symbol="chart.line.uptrend.xyaxis",
        tint="green",
        value="$18.2k",
        caption="today",
        detail="214 orders",
        status="ok",
        progress=0.72,
        trend=[12.1, 13.4, 12.9, 15.0, 18.2],
        items=[
            {"label": "Orders", "value": "214", "symbol": "bag", "tint": "blue"},
            {"label": "Refunds", "value": "3", "symbol": "arrow.uturn.left", "tint": "red"},
        ],
        actions=[
            {"kind": "refresh", "label": "Refresh"},
            {"kind": "href", "label": "Open", "url": "https://dash.example.com"},
        ],
        refreshAfter=900,
        staleAfter=3600,
    )
    return card.to_string()


if __name__ == "__main__":
    sys.stdout.write(build() + "\n")
