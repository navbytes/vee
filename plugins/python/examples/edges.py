#!/usr/bin/env python3
# Encoder edge cases, as a golden fixture. See plugins/typescript/examples/
# edges.ts for what each line pins down; this file must produce byte-identical
# output. Committed to plugins/fixtures/edges.txt.
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
    menu.title("Edges")

    d = menu.dropdown
    d.item("large", sparkline=[1000000.0, 1234567.0, 999999.0, 12000000.0])
    d.item("boundaries", sparkline=[1e-7, 0.000001, 1e20, 1e21])
    d.item("signs", sparkline=[-0.0, -1.5, 0.30000000000000004])
    d.item("nbsp", tooltip="a b")
    d.item("leading-double", tooltip='"quoted"')
    d.item("leading-single", tooltip="'tis")
    d.item("inner-quote", tooltip='has"inside')
    d.item("reserved", tooltip="a|b\\c")
    return menu.to_string()


if __name__ == "__main__":
    print(build())
