#!/usr/bin/env python3
# The structured-JSON protocol, built with JSONMenu. Byte-identical to the
# TypeScript and Go examples; committed to plugins/fixtures/json-demo.txt.
#
# Using this outside the repository: run `vee sdk py` to write vee.py beside
# your copy. No edit needed -- Python already searches the script's own
# directory.
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from vee import JSONMenu  # noqa: E402


def build() -> str:
    menu = JSONMenu()
    menu.title("JSON ✓", color="green", sfimage="curlybraces")

    d = menu.dropdown
    # Surface targeting, in its JSON spelling: the same two axes the text
    # protocol writes as `visibleon=`/`searchable=` (see the surfaces example).
    d.item("Structured item", href="https://example.com",
           visible_on=["menu", "window"], searchable=False)
    d.separator()
    d.submenu("Submenu").item("Child", color="blue")
    # See the TypeScript example: characters the three JSON encoders disagree
    # about by default.
    d.item("R&D <beta> ✓", tooltip="a & b")
    return menu.to_string()


if __name__ == "__main__":
    print(build())
