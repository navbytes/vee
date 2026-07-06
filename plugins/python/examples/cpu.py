#!/usr/bin/env python3
# Example Vee plugin built with the Python SDK. Doubles as a golden fixture: its
# build() output is committed to plugins/python/fixtures/cpu.txt and checked for
# drift by the test suite. Produces byte-identical output to the TypeScript
# example (plugins/examples/cpu.ts) — proving cross-language parity.
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from vee import Menu  # noqa: E402


def build() -> str:
    menu = Menu()
    menu.title("CPU 12%", color="green", sfimage="cpu")

    d = menu.dropdown
    d.item("Top processes", href="https://example.com/procs")
    d.separator()

    details = d.submenu("Details")
    details.item("Load: 1.20")
    details.item("Cores: 8")

    d.item("Refresh", refresh=True)
    return menu.to_string()


if __name__ == "__main__":
    sys.stdout.write(build() + "\n")
