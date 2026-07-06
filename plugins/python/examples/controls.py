#!/usr/bin/env python3
# Example Vee plugin exercising the typed rich-param builders — sparkline,
# toggle, slider, and progress. Doubles as a golden fixture: its build() output
# is committed to plugins/python/fixtures/controls.txt and checked for drift.
# Produces byte-identical output to the TypeScript and Go examples.
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from vee import Menu  # noqa: E402


def build() -> str:
    menu = Menu()
    menu.title("Controls", sfimage="slider.horizontal.3")

    d = menu.dropdown
    # progress given as (value, max) → normalized to the single fraction 0.72,
    # with a track color and explicit size. The tooltip has spaces to prove the
    # shared _quote helper flows through the rich-param path.
    d.item(
        "Disk usage",
        color="green",
        progress=(72, 100),
        trackColor="#333333",
        progressW=80,
        progressH=6,
        tooltip="72 GB of 100 GB used",
    )
    d.item("Notifications", toggle=True)
    d.item("Volume", slider={"min": 0, "max": 100, "value": 40})
    d.item("Load history", sparkline=[1, 2, 3, 5, 8, 13])
    return menu.to_string()


if __name__ == "__main__":
    sys.stdout.write(build() + "\n")
