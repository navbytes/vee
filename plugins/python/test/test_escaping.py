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

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from vee import Menu  # noqa: E402


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
