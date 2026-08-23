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

test("a leading quote character forces quoting so the value round-trips", () => {
  // The parser decides a value is quoted by looking at its first character, so
  // a bare `"quoted"` would come back as `quoted` with the delimiters eaten.
  const menu = new Menu();
  menu.title("T");
  menu.dropdown.item("a", { tooltip: `"quoted"` });
  menu.dropdown.item("b", { tooltip: `'tis` });
  // A quote that is merely *contained* is safe bare — only position 0 is read
  // as a delimiter — and must stay unquoted so existing output is unchanged.
  menu.dropdown.item("c", { tooltip: `has"inside` });
  const lines = menu.toString().split("\n").slice(2);
  assert.deepEqual(lines, [
    'a | tooltip="\\"quoted\\""',
    `b | tooltip="'tis"`,
    'c | tooltip=has"inside',
  ]);
});

test("whitespace the three languages classify differently still forces quoting", () => {
  // Carriage return and U+00A0 are in JavaScript's `\s` but not in every
  // language's native whitespace class; all three SDKs must agree regardless.
  const menu = new Menu();
  menu.title("T");
  menu.dropdown.item("a", { tooltip: "x\ry" });
  menu.dropdown.item("b", { tooltip: "x\u00a0y" });
  assert.deepEqual(menu.toString().split("\n").slice(2), [
    'a | tooltip="x\ry"',
    'b | tooltip="x\u00a0y"',
  ]);
});

test("numbers are formatted by the shared ECMA-262 rule, not a native default", () => {
  // 1e6 is where Go's 'g' verb would switch to exponent notation; 1e-7 and
  // 1e21 are the boundaries of the plain-decimal range.
  const menu = new Menu();
  menu.title("T");
  menu.dropdown.item("n", { sparkline: [1000000, 1234567, 1e-7, 1e20, 1e21, -0] });
  assert.equal(
    menu.toString().split("\n").at(-1),
    "n | sparkline=1000000,1234567,1e-7,100000000000000000000,1e+21,0",
  );
});
