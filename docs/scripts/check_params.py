#!/usr/bin/env python3
"""Fail when the menu-line parameter list disagrees across its three surfaces.

The same list of parameter keys is written down three times:

  1. ``LineParser.mapParams``      — the switch that actually parses them
  2. ``LineParameterKeys``         — the public set the CLI linter uses
  3. ``docs/api/params.json``      — the record the published tables are built from

Swift cannot enumerate a switch's cases, so (2) is a hand-written mirror of (1),
and (3) is authored by hand because a type, a default, and a sentence are things
only a person can write. This script is what keeps all three honest: it scrapes
each surface and exits non-zero on any disagreement.

It exists because (3) silently fell behind: the composable widget layout tree
shipped with no reference at all, and ``Linter``'s own copy of the list carried
a comment conceding it was "Hand-maintained, not derived".

Surface (3) used to be the Markdown table itself, scraped with a regex. It is
now structured data, and the published tables are generated from it by
``build_reference.py`` — so this check reads what the docs *mean* rather than
recovering it from how they are rendered.

The script also verifies the numbers. Names agreeing is not enough: the docs
stated a chart's default size and its 8-200 point clamp in prose, while the
values lived in ``ChartParams.swift``, and nothing failed when one moved. Every
constant the documentation states is recorded in ``params.json`` beside the
symbol it mirrors, and compared against that declaration here.

Vee's three official SDKs (TypeScript, Python, Go) — formerly checked here as
three further surfaces — are retired; see openspec/changes/retire-plugin-sdks.

    python3 docs/scripts/check_params.py

Pure standard library: the guard scripts stay dependency-free even though
the site build no longer is.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

PARSER = os.path.join(ROOT, "Sources/VeePluginFormat/LineParser.swift")
KEYS = os.path.join(ROOT, "Sources/VeePluginFormat/LineParameterKeys.swift")
SPEC = os.path.join(ROOT, "docs/api/params.json")

# Parameters deliberately absent from one surface. Every entry needs a reason:
# an intentional omission must be distinguishable from an oversight, and must
# be visible in review rather than buried in a diff.
EXCEPTIONS = {
    # key: (surfaces it may be missing from, why)
    "paramN": ({"parser", "keys"},
               "the positional param0..N family is open-ended, so it is matched by "
               "prefix in LineParser and LineParameterKeys.isRecognized rather than "
               "enumerated as cases or set members"),
}


def parser_keys():
    """Keys from the top-level `switch key {` in LineParser.mapParams."""
    src = open(PARSER).read().split("\n")
    start = next(i for i, ln in enumerate(src) if ln.strip() == "switch key {")
    indent = len(src[start]) - len(src[start].lstrip())
    out = set()
    for ln in src[start + 1:]:
        stripped = ln.strip()
        if stripped == "}" and (len(ln) - len(ln.lstrip())) == indent:
            break
        if (len(ln) - len(ln.lstrip())) != indent:
            continue
        m = re.match(r"\s*case\s+(.*?):", ln)
        if m:
            out.update(re.findall(r'"([^"]+)"', m.group(1)))
    return out


def public_keys():
    """Keys from LineParameterKeys.recognized."""
    src = open(KEYS).read()
    body = src[src.index("recognized: Set<String> = ["):]
    body = body[:body.index("]")]
    return set(re.findall(r'"([^"]+)"', body))


def spec():
    """docs/api/params.json, the authored parameter record."""
    with open(SPEC, encoding="utf-8") as handle:
        return json.load(handle)


def doc_keys(data):
    """Keys the published reference documents, from the parameter record.

    A key and its aliases both count: `shell` and `bash` are one record but two
    spellings the parser dispatches on, so both have to be present for the sets
    to line up.
    """
    out = set()
    for param in data["parameters"]:
        key = param["key"]
        # param0/param1/... are one open-ended family, not N parameters.
        out.add("paramN" if re.fullmatch(r"param\d+", key) else key)
        out.update(param.get("aliases", []))
    return out


def swift_constant(path, symbol, member=None):
    """A `public static let` value read from Swift source.

    Regex against source, like `parser_keys` above, and for the same reason:
    Swift cannot be asked what its declarations evaluate to without building
    and running something. A reformat breaks this loudly, which is the correct
    direction for a guard to fail in.
    """
    owner, name = symbol.split(".")[-2:]
    src = open(os.path.join(ROOT, path), encoding="utf-8").read()
    # Scope to the declaring type before matching. `ProgressParams` and
    # `SparklineStyle` both declare `defaultWidth` in the same file, so an
    # unscoped search silently reads the wrong one — which is exactly how this
    # check would have reported a passing drift.
    declaration = re.search(
        r"(?:struct|enum|final class|class)\s+%s\b" % re.escape(owner), src)
    if not declaration:
        return None
    src = src[declaration.end():]
    following = re.search(
        r"\n(?:public\s+)?(?:struct|enum|final class|class)\s+\w", src)
    if following:
        src = src[:following.start()]
    match = re.search(
        r"static let %s(?::[^=]+)?\s*=\s*([^\n]+)" % re.escape(name), src)
    if not match:
        return None
    raw = match.group(1).strip().rstrip(",")
    if member:  # a ClosedRange: `8...200`
        bounds = re.match(r"([\d.]+)\s*\.\.\.\s*([\d.]+)", raw)
        if not bounds:
            return None
        raw = bounds.group(1 if member == "lowerBound" else 2)
    try:
        return float(raw)
    except ValueError:
        return None


def constant_problems(data):
    """Every documented constant, against the declaration it mirrors."""
    problems = []
    for const in data.get("constants", []):
        actual = swift_constant(const["file"], const["symbol"], const.get("member"))
        where = const["symbol"] + ("." + const["member"] if const.get("member") else "")
        if actual is None:
            problems.append(
                "%s: could not read %s from %s — the declaration was renamed or "
                "reformatted, and this check needs updating"
                % (const["id"], where, const["file"]))
        elif actual != float(const["value"]):
            problems.append(
                "%s: params.json says %s, %s says %s (%s)"
                % (const["id"], const["value"], where,
                   int(actual) if actual == int(actual) else actual,
                   const["statedAs"]))
    return problems


def main():
    data = spec()
    surfaces = {"parser": parser_keys(), "keys": public_keys(), "docs": doc_keys(data)}
    every = set().union(*surfaces.values())

    problems = []
    for key in sorted(every):
        missing = {name for name, keys in surfaces.items() if key not in keys}
        if not missing:
            continue
        allowed, _ = EXCEPTIONS.get(key, (set(), ""))
        unexplained = missing - allowed
        if unexplained:
            problems.append("%-16s missing from: %s" % (key, ", ".join(sorted(unexplained))))

    for name, keys in surfaces.items():
        if not keys:
            problems.append("scraped 0 keys from %s — the format it is parsed from probably changed" % name)

    numbers = constant_problems(data)

    if problems:
        print("Menu-line parameters disagree across their three surfaces:\n")
        for p in problems:
            print("  " + p)
        print("\n  parser = LineParser.mapParams  |  keys = LineParameterKeys"
              "  |  docs = plugin-authoring.md")
        print("\nAdd the parameter to whichever surface is missing it, or record a"
              "\ndeliberate omission in EXCEPTIONS in this script.")
        if numbers:
            print()
            report_numbers(numbers)
        return 1

    if numbers:
        report_numbers(numbers)
        return 1

    print("ok: %d parameters agree across the parser, the linter keys, and the docs"
          % len(every))
    print("ok: %d documented constants match the Swift that declares them"
          % len(data.get("constants", [])))
    return 0


def report_numbers(problems):
    print("Documented constants disagree with the implementation:\n")
    for problem in problems:
        print("  " + problem)
    print("\nThe implementation is the truth. Update the value in "
          "docs/api/params.json,\nthen re-run docs/scripts/build_reference.py "
          "so the published tables follow.")


if __name__ == "__main__":
    sys.exit(main())
