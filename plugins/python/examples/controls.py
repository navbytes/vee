#!/usr/bin/env python3
# Example Vee plugin exercising the typed rich-param builders — sparkline,
# toggle, slider, and progress. Doubles as a golden fixture: its build() output
# is committed to plugins/fixtures/controls.txt and checked for drift.
# Produces byte-identical output to the TypeScript and Go examples.
#
# Using this outside the repository: run `vee sdk py` to write vee.py beside
# your copy. No edit needed -- Python already searches the script's own
# directory.
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from vee import Menu  # noqa: E402


def build() -> str:
    menu = Menu()
    menu.title("Controls", sfimage="slider.horizontal.3")

    d = menu.dropdown
    # progress given as {value, max} → emitted as the format's two-argument
    # form `progress=72,100`, which Vee divides on parse,
    # with a track color and explicit size. The tooltip has spaces to prove the
    # shared _quote helper flows through the rich-param path.
    d.item(
        "Disk usage",
        color="green",
        progress={"value": 72, "max": 100},
        progress_track_color="#333333",
        progress_w=80,
        progress_h=6,
        tooltip="72 GB of 100 GB used",
    )
    d.item("Notifications", toggle=True)
    # accessory_w sizes whichever accessory a row carries -- here the
    # slider track, which had no size of its own before.
    d.item("Volume", slider={"min": 0, "max": 100, "value": 40}, accessory_w=120)
    # The sparkline takes the same size/colour vocabulary as progress= and the
    # chart shapes: <control>_w / <control>_h / <control>_color.
    d.item(
        "Load history",
        sparkline=[1, 2, 3, 5, 8, 13],
        sparkline_w=120,
        sparkline_h=18,
        sparkline_color="teal",
    )
    return menu.to_string()


if __name__ == "__main__":
    sys.stdout.write(build() + "\n")
