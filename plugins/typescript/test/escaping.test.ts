// Regression: a literal `|`/newline/backslash in plugin-supplied text must
// survive Vee's parser instead of truncating or corrupting the item — see
// Sources/VeePluginFormat/LineParser.swift (splitTextAndParams/parseParams's
// `unescape`) for the parser half of this `\|`/`\n`/`\\` contract; `escapeText`/
// `quote` in ../vee.ts are the SDK half. The Python and Go SDKs mirror this
// file exactly (same original text, same expected escaped line).
import { test } from "node:test";
import assert from "node:assert/strict";
import { Menu } from "../vee.ts";

/** Mirrors LineParser's `unescape`: the parser's inverse of `escapeText`. */
function unescape(s: string): string {
  let out = "";
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "\\" && i + 1 < s.length && "|n\\".includes(s[i + 1])) {
      out += s[i + 1] === "n" ? "\n" : s[i + 1];
      i++;
    } else {
      out += s[i];
    }
  }
  return out;
}

test("item text containing | and a newline emits the SDK/parser \\|/\\n contract", () => {
  const menu = new Menu();
  menu.title("T");
  menu.dropdown.item("Left | Right\nSecond line", { color: "red" });
  // Splitting on "\n" must yield exactly 3 lines: a raw newline byte in the
  // item would otherwise be read by OutputParser as a 4th, corrupted line.
  assert.deepEqual(menu.toString().split("\n"), ["T", "---", "Left \\| Right\\nSecond line | color=red"]);
});

test("title text is escaped the same way as dropdown item text", () => {
  const menu = new Menu();
  menu.title("A | B\nC");
  assert.equal(menu.toString(), "A \\| B\\nC");
});

test("a literal backslash in a param value is escaped, quoted, and round-trips", () => {
  const path = "C:\\Users\\me"; // one literal backslash between each segment
  const menu = new Menu();
  menu.title("T");
  menu.dropdown.item("plain", { tooltip: path });
  const line = menu.toString().split("\n").at(-1)!;
  assert.match(line, /^plain \| tooltip="/);
  const quotedValue = line.slice(line.indexOf('"') + 1, line.lastIndexOf('"'));
  assert.equal(unescape(quotedValue), path);
});

test("values needing no escaping stay unquoted, matching prior behavior", () => {
  const menu = new Menu();
  menu.title("T");
  menu.dropdown.item("plain", { color: "red" });
  assert.equal(menu.toString().split("\n").at(-1), "plain | color=red");
});
