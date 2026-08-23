"""Vee plugin SDK — typed builders that emit the xbar/SwiftBar text format Vee
parses. Zero dependencies; pure standard-library Python.

Mirrors the TypeScript SDK (``plugins/typescript/vee.ts``): the same builder shape,
option names, encoding order, and quoting, so a plugin reads the same in either
language and both produce byte-identical output for the same menu.
"""

from __future__ import annotations

import json
import sys
import warnings
from typing import Any

__all__ = ["Menu", "Section", "WidgetCard", "widget_card", "Stat", "Gauge", "Trend", "List", "Board"]

# The characters that force a value through the quoted path: JavaScript's `\s`
# set (the reference the three SDKs share), plus the two the format itself
# reserves. Spelled out by code point rather than borrowed from Python's own
# `\s`, which additionally matches U+001C-U+001F and U+0085 and does not match
# U+FEFF -- close enough to look right, different enough to break
# byte-identical output.
_QUOTE_FORCING = frozenset(
    "\t\n\v\f\r \u00a0\u1680\u2028\u2029\u202f\u205f\u3000\ufeff|\\"
) | frozenset(chr(c) for c in range(0x2000, 0x200B))


def _needs_quote(value: str) -> bool:
    return any(ch in _QUOTE_FORCING for ch in value)


# Option name -> emitted key, in the exact order the TypeScript SDK emits them.
# ``shell`` is handled specially (it pulls in param1..N), so it is not listed.
_SCALAR_KEYS: list[tuple[str, str]] = [
    ("color", "color"),
    ("size", "size"),
    ("font", "font"),
    ("length", "length"),
    ("trim", "trim"),
    ("ansi", "ansi"),
    ("emojize", "emojize"),
    ("href", "href"),
]

_TRAILING_KEYS: list[tuple[str, str]] = [
    ("terminal", "terminal"),
    ("refresh", "refresh"),
    ("dropdown", "dropdown"),
    ("alternate", "alternate"),
    ("disabled", "disabled"),
    ("checked", "checked"),
    ("key", "key"),
    ("tooltip", "tooltip"),
    ("image", "image"),
    ("template_image", "templateimage"),
    ("sfimage", "sfimage"),
    # sfcolor is emitted here too -- see the branch in _encode; it accepts a
    # list as well as a scalar, so it cannot ride this plain key table.
    ("sf_size", "sfsize"),
    ("sf_config", "sfconfig"),
    ("md", "md"),
    ("badge", "badge"),
    ("symbolize", "symbolize"),
    ("webview", "webview"),
    ("webview_w", "webvieww"),
    ("webview_h", "webviewh"),
    ("shortcut", "shortcut"),
    ("header", "header"),
    ("accessory", "accessory"),
]


def _escape_text(value: str) -> str:
    """Escapes the three characters Vee's parser (LineParser.splitTextAndParams/
    parseParams) reads back as `\\|`/`\\n`/`\\\\`: a literal `|` would otherwise be
    read as the text/params delimiter, and a literal newline would otherwise
    split a plugin's single stdout line into two corrupted ones. Order matters:
    backslashes are escaped first, or the backslash inserted for `|`/newline
    would itself get re-escaped.
    """
    return value.replace("\\", "\\\\").replace("|", "\\|").replace("\n", "\\n")


def _quote(value: str) -> str:
    escaped = _escape_text(value)
    # Backslash also forces quoting: an unquoted (bare) value is never
    # unescaped by the parser, so anything containing an escape must go
    # through the quoted path, which is.
    #
    # A leading quote character forces it too: the parser decides a value is
    # quoted by looking at its first character, so emitting ``"a"`` bare would
    # round-trip back as ``a`` with the quotes eaten. Values that merely
    # *contain* a quote are safe bare -- only the first position is read as a
    # delimiter.
    if _needs_quote(value) or value[:1] in ('"', "'"):
        return '"' + escaped.replace('"', '\\"') + '"'
    return escaped


def _fmt_float(x: float) -> str:
    """Formats ``x`` exactly as JavaScript's ``String(Number)`` does
    (ECMA-262 Number::toString).

    Python's own ``str`` agrees with JavaScript across the ordinary range but
    parts company at the edges -- ``1e21`` prints in full, ``1e-07`` carries a
    padded exponent -- and Go's ``'g'`` verb parts company much earlier still,
    at 1e6. Since the three SDKs commit to byte-identical output, the format
    has to be one written-down rule rather than three native defaults.
    """
    if x != x:
        return "NaN"
    if x == float("inf"):
        return "Infinity"
    if x == float("-inf"):
        return "-Infinity"
    if x == 0:
        return "0"  # also normalizes -0.0, matching String(-0)

    negative = x < 0
    s = repr(abs(x))  # shortest round-trippable digits
    if "e" in s:
        mantissa, _, exponent = s.partition("e")
        exp10 = int(exponent)
    else:
        mantissa, exp10 = s, 0
    int_part, _, frac_part = mantissa.partition(".")

    all_digits = int_part + frac_part
    stripped = all_digits.lstrip("0")
    leading_zeros = len(all_digits) - len(stripped)
    digits = stripped.rstrip("0") or "0"
    k = len(digits)
    n = len(int_part) + exp10 - leading_zeros  # position of the decimal point

    if k <= n <= 21:
        out = digits + "0" * (n - k)
    elif 0 < n <= 21:
        out = digits[:n] + "." + digits[n:]
    elif -6 < n <= 0:
        out = "0." + "0" * (-n) + digits
    else:
        e = n - 1
        sign = "+" if e >= 0 else "-"
        head = digits if k == 1 else digits[0] + "." + digits[1:]
        out = head + "e" + sign + str(abs(e))
    return "-" + out if negative else out


def _fmt(value: Any) -> str:
    # Match JS String(): booleans lowercase, numbers formatted by the shared
    # ECMA-262 rule so `size=12` is not `size=12.0` and a 1e6 sparkline point
    # is not `1e+06`.
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return _fmt_float(value)
    if isinstance(value, int):
        # Python ints are unbounded; JS would render one past 2**53 as a
        # double. Route the ones that reach exponent form through the float
        # rule so the two agree.
        return str(value) if abs(value) < 10**21 else _fmt_float(float(value))
    return str(value)


# Every option `item()`/`title()` accepts, and the camelCase spellings kept
# working from before the SDK moved to snake_case.
#
# Two problems this solves at once. Unknown keyword arguments used to be
# dropped in silence -- `colour="red"` or a mistyped `sfimg=` emitted nothing,
# with no error -- where the TypeScript SDK rejects them at compile time and
# the Go SDK rejects them as unknown struct fields. And the SDK's own spelling
# was inconsistent: menu options were camelCase while layout-node options were
# snake_case, so the spelling a Python author would naturally reach for was
# exactly the one that failed silently.
_OPTION_NAMES = frozenset(
    [name for name, _ in _SCALAR_KEYS]
    + [name for name, _ in _TRAILING_KEYS]
    + [
        "shell", "params", "sf_color",
        "sparkline", "sparkline_w", "sparkline_h", "sparkline_color",
        "toggle", "slider",
        "progress", "progress_track_color", "progress_w", "progress_h",
        "chart",
    ]
)

# Deprecated camelCase spelling -> current snake_case name. Accepted with a
# DeprecationWarning so existing plugins keep running; scheduled for removal in
# the next major version.
_DEPRECATED_ALIASES = {
    "templateImage": "template_image",
    "sfColor": "sf_color",
    "sfSize": "sf_size",
    "sfConfig": "sf_config",
    "webviewW": "webview_w",
    "webviewH": "webview_h",
    "trackColor": "progress_track_color",
    "progressW": "progress_w",
    "progressH": "progress_h",
}


def _normalize_options(options: dict[str, Any]) -> dict[str, Any]:
    """Maps deprecated spellings onto current ones and rejects unknown keys."""
    out: dict[str, Any] = {}
    for name, value in options.items():
        current = _DEPRECATED_ALIASES.get(name)
        if current is not None:
            warnings.warn(
                f"{name!r} is the pre-snake_case spelling; use {current!r}. "
                "The old name still works and will be removed in the next "
                "major version.",
                DeprecationWarning,
                stacklevel=3,
            )
            name = current
        elif name not in _OPTION_NAMES:
            close = sorted(n for n in _OPTION_NAMES if n.replace("_", "") == name.lower().replace("_", ""))
            hint = f" Did you mean {close[0]!r}?" if close else ""
            raise TypeError(f"unknown option {name!r}.{hint}")
        out[name] = value
    return out


def _warn_tuple_form(option: str, mapping: str) -> None:
    """Warns about a tuple/list shorthand that only this SDK accepts.

    The three SDKs promise the same builder shape in any language, and these
    shorthands break that: TypeScript takes only the object form and Go only
    the struct, so a plugin written with a tuple does not port. The mapping
    form works identically in all three.
    """
    warnings.warn(
        f"the tuple form of {option}= is a Python-only shorthand the other SDKs "
        f"cannot express; pass {mapping} instead. It still works and will be "
        "removed in the next major version.",
        DeprecationWarning,
        stacklevel=4,
    )


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
        if key == "sfsize":
            # `sfcolor` sits between `sfimage` and `sfsize` in the order the
            # three SDKs share. It accepts one colour or a list of them (one
            # per layer of a multicolour symbol), so it needs its own branch.
            sf_color = options.get("sf_color")
            if sf_color is not None:
                push("sfcolor", ",".join(str(c) for c in sf_color)
                     if isinstance(sf_color, (list, tuple)) else sf_color)
        push(key, options.get(name))

    # Vee-native rich params, emitted last in a fixed order shared across SDKs:
    # sparkline, toggle, slider, progress, trackcolor, progressw, progressh,
    # then the chart shape with its labels/colors.
    sparkline = options.get("sparkline")
    if sparkline is not None:
        push("sparkline", ",".join(_fmt(v) for v in sparkline))
    # ``sparkline_w`` takes points or ``"full"`` -- the same width vocabulary as
    # ``progress_w`` and ``chart["w"]``.
    push("sparklinew", options.get("sparkline_w"))
    push("sparklineh", options.get("sparkline_h"))
    push("sparklinecolor", options.get("sparkline_color"))

    toggle = options.get("toggle")
    if toggle is not None:
        push("toggle", "on" if toggle else "off")

    slider = options.get("slider")
    if slider is not None:
        if isinstance(slider, dict):
            smin, smax, sval = slider["min"], slider["max"], slider["value"]
        else:  # tuple/list of (min, max, value)
            _warn_tuple_form("slider", '{"min": 0, "max": 100, "value": 40}')
            smin, smax, sval = slider
        push("slider", f"{_fmt(smin)},{_fmt(smax)},{_fmt(sval)}")

    progress = options.get("progress")
    if progress is not None:
        # A fraction goes out as-is; a value/max pair goes out as the format's
        # own two-argument form (`progress=72,100`), which Vee divides on
        # parse. That keeps the author's numbers on the wire rather than a
        # pre-divided float.
        if isinstance(progress, (tuple, list)):  # (value, max)
            _warn_tuple_form("progress", '{"value": 72, "max": 100}')
            value, maximum = progress
            push("progress", f"{_fmt(value)},{_fmt(maximum)}")
        elif isinstance(progress, dict):
            push("progress", f"{_fmt(progress['value'])},{_fmt(progress['max'])}")
        else:
            push("progress", _fmt(progress))

    push("progresstrackcolor", options.get("progress_track_color"))
    # ``progress_w`` takes points or ``"full"`` -- the same width vocabulary as
    # ``chart["w"]`` below.
    push("progressw", options.get("progress_w"))
    push("progressh", options.get("progress_h"))

    # Categorical share chart: `pie=`/`donut=`/`stackedbar=` plus its positional
    # `chartlabels=`/`chartcolors=`. All three shapes take the same data, so the
    # shape is just the key the values are pushed under. Vee reads labels and
    # colors as comma-separated lists — keep commas out of segment names.
    chart = options.get("chart")
    if chart is not None:
        push(chart["kind"], ",".join(_fmt(v) for v in chart["values"]))
        # Inline size in points. A pie/donut is a circle, so either knob sizes
        # both sides; a stacked bar takes them independently. ``"full"`` is the
        # one non-numeric width: stretch to the row's own width — stacked bars
        # only, since a circle has no free width.
        w = chart.get("w")
        if w is not None:
            push("chartw", w if isinstance(w, str) else _fmt(w))
        if chart.get("h") is not None:
            push("charth", _fmt(chart["h"]))
        labels = chart.get("labels")
        if labels is not None:
            push("chartlabels", ",".join(str(v) for v in labels))
        colors = chart.get("colors")
        if colors is not None:
            push("chartcolors", ",".join(str(v) for v in colors))

    return " | " + " ".join(parts) if parts else ""


class Section:
    """A menu section at a given submenu depth (0 = top level)."""

    def __init__(self, lines: list[str], depth: int) -> None:
        self._lines = lines
        self._depth = depth

    def _prefix(self) -> str:
        return "-" * (self._depth * 2)

    def item(self, text: str, **options: Any) -> "Section":
        self._lines.append(self._prefix() + _escape_text(text) + _encode(_normalize_options(options)))
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
        self._titles.append(_escape_text(text) + _encode(_normalize_options(options)))
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
    ("layout", "layout"),
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


# ── Layout tree ──────────────────────────────────────────────────────────────
# The composable escape hatch alongside the five preset templates. Nodes are
# built as ordered dicts (``_json_value`` preserves insertion order), so keys
# land in the canonical order the three SDKs share and output is byte-identical.
# Style keys are snake_case (Python idiom); the wire format is snake_case too.

_STYLE_KEYS = ["font", "tint", "align", "padding", "line_limit", "monospaced_digit", "min_scale", "fill"]
_FONT_KEYS = ["size", "point_size", "weight", "design"]


def _font(f: dict[str, Any]) -> dict[str, Any]:
    return {k: f[k] for k in _FONT_KEYS if f.get(k) is not None}


def _style(s: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for k in _STYLE_KEYS:
        v = s.get(k)
        if v is not None:
            out[k] = _font(v) if k == "font" else v
    return out


# Which options each node type accepts. `Columns` on a text node or `min_length`
# on a gauge is a mistake, not a no-op: the TypeScript SDK's option types reject
# those at compile time and the Go SDK's typed option kinds reject them too, so
# Python rejects them here rather than shipping a key the renderer ignores.
_COMMON_NODE_OPTS = frozenset({"families", "style"})
_NODE_OPTS = {
    "vstack": _COMMON_NODE_OPTS | {"align", "spacing"},
    "hstack": _COMMON_NODE_OPTS | {"align", "spacing"},
    "zstack": _COMMON_NODE_OPTS | {"align", "spacing"},
    "grid": _COMMON_NODE_OPTS | {"align", "spacing", "columns"},
    "text": _COMMON_NODE_OPTS,
    "image": _COMMON_NODE_OPTS,
    "sparkline": _COMMON_NODE_OPTS,
    "gauge": _COMMON_NODE_OPTS | {"gauge_style"},
    "spacer": {"families", "min_length"},
    "divider": {"families"},
}


def _check_node_opts(node_type: str, opts: dict[str, Any]) -> None:
    allowed = _NODE_OPTS[node_type]
    for name, value in opts.items():
        if value is None:
            continue
        if name not in allowed:
            raise TypeError(
                f"{name!r} is not a valid option for a {node_type!r} node; "
                f"it accepts {', '.join(sorted(allowed))}"
            )


def _node(
    type: str,
    *,
    text: str | None = None,
    symbol: str | None = None,
    value: float | None = None,
    values: list[float] | None = None,
    gauge_style: str | None = None,
    align: str | None = None,
    spacing: float | None = None,
    columns: int | None = None,
    min_length: float | None = None,
    families: list[str] | None = None,
    style: dict[str, Any] | None = None,
    children: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Builds a node dict with keys inserted in the shared canonical order."""
    # `text`/`symbol`/`value`/`values`/`children` are positional payload set by
    # the builders themselves, not caller-supplied options, so only the option
    # arguments are checked.
    _check_node_opts(type, {
        "gauge_style": gauge_style, "align": align, "spacing": spacing,
        "columns": columns, "min_length": min_length, "families": families,
        "style": style,
    })
    node: dict[str, Any] = {"type": type}
    if text is not None:
        node["text"] = text
    if symbol is not None:
        node["symbol"] = symbol
    if value is not None:
        node["value"] = value
    if values is not None:
        node["values"] = values
    if gauge_style is not None:
        node["gauge_style"] = gauge_style
    if align is not None:
        node["align"] = align
    if spacing is not None:
        node["spacing"] = spacing
    if columns is not None:
        node["columns"] = columns
    if min_length is not None:
        node["min_length"] = min_length
    if families is not None:
        node["families"] = families
    if style is not None:
        node["style"] = _style(style)
    if children is not None:
        node["children"] = children
    return node


class Node:
    """Builders for the layout tree, namespaced (``Node.VStack(...)``) so they
    don't collide with the card-level template builders (``Stat``/``Gauge``/…).
    Each returns a plain dict; pass the root as ``widget_card(layout=...)``.
    """

    @staticmethod
    def VStack(children: list[dict[str, Any]], **opts: Any) -> dict[str, Any]:
        """A vertical stack."""
        return _node("vstack", children=children, **opts)

    @staticmethod
    def HStack(children: list[dict[str, Any]], **opts: Any) -> dict[str, Any]:
        """A horizontal stack — side-by-side regions."""
        return _node("hstack", children=children, **opts)

    @staticmethod
    def ZStack(children: list[dict[str, Any]], **opts: Any) -> dict[str, Any]:
        """A depth stack — overlays and rings."""
        return _node("zstack", children=children, **opts)

    @staticmethod
    def Grid(children: list[dict[str, Any]], **opts: Any) -> dict[str, Any]:
        """A grid of ``columns`` (default 2, clamped 1…4)."""
        return _node("grid", children=children, **opts)

    @staticmethod
    def Text(text: str, **opts: Any) -> dict[str, Any]:
        """A text run."""
        return _node("text", text=text, **opts)

    @staticmethod
    def Image(symbol: str, **opts: Any) -> dict[str, Any]:
        """An SF Symbol glyph (v1 renders SF Symbols only)."""
        return _node("image", symbol=symbol, **opts)

    @staticmethod
    def Gauge(value: float, **opts: Any) -> dict[str, Any]:
        """A gauge — ``linear`` (default) or ``circular``. ``value`` is 0…1."""
        return _node("gauge", value=value, **opts)

    @staticmethod
    def Sparkline(values: list[float], **opts: Any) -> dict[str, Any]:
        """A dependency-free line chart from ``values``."""
        return _node("sparkline", values=values, **opts)

    @staticmethod
    def Spacer(**opts: Any) -> dict[str, Any]:
        """Flexible empty space."""
        return _node("spacer", **opts)

    @staticmethod
    def Divider(**opts: Any) -> dict[str, Any]:
        """A hairline divider."""
        return _node("divider", **opts)
