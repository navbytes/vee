#!/usr/bin/env python3
"""Fail when the menu-line parameter list disagrees across its six surfaces.

The same list of parameter keys is written down six times:

  1. ``LineParser.mapParams``      — the switch that actually parses them
  2. ``LineParameterKeys``         — the public set the CLI linter uses
  3. ``docs/api/params.json``      — the record the published tables are built from
  4. ``plugins/typescript/vee.ts`` — what the TypeScript SDK can emit
  5. ``plugins/python/vee.py``     — what the Python SDK can emit
  6. ``plugins/go/vee.go``         — what the Go SDK can emit

Swift cannot enumerate a switch's cases, so (2) is a hand-written mirror of (1),
and (3) is authored by hand because a type, a default, and a sentence are things
only a person can write. This script is what keeps all six honest: it scrapes
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

Surfaces (4)-(6) were added after an audit found fifteen parameters that the
parser, the linter and the docs all agreed on and that no SDK could emit --
``accessory`` and ``header`` among them, both Vee-native. Checking the three
SDKs separately rather than as a union also makes them agree with each other:
a parameter added to one SDK and forgotten in the other two fails here.

    python3 docs/scripts/check_params.py

Pure standard library, matching the project policy and docs/scripts/build_guide.py.
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
    data = spec()
    surfaces = {"parser": parser_keys(), "keys": public_keys(), "docs": doc_keys(data)}
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

    numbers = constant_problems(data)

    if problems:
        print("Menu-line parameters disagree across their six surfaces:\n")
        for p in problems:
            print("  " + p)
        print("\n  parser = LineParser.mapParams  |  keys = LineParameterKeys"
              "  |  docs = plugin-authoring.md")
        print("  ts/python/go = the SDKs under plugins/")
        print("\nAdd the parameter to whichever surface is missing it, or record a"
              "\ndeliberate omission in EXCEPTIONS in this script.")
        if numbers:
            print()
            report_numbers(numbers)
        return 1

    if numbers:
        report_numbers(numbers)
        return 1

    print("ok: %d parameters agree across the parser, the linter keys, the docs, "
          "and all three SDKs" % len(every))
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
