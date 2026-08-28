"""Regression: a literal `|`/newline/backslash in plugin-supplied text must
survive Vee's parser instead of truncating or corrupting the item — see
Sources/VeePluginFormat/LineParser.swift (splitTextAndParams/parseParams's
``unescape``) for the parser half of this ``\\|``/``\\n``/``\\\\`` contract;
``_escape_text``/``_quote`` in ../vee.py are the SDK half. The TypeScript and Go
SDKs mirror this file exactly (same original text, same expected escaped line).
"""

import os
import sys
import unittest
import warnings

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from vee import Gauge, Menu  # noqa: E402


def _unescape(s: str) -> str:
    """Mirrors LineParser's ``unescape``: the parser's inverse of ``_escape_text``."""
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s) and s[i + 1] in "|n\\":
            out.append("\n" if s[i + 1] == "n" else s[i + 1])
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


class EscapingTests(unittest.TestCase):
    def test_item_text_with_pipe_and_newline_emits_sdk_parser_contract(self) -> None:
        menu = Menu()
        menu.title("T")
        menu.dropdown.item("Left | Right\nSecond line", color="red")
        # Splitting on "\n" must yield exactly 3 lines: a raw newline byte in
        # the item would otherwise be read by OutputParser as a 4th, corrupted
        # line.
        self.assertEqual(
            menu.to_string().split("\n"),
            ["T", "---", "Left \\| Right\\nSecond line | color=red"],
        )

    def test_title_text_is_escaped_the_same_way_as_item_text(self) -> None:
        menu = Menu()
        menu.title("A | B\nC")
        self.assertEqual(menu.to_string(), "A \\| B\\nC")

    def test_literal_backslash_in_param_value_is_escaped_quoted_and_round_trips(self) -> None:
        path = "C:\\Users\\me"  # one literal backslash between each segment
        menu = Menu()
        menu.title("T")
        menu.dropdown.item("plain", tooltip=path)
        line = menu.to_string().split("\n")[-1]
        self.assertTrue(line.startswith('plain | tooltip="'))
        quoted_value = line[line.index('"') + 1 : line.rindex('"')]
        self.assertEqual(_unescape(quoted_value), path)

    def test_values_needing_no_escaping_stay_unquoted(self) -> None:
        menu = Menu()
        menu.title("T")
        menu.dropdown.item("plain", color="red")
        self.assertEqual(menu.to_string().split("\n")[-1], "plain | color=red")


if __name__ == "__main__":
    unittest.main()


class QuotingAndNumbersTests(unittest.TestCase):
    """Mirrors plugins/typescript/test/escaping.test.ts — same inputs, same
    expected lines, so a divergence in either SDK fails here."""

    def test_leading_quote_forces_quoting(self) -> None:
        menu = Menu()
        menu.title("T")
        menu.dropdown.item("a", tooltip='"quoted"')
        menu.dropdown.item("b", tooltip="'tis")
        menu.dropdown.item("c", tooltip='has"inside')
        self.assertEqual(
            menu.to_string().split("\n")[2:],
            [
                'a | tooltip="\\"quoted\\""',
                "b | tooltip=\"'tis\"",
                'c | tooltip=has"inside',
            ],
        )

    def test_cross_language_whitespace_forces_quoting(self) -> None:
        menu = Menu()
        menu.title("T")
        menu.dropdown.item("a", tooltip="x\ry")
        menu.dropdown.item("b", tooltip="x\u00a0y")
        self.assertEqual(
            menu.to_string().split("\n")[2:],
            ['a | tooltip="x\ry"', 'b | tooltip="x\u00a0y"'],
        )

    def test_numbers_use_the_shared_ecma_rule(self) -> None:
        menu = Menu()
        menu.title("T")
        menu.dropdown.item("n", sparkline=[1000000.0, 1234567.0, 1e-7, 1e20, 1e21, -0.0])
        self.assertEqual(
            menu.to_string().split("\n")[-1],
            "n | sparkline=1000000,1234567,1e-7,100000000000000000000,1e+21,0",
        )


class OptionNameTests(unittest.TestCase):
    """The Python SDK used to drop unknown options in silence, so a typo — or
    the idiomatic snake_case spelling, back when options were camelCase — 
    emitted nothing at all. TypeScript rejects those at compile time and Go
    rejects them as unknown struct fields; these assert Python now does too."""

    def test_unknown_option_raises(self) -> None:
        menu = Menu()
        for bad in ("colour", "sfimg", "progressWidth"):
            with self.assertRaises(TypeError):
                menu.dropdown.item("x", **{bad: "value"})

    def test_unknown_option_suggests_the_real_name(self) -> None:
        menu = Menu()
        with self.assertRaises(TypeError) as caught:
            menu.dropdown.item("x", progressw=10)
        self.assertIn("progress_w", str(caught.exception))

    def test_deprecated_camelcase_still_works_and_warns(self) -> None:
        old, new = Menu(), Menu()
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            old.dropdown.item(
                "row", progress=0.5, trackColor="gray", progressW=200, progressH=6
            )
            self.assertEqual(len(caught), 3)
            self.assertTrue(all(w.category is DeprecationWarning for w in caught))
        new.dropdown.item(
            "row",
            progress=0.5,
            progress_track_color="gray",
            progress_w=200,
            progress_h=6,
        )
        self.assertEqual(old.to_string(), new.to_string())

    def test_python_only_tuple_forms_warn_but_match_the_mapping_form(self) -> None:
        """The tuple shorthands are the per-language sugar that stops a Python
        plugin porting: TypeScript takes only the object form, Go only the
        struct. They still work, and must agree with the portable spelling."""
        tuples, mappings = Menu(), Menu()
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            tuples.dropdown.item("row", progress=(72, 100), slider=(0, 100, 40))
            self.assertEqual(len(caught), 2)
            self.assertTrue(all(w.category is DeprecationWarning for w in caught))
        mappings.dropdown.item(
            "row",
            progress={"value": 72, "max": 100},
            slider={"min": 0, "max": 100, "value": 40},
        )
        self.assertEqual(tuples.to_string(), mappings.to_string())


class WidgetCardOptionTests(unittest.TestCase):
    """`WidgetCard` stored `**options` verbatim and emitted only the names it
    recognised, so a typo — or `refresh_after`, the spelling every other option
    in this SDK and the JSON key itself use — vanished with no error and no
    output key. It now goes through the same rule `Menu` uses."""

    def test_unknown_card_option_raises(self) -> None:
        with self.assertRaises(TypeError):
            Gauge(title="T", totally_made_up_option=99)

    def test_snake_case_names_are_canonical(self) -> None:
        self.assertIn('"refresh_after":300', str(Gauge(title="T", refresh_after=300)))

    def test_camelcase_names_still_work_and_warn(self) -> None:
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            old = str(Gauge(title="T", refreshAfter=300, staleAfter=900))
            self.assertEqual(len(caught), 2)
            self.assertTrue(all(w.category is DeprecationWarning for w in caught))
        self.assertEqual(old, str(Gauge(title="T", refresh_after=300, stale_after=900)))

    def test_misspelling_suggests_the_real_name(self) -> None:
        with self.assertRaises(TypeError) as caught:
            Gauge(title="T", refreshafter=300)
        self.assertIn("refresh_after", str(caught.exception))
