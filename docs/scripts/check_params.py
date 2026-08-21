#!/usr/bin/env python3
"""Fail when the menu-line parameter list disagrees across its three surfaces.

The same list of parameter keys is written down three times:

  1. ``LineParser.mapParams``      — the switch that actually parses them
  2. ``LineParameterKeys``         — the public set the CLI linter uses
  3. ``docs/_content/plugin-authoring.md`` — the table plugin authors read

Swift cannot enumerate a switch's cases, so (2) is a hand-written mirror of (1)
and (3) is prose that cannot be generated. This script is what keeps all three
honest: it scrapes each surface and exits non-zero on any disagreement.

It exists because (3) silently fell behind: the composable widget layout tree
shipped with no reference at all, and ``Linter``'s own copy of the list carried
a comment conceding it was "Hand-maintained, not derived".

    python3 docs/scripts/check_params.py

Pure standard library, matching the project policy and docs/scripts/build_guide.py.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

PARSER = os.path.join(ROOT, "Sources/VeePluginFormat/LineParser.swift")
KEYS = os.path.join(ROOT, "Sources/VeePluginFormat/LineParameterKeys.swift")
DOCS = os.path.join(ROOT, "docs/_content/plugin-authoring.md")

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


def doc_keys():
    """Keys named in the parameter table in the authoring reference.

    Only the table's first column counts — a key mentioned in prose is not the
    same as a key documented with a description.
    """
    out = set()
    in_table = False
    for ln in open(DOCS):
        if ln.startswith("| Parameter |"):
            in_table = True
            continue
        if in_table:
            if not ln.startswith("|"):
                break
            first = ln.split("|")[1]
            for k in re.findall(r"`([^`]+)`", first):
                k = k.lower()
                # param0/param1/... are one open-ended family, not N parameters
                out.add("paramN" if re.fullmatch(r"param\d+", k) else k)
    return out


def main():
    surfaces = {"parser": parser_keys(), "keys": public_keys(), "docs": doc_keys()}
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

    if problems:
        print("Menu-line parameters disagree across their three surfaces:\n")
        for p in problems:
            print("  " + p)
        print("\n  parser = LineParser.mapParams  |  keys = LineParameterKeys"
              "  |  docs = plugin-authoring.md")
        print("\nAdd the parameter to whichever surface is missing it, or record a"
              "\ndeliberate omission in EXCEPTIONS in this script.")
        return 1

    print("ok: %d parameters agree across parser, linter keys, and docs" % len(every))
    return 0


if __name__ == "__main__":
    sys.exit(main())
