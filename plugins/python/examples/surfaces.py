#!/usr/bin/env python3
# The two surface-targeting axes -- visible_on (where a row exists) and
# searchable (whether a query can reach it). Byte-identical to the TypeScript
# and Go examples; committed to plugins/fixtures/surfaces.txt.
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
    menu.title("Deploy ✓", color="green")

    d = menu.dropdown
    d.item("Open dashboard", href="https://deploy.example.com")
    # Two surfaces named: the row exists on those and nowhere else. Copying to
    # the pasteboard means nothing in a terminal listing.
    d.item("Copy build ID", shell="/usr/bin/pbcopy", params=["4210"],
           visible_on=["menu", "window"])
    # Browsable, but never a search hit: one Return away is the wrong distance
    # for a destructive action. The ⌥ alternate inherits it from the primary.
    d.item("Roll back", shell="/usr/local/bin/deploy", params=["rollback"],
           searchable=False)
    d.item("Roll back (force)", alternate=True, shell="/usr/local/bin/deploy",
           params=["rollback", "--force"])
    d.separator()
    # Hiding takes the subtree with it: both children go wherever the parent does.
    logs = d.submenu("Logs", visible_on=["window", "cli"])
    logs.item("Build log", href="https://deploy.example.com/4210/log")
    logs.item("Test log", href="https://deploy.example.com/4210/tests")
    return menu.to_string()


if __name__ == "__main__":
    sys.stdout.write(build() + "\n")
