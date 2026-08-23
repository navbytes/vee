#!/usr/bin/env python3
"""Fail when a documented link points at something that does not exist.

Scope is what this repository can break: links between guide pages, links into
the repository's own files, and anchors within a page. Links to other people's
hosts are not checked — that is link rot, which is a different problem on a
different clock, and a network call in CI besides.

    python3 docs/scripts/check_links.py

It exists because the `plugins/` reorganisation moved `examples/` to
`plugins/showcase/` and `plugins/src/vee.ts` to `plugins/typescript/vee.ts`, and
broke four documented links without anything noticing. Three of them were still
broken two pull requests later, one of which had rewritten the very paragraph
around it.

The GitHub links are the reason this is not just a file-exists check: a link to
``https://github.com/navbytes/vee/tree/main/examples`` reads as an external URL
and is really a path in this repository, so it is resolved locally. That is the
exact shape of every link the reorganisation broke.

Pure standard library, matching docs/scripts/build_guide.py.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
ROOT = os.path.dirname(DOCS)
CONTENT = os.path.join(DOCS, "_content")

SITE = "https://vee.navbytes.io"
REPO = re.compile(r"^https://github\.com/navbytes/vee/(?:tree|blob)/[^/]+/(.*)$")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HEADING = re.compile(r"^#+\s+(.*)$")
FENCE = re.compile(r"^\s*```")

# Files whose links are checked: the guide sources, and the Markdown a
# contributor reads at the top of the repository.
def sources():
    for name in sorted(os.listdir(CONTENT)):
        if name.endswith(".md"):
            yield os.path.join(CONTENT, name)
    for name in ("README.md", "CONTRIBUTING.md", "CHANGELOG.md", "SECURITY.md"):
        path = os.path.join(ROOT, name)
        if os.path.exists(path):
            yield path
    for root, dirs, files in os.walk(os.path.join(ROOT, "plugins")):
        dirs[:] = [d for d in dirs if d not in ("node_modules", "__pycache__")]
        for name in files:
            if name.endswith(".md"):
                yield os.path.join(root, name)


# The anchor rule is build_guide's, imported rather than reimplemented: an
# anchor this script accepts and the site does not generate is a link that
# silently lands at the top of the page, which is worse than a 404 because
# nothing looks wrong. A second copy of that rule would eventually be a
# different rule.
sys.path.insert(0, HERE)
from build_guide import slugify  # noqa: E402


def anchors(path):
    out = set()
    fenced = False
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if FENCE.match(line):
                fenced = not fenced
                continue
            if fenced:
                continue
            match = HEADING.match(line)
            if match:
                out.add(slugify(match.group(1)))
    return out


def links(path):
    """Every Markdown link in a file, skipping fenced code."""
    out = []
    fenced = False
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if FENCE.match(line):
                fenced = not fenced
                continue
            if fenced:
                continue
            for target in LINK.findall(line):
                out.append((number, target))
    return out


def resolve(source, target):
    """Where a link points on disk, or None when it is out of scope.

    Returns (path, anchor). `path` is None for a bare `#anchor`, which is
    checked against the source file itself.
    """
    if target.startswith("#"):
        return source, target[1:]

    repo = REPO.match(target)
    if repo:
        path = repo.group(1)
        return (os.path.join(ROOT, path) if path else ROOT), None

    if target.startswith(SITE):
        rest = target[len(SITE):].lstrip("/")
        return os.path.join(DOCS, rest) if rest else DOCS, None

    if "://" in target or target.startswith("mailto:"):
        return None, None

    path, _, anchor = target.partition("#")
    if not path:
        return source, anchor
    return os.path.normpath(os.path.join(os.path.dirname(source), path)), anchor


def main():
    problems = []
    checked = 0
    for source in sources():
        page_anchors = None
        for number, target in links(source):
            path, anchor = resolve(source, target)
            if path is None:
                continue
            checked += 1
            where = "%s:%d" % (os.path.relpath(source, ROOT), number)
            if not os.path.exists(path):
                problems.append("%s  %s\n      -> %s does not exist"
                                % (where, target, os.path.relpath(path, ROOT)))
                continue
            if anchor and path.endswith(".md"):
                if path == source:
                    if page_anchors is None:
                        page_anchors = anchors(source)
                    found = page_anchors
                else:
                    found = anchors(path)
                if anchor not in found:
                    problems.append(
                        "%s  %s\n      -> %s has no heading with anchor #%s"
                        % (where, target, os.path.relpath(path, ROOT), anchor))

    if problems:
        print("Documented links that do not resolve:\n")
        for problem in problems:
            print("  " + problem)
        print("\n%d broken of %d checked. External hosts are not checked."
              % (len(problems), checked))
        return 1

    print("ok: %d repository and same-site links resolve" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
