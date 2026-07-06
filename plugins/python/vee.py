"""Vee plugin SDK — typed builders that emit the xbar/SwiftBar text format Vee
parses. Zero dependencies; pure standard-library Python.

Mirrors the TypeScript SDK (``plugins/src/vee.ts``): the same builder shape,
option names, encoding order, and quoting, so a plugin reads the same in either
language and both produce byte-identical output for the same menu.
"""

from __future__ import annotations

import re
import sys
from typing import Any

__all__ = ["Menu", "Section"]

_NEEDS_QUOTE = re.compile(r"[\s|]")

# Option name -> emitted key, in the exact order the TypeScript SDK emits them.
# ``shell`` is handled specially (it pulls in param1..N), so it is not listed.
_SCALAR_KEYS: list[tuple[str, str]] = [
    ("color", "color"),
    ("size", "size"),
    ("font", "font"),
    ("length", "length"),
    ("href", "href"),
]

_TRAILING_KEYS: list[tuple[str, str]] = [
    ("terminal", "terminal"),
    ("refresh", "refresh"),
    ("alternate", "alternate"),
    ("disabled", "disabled"),
    ("checked", "checked"),
    ("key", "key"),
    ("tooltip", "tooltip"),
    ("sfimage", "sfimage"),
    ("md", "md"),
    ("badge", "badge"),
    ("symbolize", "symbolize"),
]


def _quote(value: str) -> str:
    if _NEEDS_QUOTE.search(value):
        return '"' + value.replace('"', '\\"') + '"'
    return value


def _fmt(value: Any) -> str:
    # Match JS String(): booleans lowercase, numbers without a trailing ".0"
    # when they are whole, so `size=12` not `size=12.0`.
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def _encode(options: dict[str, Any] | None) -> str:
    if not options:
        return ""
    parts: list[str] = []

    def push(key: str, value: Any) -> None:
        if value is not None:
            parts.append(f"{key}={_quote(_fmt(value))}")

    for name, key in _SCALAR_KEYS:
        push(key, options.get(name))

    if options.get("shell") is not None:
        push("shell", options.get("shell"))
        for i, param in enumerate(options.get("params") or []):
            push(f"param{i + 1}", param)

    for name, key in _TRAILING_KEYS:
        push(key, options.get(name))

    return " | " + " ".join(parts) if parts else ""


class Section:
    """A menu section at a given submenu depth (0 = top level)."""

    def __init__(self, lines: list[str], depth: int) -> None:
        self._lines = lines
        self._depth = depth

    def _prefix(self) -> str:
        return "-" * (self._depth * 2)

    def item(self, text: str, **options: Any) -> "Section":
        self._lines.append(self._prefix() + text + _encode(options))
        return self

    def separator(self) -> "Section":
        self._lines.append(self._prefix() + "---")
        return self

    def submenu(self, text: str, **options: Any) -> "Section":
        """Add an item and return a ``Section`` for its submenu."""
        self.item(text, **options)
        return Section(self._lines, self._depth + 1)


class Menu:
    """The top-level menu: title line(s) plus a dropdown."""

    def __init__(self) -> None:
        self._titles: list[str] = []
        self._body: list[str] = []

    def title(self, text: str, **options: Any) -> "Menu":
        self._titles.append(text + _encode(options))
        return self

    @property
    def dropdown(self) -> Section:
        return Section(self._body, 0)

    def to_string(self) -> str:
        head = "\n".join(self._titles)
        if self._body:
            return f"{head}\n---\n" + "\n".join(self._body)
        return head

    def __str__(self) -> str:  # so `str(menu)` works like TS `toString()`
        return self.to_string()

    def print(self) -> None:
        sys.stdout.write(self.to_string() + "\n")
