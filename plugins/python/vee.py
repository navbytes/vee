"""Vee plugin SDK — typed builders that emit the xbar/SwiftBar text format Vee
parses. Zero dependencies; pure standard-library Python.

Mirrors the TypeScript SDK (``plugins/src/vee.ts``): the same builder shape,
option names, encoding order, and quoting, so a plugin reads the same in either
language and both produce byte-identical output for the same menu.
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any

__all__ = ["Menu", "Section", "WidgetCard", "widget_card", "Stat", "Gauge", "Trend", "List", "Board"]

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

    # Vee-native rich params, emitted last in a fixed order shared across SDKs:
    # sparkline, toggle, slider, progress, trackcolor, progressw, progressh.
    sparkline = options.get("sparkline")
    if sparkline is not None:
        push("sparkline", ",".join(_fmt(v) for v in sparkline))

    toggle = options.get("toggle")
    if toggle is not None:
        push("toggle", "on" if toggle else "off")

    slider = options.get("slider")
    if slider is not None:
        if isinstance(slider, dict):
            smin, smax, sval = slider["min"], slider["max"], slider["value"]
        else:  # tuple/list of (min, max, value)
            smin, smax, sval = slider
        push("slider", f"{_fmt(smin)},{_fmt(smax)},{_fmt(sval)}")

    progress = options.get("progress")
    if progress is not None:
        if isinstance(progress, (tuple, list)):  # (value, max)
            value, maximum = progress
            fraction = 0.0 if maximum == 0 else value / maximum
        elif isinstance(progress, dict):
            value, maximum = progress["value"], progress["max"]
            fraction = 0.0 if maximum == 0 else value / maximum
        else:  # already a fraction
            fraction = progress
        push("progress", _fmt(fraction))

    push("trackcolor", options.get("trackColor"))
    push("progressw", options.get("progressW"))
    push("progressh", options.get("progressH"))

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


# -----------------------------------------------------------------------------
# Widget surface contract — the rich JSON payload a plugin prints to stdout
# when invoked with VEE_TARGET=widget, instead of the xbar/SwiftBar text
# protocol above. See docs/design/widget-surface-contract.md §4. Mirrors the
# TypeScript SDK's WidgetCard field-for-field (same option names, same JSON
# key order).

# Option name -> emitted JSON key, in the exact order the TypeScript SDK
# emits them.
_CARD_KEYS: list[tuple[str, str]] = [
    ("template", "template"),
    ("title", "title"),
    ("symbol", "symbol"),
    ("tint", "tint"),
    ("value", "value"),
    ("caption", "caption"),
    ("detail", "detail"),
    ("status", "status"),
    ("progress", "progress"),
    ("trend", "trend"),
    ("items", "items"),
    ("actions", "actions"),
    ("refreshAfter", "refresh_after"),
    ("staleAfter", "stale_after"),
]


def _json_value(value: Any) -> str:
    """Serializes ``value`` to compact JSON, formatting a whole-number float
    without a trailing ``.0`` (matching ``_fmt`` / the TS and Go SDKs) —
    Python's own ``json`` module keeps ``15.0``, which would break the
    cross-language byte-identical fixture convention this SDK maintains.
    """
    if value is None:
        return "null"
    if isinstance(value, (bool, int, float)):
        return _fmt(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(_json_value(v) for v in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(f"{json.dumps(str(k))}:{_json_value(v)}" for k, v in value.items()) + "}"
    raise TypeError(f"unsupported widget card value: {value!r}")


class WidgetCard:
    """The ``VEE_TARGET=widget`` stdout payload (see the design doc §4).
    Build one with the richest data available and call
    ``str()``/``print()`` exactly once per run; each native template
    (small/medium/large) takes what fits.

    ``items``/``actions`` are plain dicts, e.g.
    ``{"label": "Orders", "value": "214", "symbol": "bag", "tint": "blue"}``
    — field order in the dict literal is preserved in the JSON output.
    """

    def __init__(self, **options: Any) -> None:
        self._options = options

    def to_string(self) -> str:
        payload: dict[str, Any] = {"vee_widget": 1}
        for name, key in _CARD_KEYS:
            value = self._options.get(name)
            if value is not None:
                payload[key] = value
        return _json_value(payload)

    def __str__(self) -> str:  # so `str(card)` works like TS `toString()`
        return self.to_string()

    def print(self) -> None:
        sys.stdout.write(self.to_string() + "\n")


def widget_card(**options: Any) -> WidgetCard:
    """Builds a widget card. Equivalent to ``WidgetCard(**options)``."""
    return WidgetCard(**options)


def Stat(**options: Any) -> WidgetCard:
    """Glyph, big value in tint, title/caption. The default template."""
    return WidgetCard(template="stat", **options)


def Gauge(**options: Any) -> WidgetCard:
    """Stat + a native gauge from ``progress``."""
    return WidgetCard(template="gauge", **options)


def Trend(**options: Any) -> WidgetCard:
    """Stat + a sparkline from ``trend``."""
    return WidgetCard(template="trend", **options)


def List(**options: Any) -> WidgetCard:
    """``title`` header + ``items`` as rows."""
    return WidgetCard(template="list", **options)


def Board(**options: Any) -> WidgetCard:
    """A compact grid of ``items`` as stat cells (KPI board)."""
    return WidgetCard(template="board", **options)
