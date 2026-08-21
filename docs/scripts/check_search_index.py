#!/usr/bin/env python3
"""Fail when the committed search index is older than the pages it indexes.

Search is a static Pagefind index built from docs/guide/*.html and committed
alongside them. Nothing about that is self-correcting: edit a guide, regenerate
the HTML, forget the index, and every page is correct while search quietly
returns the previous release's text. There is no error, no empty result, no
signal at all — the worst shape a docs bug can take.

`build_guide.py --check` already stops the HTML falling behind the Markdown.
This is the same guard one step further down the chain.

    python3 docs/scripts/check_search_index.py           # verify (what CI runs)
    python3 docs/scripts/check_search_index.py --update  # rebuild, then record

The fingerprint is a hash of the exact files Pagefind reads, stored next to the
index. Verifying it needs no network and no Pagefind binary, so CI stays pure
standard library; only --update shells out to Pagefind.

A change to a page's chrome (adding a guide changes every sidebar) re-flags the
index even though the indexed prose did not move. That is deliberate: a spurious
regeneration costs seconds, and a missed one ships stale search.
"""
import glob
import hashlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
GUIDE = os.path.join(DOCS, "guide")
INDEX = os.path.join(DOCS, "pagefind")
STAMP = os.path.join(INDEX, "source-fingerprint.txt")

# Pinned so the committed index cannot change shape under us on a whim.
PAGEFIND = "pagefind@1.5.2"
BUILD_CMD = ["npx", "-y", PAGEFIND, "--site", "docs/guide", "--output-subdir", "../pagefind"]


def fingerprint():
    """A hash over every file Pagefind indexes, name and content."""
    digest = hashlib.sha256()
    for path in sorted(glob.glob(os.path.join(GUIDE, "*.html"))):
        digest.update(os.path.basename(path).encode())
        with open(path, "rb") as handle:
            digest.update(handle.read())
    return digest.hexdigest()


def update():
    print("$ " + " ".join(BUILD_CMD))
    result = subprocess.run(BUILD_CMD, cwd=os.path.dirname(DOCS))
    if result.returncode != 0:
        print("\nPagefind failed; the fingerprint was not written.", file=sys.stderr)
        return result.returncode
    # Written only after a successful build, so the stamp can never claim an
    # index that was not produced.
    with open(STAMP, "w") as handle:
        handle.write(fingerprint() + "\n")
    print("\nwrote %s" % os.path.relpath(STAMP, os.path.dirname(DOCS)))
    return 0


def check():
    if not os.path.isdir(INDEX):
        print("No search index at docs/pagefind.", file=sys.stderr)
        print("Build it: python3 docs/scripts/check_search_index.py --update", file=sys.stderr)
        return 1
    if not os.path.exists(STAMP):
        print("The search index has no fingerprint, so it cannot be shown to be current.",
              file=sys.stderr)
        print("Rebuild it: python3 docs/scripts/check_search_index.py --update", file=sys.stderr)
        return 1

    recorded = open(STAMP).read().strip()
    current = fingerprint()
    if recorded != current:
        print("The search index is stale: docs/guide has changed since it was built.",
              file=sys.stderr)
        print("Every page will render correctly, but search will return the previous text.",
              file=sys.stderr)
        print("\nRebuild it: python3 docs/scripts/check_search_index.py --update", file=sys.stderr)
        return 1

    print("ok: search index is current with docs/guide (%s)" % current[:12])
    return 0


if __name__ == "__main__":
    sys.exit(update() if "--update" in sys.argv[1:] else check())
