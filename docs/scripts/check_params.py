#!/usr/bin/env python3
"""Fail when the menu-line parameter list disagrees across its six surfaces.

The same list of parameter keys is written down six times:

  1. ``LineParser.mapParams``      — the switch that actually parses them
  2. ``LineParameterKeys``         — the public set the CLI linter uses
  3. ``docs/_content/plugin-authoring.md`` — the table plugin authors read
  4. ``plugins/typescript/vee.ts`` — what the TypeScript SDK can emit
  5. ``plugins/python/vee.py``     — what the Python SDK can emit
  6. ``plugins/go/vee.go``         — what the Go SDK can emit

Swift cannot enumerate a switch's cases, so (2) is a hand-written mirror of (1)
and (3) is prose that cannot be generated. This script is what keeps all six
honest: it scrapes each surface and exits non-zero on any disagreement.

It exists because (3) silently fell behind: the composable widget layout tree
shipped with no reference at all, and ``Linter``'s own copy of the list carried
a comment conceding it was "Hand-maintained, not derived".

Surfaces (4)-(6) were added after an audit found fifteen parameters that the
parser, the linter and the docs all agreed on and that no SDK could emit --
``accessory`` and ``header`` among them, both Vee-native. Checking the three
SDKs separately rather than as a union also makes them agree with each other:
a parameter added to one SDK and forgotten in the other two fails here.

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

# Each SDK's emitted keys are scraped from its `push(...)` calls. Most keys are
# string literals; the few pushed through a variable are credited by matching
# the expression that emits them, so a dynamic key still has to be *provably*
# present rather than assumed.
#
# The scrape is bounded to the menu-line encoder in each SDK. It has to be:
# every SDK also builds the widget-card JSON payload with an identically named
# `push` helper, and those keys (`template`, `tint`, `items`, ...) are a
# different namespace that has nothing to do with menu-line parameters.
SDK_SOURCES = {
    "ts": (
        "plugins/typescript/vee.ts",
        [("function encode(options?: ItemOptions): string {", "\n}")],
        r'push\("([a-z0-9]+)"',
        [(r"push\(c\.kind,", {"pie", "donut", "stackedbar"}),
         (r"push\(`param\$\{i \+ 1\}`", {"paramN"})],
    ),
    "python": (
        "plugins/python/vee.py",
        # The two key tables live at module scope; the rest is inside _encode.
        [("_SCALAR_KEYS: list[tuple[str, str]] = [", "]"),
         ("_TRAILING_KEYS: list[tuple[str, str]] = [", "]"),
         ("def _encode(", "\n\nclass ")],
        r'push\("([a-z0-9]+)"|\(\s*"[a-zA-Z_]+",\s*"([a-z0-9]+)"\s*\)',
        [(r'push\(chart\["kind"\]', {"pie", "donut", "stackedbar"}),
         (r'push\(f"param\{i \+ 1\}"', {"paramN"})],
    ),
    "go": (
        "plugins/go/vee.go",
        [("func encode(o *Options) string {", "\n}")],
        r'push\("([a-z0-9]+)"|pushBool\("([a-z0-9]+)"',
        [(r"push\(o\.Chart\.Kind,", {"pie", "donut", "stackedbar"}),
         (r'push\(fmt\.Sprintf\("param%d"', {"paramN"})],
    ),
}

# Parameters deliberately absent from one surface. Every entry needs a reason:
# an intentional omission must be distinguishable from an oversight, and must
# be visible in review rather than buried in a diff.
EXCEPTIONS = {
    # key: (surfaces it may be missing from, why)
    "paramN": ({"parser", "keys"},
               "the positional param0..N family is open-ended, so it is matched by "
               "prefix in LineParser and LineParameterKeys.isRecognized rather than "
               "enumerated as cases or set members"),
    "bash": ({"ts", "python", "go"},
             "a compatibility alias for shell=; the SDKs expose the one spelling "
             "(shell) rather than both, so plugins written with an SDK are "
             "consistent"),
    "markdown": ({"ts", "python", "go"},
                 "a compatibility alias for md=; the SDKs expose the one spelling"),
    "trackcolor": ({"ts", "python", "go"},
                   "the pre-v2 spelling of progresstrackcolor=. Still parsed and "
                   "still linted so existing plugins keep working, but the SDKs "
                   "emit only the current name -- see the deprecation note in "
                   "plugin-authoring.md"),
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


def sdk_keys(name):
    """Keys the named SDK can emit, from its `push(...)` call sites."""
    rel, regions, literal, dynamic = SDK_SOURCES[name]
    whole = open(os.path.join(ROOT, rel)).read()
    chunks = []
    for start, end in regions:
        if start not in whole:
            raise SystemExit(
                "check_params: could not find %r in %s — the SDK was "
                "restructured and this script's scrape region needs updating"
                % (start, rel))
        after = whole[whole.index(start) + len(start):]
        chunks.append(after[:after.index(end)] if end in after else after)
    src = "\n".join(chunks)
    out = set()
    for match in re.findall(literal, src):
        if isinstance(match, tuple):
            out.update(g for g in match if g)
        elif match:
            out.add(match)
    for pattern, keys in dynamic:
        if re.search(pattern, src):
            out.update(keys)
    return out


def main():
    surfaces = {"parser": parser_keys(), "keys": public_keys(), "docs": doc_keys()}
    for name in SDK_SOURCES:
        surfaces[name] = sdk_keys(name)
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
        print("Menu-line parameters disagree across their six surfaces:\n")
        for p in problems:
            print("  " + p)
        print("\n  parser = LineParser.mapParams  |  keys = LineParameterKeys"
              "  |  docs = plugin-authoring.md")
        print("  ts/python/go = the SDKs under plugins/")
        print("\nAdd the parameter to whichever surface is missing it, or record a"
              "\ndeliberate omission in EXCEPTIONS in this script.")
        return 1

    print("ok: %d parameters agree across the parser, the linter keys, the docs, "
          "and all three SDKs" % len(every))
    return 0


if __name__ == "__main__":
    sys.exit(main())
