#!/usr/bin/env python3
# Example Vee plugin exercising the categorical share charts — pie, donut, and
# stacked bar. Doubles as a golden fixture: its build() output is committed to
# plugins/fixtures/charts.txt and checked for drift. Produces
# byte-identical output to the TypeScript and Go examples.
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
    menu.title("Disk", sfimage="chart.pie")

    d = menu.dropdown
    # The same three shapes over the same kind of data: switching "kind" is the
    # only difference between them.
    d.item(
        "By category",
        chart={"kind": "pie", "values": [45, 30, 25], "labels": ["Documents", "Photos", "Apps"]},
    )
    # Named colors override the default palette, positionally.
    d.item(
        "By volume",
        chart={
            "kind": "donut",
            "values": [512, 256, 128],
            "labels": ["Macintosh HD", "Backup", "Scratch"],
            "colors": ["blue", "teal", "orange"],
        },
        tooltip="896 GB across 3 volumes",
    )
    d.item(
        "Budget",
        chart={"kind": "stackedbar", "values": [60, 25, 15], "labels": ["Used", "Cache", "Free"]},
    )
    return menu.to_string()


if __name__ == "__main__":
    sys.stdout.write(build() + "\n")
