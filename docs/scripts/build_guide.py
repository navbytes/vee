#!/usr/bin/env python3
"""Render the Markdown in docs/_content into the docs/guide GitHub Pages site.

The guide pages under docs/guide are *generated output* committed to the repo:
GitHub Pages serves docs/ straight from the default branch (there is a
.nojekyll marker and no Pages workflow), so whatever is committed here is what
ships. Before this script existed the HTML was produced out-of-band and drifted
roughly two releases behind docs/_content; run this after editing any page so
the site and the Markdown can't disagree again.

    python3 docs/scripts/build_guide.py            # write docs/guide/*.html
    python3 docs/scripts/build_guide.py --check    # exit 1 if any page is stale

Pure standard library (no third-party deps, matching the project policy).

Only the Markdown subset the guides actually use is supported — headings,
paragraphs, lists (with nested content), fenced code, tables, blockquotes, and
inline emphasis/code/links. Anything else should be added here deliberately
rather than smuggled into a page as raw HTML.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
CONTENT = os.path.join(DOCS, "_content")
GUIDE = os.path.join(DOCS, "guide")

# The canonical origin. Changing this rewrites every page's canonical and
# og:url, so it must land together with docs/CNAME and the DNS record.
SITE = "https://vee.navbytes.io"

# The guide's running order: sidebar order, and the prev/next pager. `index` is
# hand-written (it has no Markdown source) and is only listed so it can appear
# in the sidebar. Titles/descriptions are the page's SEO metadata.
PAGES = [
    dict(slug="index", nav="Overview", source=None),
    dict(
        slug="getting-started", nav="Getting started",
        title="Getting started with Vee — Vee docs",
        desc="Install Vee, write your first plugin, and learn where plugins live. A native macOS menu-bar script runner, xbar and SwiftBar compatible.",
    ),
    dict(
        slug="migrating-from-swiftbar", nav="Migrating from SwiftBar / xbar",
        title="Migrating from SwiftBar / xbar — Vee docs",
        desc="Move to Vee from SwiftBar or xbar in one step: point it at your existing plugins folder. Full protocol compatibility, plus a trust layer and typed SDK.",
    ),
    dict(
        slug="plugin-authoring", nav="Plugin authoring",
        title="Plugin authoring reference — Vee docs",
        desc="The full Vee plugin reference: filenames and intervals, menu structure, line parameters, metadata headers, SF Symbols, ANSI, Markdown, streaming, and cron.",
    ),
    dict(
        slug="widgets", nav="Widgets",
        title="Widgets — Vee docs",
        desc="Render Vee plugins as native desktop and Notification Center widgets: the surface contract, the widget card schema, the five templates, and the composable layout tree.",
    ),
    dict(
        slug="trust-model", nav="Trust model",
        title="Trust model — Vee docs",
        desc="How Vee makes plugins transparent: authors declare what they touch with <vee.*> tags, and Vee shows a plain-language trust summary before install. Advisory, not a sandbox.",
    ),
    dict(
        slug="preferences", nav="Preferences",
        title="Preferences — Vee docs",
        desc="Plugins declare typed settings with <xbar.var>; Vee auto-generates a form and stores secrets in the macOS Keychain. Configuration belongs to the plugin.",
    ),
    dict(
        slug="sdk", nav="Plugin SDKs",
        title="Plugin SDKs — Vee docs",
        desc="Zero-dependency Vee plugin SDKs for TypeScript, Python, and Go — the same typed Menu/Section builders in every language, producing byte-identical output.",
    ),
    dict(
        slug="json-output", nav="JSON output",
        title="JSON output format — Vee docs",
        desc="Vee's optional structured-JSON output format: opt in with a top-level {\"vee\":1} object, skip the text protocol's quoting and escaping, and get typed items and clean nesting.",
    ),
    dict(
        slug="cli-and-urls", nav="CLI &amp; URL actions",
        title="CLI and URL actions — Vee docs",
        desc="Run Vee from source with swift run vee, and drive it at runtime with vee:// and swiftbar:// URL actions — refresh, enable/disable, toggle, and notify.",
    ),
    dict(
        slug="debugging", nav="Debugging &amp; testing",
        title="Debugging and testing plugins — Vee docs",
        desc="Preview, watch, and lint a Vee plugin without installing it: vee render, vee show, vee dev, and vee lint, plus execution timeouts, exit codes, and the Debug console.",
    ),
    dict(
        slug="writing-plugins-with-an-llm", nav="Writing plugins with an LLM",
        title="Writing Vee plugins with an LLM — Vee docs",
        desc="Hand a model the whole plugin format in one file, give it the JSON Schemas instead of prose, and close the loop with vee lint — plus the mistakes to watch for.",
    ),
    dict(
        slug="enterprise-store", nav="Custom plugin stores",
        title="Custom plugin stores (enterprise) — Vee docs",
        desc="Point Vee at your own curated plugin catalog: a GitHub repo, a static HTTP host, or an air-gapped file mirror, with integrity checks and MDM-managed configuration.",
    ),
    dict(
        slug="faq", nav="FAQ",
        title="FAQ — Vee docs",
        desc="Answers about Vee: is it safe un-sandboxed, will my SwiftBar/xbar plugins work, macOS 26 and Apple Silicon requirements, where secrets are stored, and more.",
    ),
    dict(
        slug="troubleshooting", nav="Troubleshooting",
        title="Troubleshooting — Vee docs",
        desc="Fix common Vee issues: a plugin not appearing, Gatekeeper blocks, timeouts, missing interpreters and PATH differences, and refreshes not happening.",
    ),
]


# ── Inline ───────────────────────────────────────────────────────────────────

def escape(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def slugify(text):
    """Heading id, matching the anchors the Markdown itself links to.

    Punctuation is dropped rather than hyphenated (so ``Global hotkey
    (`<vee.shortcut>`)`` is ``global-hotkey-veeshortcut``) and each remaining
    whitespace character becomes its own hyphen — which is why removing a
    ``/`` between two words leaves a double hyphen. Both quirks are
    load-bearing: they match GitHub's own slugger, so an in-page link resolves
    whether the file is read on GitHub or on the rendered site.

    This differs from the anchors the old out-of-band tool produced for
    headings containing an apostrophe or an em dash (``what-s-compatible``,
    not ``whats-compatible``). Nothing in the repo links to those, and one rule
    that agrees with GitHub beats two that agree with neither.
    """
    text = re.sub(r"[^\w\s-]", "", text.lower(), flags=re.UNICODE)
    return "".join("-" if c.isspace() else c for c in text)


def link_href(url):
    """Rewrite a Markdown cross-reference into a site URL."""
    if url.startswith(("http://", "https://", "#", "mailto:")):
        return url
    # ../_content/foo.md#bar and foo.md#bar both point at the sibling page.
    return re.sub(r"^(?:\.\./)*(?:_content/)?([\w-]+)\.md", r"\1.html", url)


def inline(text):
    """Render inline Markdown. Code spans are lifted out first so their
    contents are escaped but never treated as emphasis or a link."""
    spans = []

    def stash(match):
        spans.append(escape(match.group(1)))
        return "\x00%d\x00" % (len(spans) - 1)

    text = re.sub(r"`([^`]+)`", stash, text)
    text = escape(text)

    def link(match):
        label, url = match.group(1), match.group(2)
        href = link_href(url)
        rel = ' rel="noopener"' if href.startswith(("http://", "https://")) else ""
        return '<a href="%s"%s>%s</a>' % (escape(href), rel, label)

    text = re.sub(r"\[([^\]]*)\]\(([^)\s]+)\)", link, text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    # Emphasis may wrap across source lines (paragraphs are already split, so
    # this can never run past a blank line).
    text = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", text)
    text = re.sub(r"(?<![\w_])_([^_]+)_(?![\w_])", r"<em>\1</em>", text)

    return re.sub(r"\x00(\d+)\x00", lambda m: "<code>%s</code>" % spans[int(m.group(1))], text)


# ── Blocks ───────────────────────────────────────────────────────────────────

def dedent(lines, width):
    return [line[width:] if len(line) >= width and line[:width].isspace() else line.lstrip()
            for line in lines]


def code_window(lang, body):
    """A fenced code block, in the site's window chrome. An unlabelled fence is
    shown as `text`, matching the existing pages."""
    return ('<div class="code-window"><div class="code-window__bar">'
            '<span class="traffic"><i></i><i></i><i></i></span>'
            '<span class="fname">%s</span></div><pre><code>%s</code></pre></div>'
            % (escape(lang or "text"), escape("\n".join(body))))


def table(rows):
    head, body = rows[0], rows[2:]

    def cells(row, tag):
        # Split on unescaped pipes only: a table cell may contain a literal `|`
        # written as `\|` (this project documents a pipe-delimited format, so
        # that is common), and splitting on it would shatter the row into extra
        # columns. Unescape after splitting, before inline rendering.
        parts = [c.strip().replace("\\|", "|")
                 for c in re.split(r"(?<!\\)\|", row.strip().strip("|"))]
        return "".join("<%s>%s</%s>" % (tag, inline(c), tag) for c in parts)

    out = '<div class="table-scroll"><table><thead><tr>%s</tr></thead><tbody>' % cells(head, "th")
    out += "".join("<tr>%s</tr>" % cells(r, "td") for r in body)
    return out + "</tbody></table></div>"


LIST_ITEM = re.compile(r"^(\s*)(?:([-*])|(\d+)\.)\s+(.*)$")


def render(lines):
    """Render a list of Markdown lines into HTML blocks."""
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]

        if not line.strip():
            i += 1
            continue

        # Fenced code.
        fence = re.match(r"^```(\w*)\s*$", line.strip())
        if fence and line.lstrip() == line:
            body, i = [], i + 1
            while i < len(lines) and lines[i].strip() != "```":
                body.append(lines[i])
                i += 1
            out.append(code_window(fence.group(1), body))
            i += 1
            continue

        # Heading. h1 carries no id — it is the page title, never linked to.
        heading = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
        if heading:
            level, text = len(heading.group(1)), heading.group(2)
            if level == 1:
                out.append("<h1>%s</h1>" % inline(text))
            else:
                out.append('<h%d id="%s">%s</h%d>' % (level, slugify(text), inline(text), level))
            i += 1
            continue

        # Table.
        if line.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:|-]+\|?\s*$", lines[i + 1]):
            rows, i = [], i
            while i < len(lines) and lines[i].startswith("|"):
                rows.append(lines[i])
                i += 1
            out.append(table(rows))
            continue

        # Blockquote.
        if line.startswith(">"):
            body, i = [], i
            while i < len(lines) and lines[i].startswith(">"):
                body.append(re.sub(r"^>\s?", "", lines[i]))
                i += 1
            out.append("<blockquote>\n%s\n</blockquote>" % "\n".join(render(body)))
            continue

        # Raw HTML (an explicit anchor, say) passes through untouched.
        if line.startswith("<"):
            out.append(line)
            i += 1
            continue

        # List. An item owns every following line indented past its marker, so
        # a nested paragraph or code block renders *inside* the <li>.
        item = LIST_ITEM.match(line)
        if item and not item.group(1):
            ordered = item.group(3) is not None
            items, i = [], i
            while i < len(lines):
                head = LIST_ITEM.match(lines[i])
                if not (head and not head.group(1)):
                    break
                body, i = [head.group(4)], i + 1
                while i < len(lines) and (not lines[i].strip() or lines[i][:1].isspace()):
                    body.append(lines[i])
                    i += 1
                while body and not body[-1].strip():
                    body.pop()
                    i -= 1
                items.append(body)
            tag = "ol" if ordered else "ul"
            out.append("<%s>" % tag)
            for body in items:
                # Continuations are indented to the item's text column, which
                # differs between "- " (2) and "1. " (3) — and a fence only
                # reads as a fence once it is back at column 0.
                rest = [line for line in body[1:] if line.strip()]
                width = min((len(l) - len(l.lstrip()) for l in rest), default=0)
                inner = render([body[0]] + dedent(body[1:], width))
                # A one-paragraph item stays inline, the way the pages read today.
                if len(inner) == 1 and inner[0].startswith("<p>"):
                    out.append("<li>%s</li>" % inner[0][3:-4])
                else:
                    if inner and inner[0].startswith("<p>"):
                        inner[0] = inner[0][3:-4]
                    out.append("<li>%s</li>" % "\n".join(inner))
            out.append("</%s>" % tag)
            continue

        # Paragraph: everything up to a blank line or the start of another block.
        body, i = [], i
        while i < len(lines) and lines[i].strip():
            nxt = lines[i]
            if body and (nxt.startswith(("#", "|", ">", "```")) or LIST_ITEM.match(nxt)):
                break
            body.append(nxt.strip())
            i += 1
        out.append("<p>%s</p>" % inline("\n".join(body)))

    return out


# ── Page ─────────────────────────────────────────────────────────────────────

def sidebar(current):
    rows = []
    for page in PAGES:
        active = ' aria-current="page"' if page["slug"] == current else ""
        rows.append('<li><a href="./%s.html"%s>%s</a></li>' % (page["slug"], active, page["nav"]))
    return '<ul class="docs-nav">\n%s\n</ul>' % "\n".join(rows)


def pager(index):
    parts = []
    if index > 1:
        prev = PAGES[index - 1]
        parts.append('<a class="prev" href="./%s.html"><span class="dir">&larr; Previous</span>'
                     '<span class="lbl">%s</span></a>' % (prev["slug"], prev["nav"]))
    if index + 1 < len(PAGES):
        nxt = PAGES[index + 1]
        parts.append('<a class="next" href="./%s.html"><span class="dir">Next &rarr;</span>'
                     '<span class="lbl">%s</span></a>' % (nxt["slug"], nxt["nav"]))
    if not parts:
        return ""
    return '<nav class="doc-nextprev" aria-label="Guide pagination">%s</nav>' % "".join(parts)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <meta name="description" content="{desc}">
  <link rel="canonical" href="{site}/guide/{slug}.html">
  <link rel="icon" type="image/svg+xml" href="../assets/favicon.svg">
  <link rel="stylesheet" href="../assets/style.css">
  <link rel="alternate" type="text/markdown" href="./{slug}.md" title="Markdown source">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="Vee">
  <meta property="og:title" content="{title}">
  <meta property="og:description" content="{desc}">
  <meta property="og:url" content="{site}/guide/{slug}.html">
  <meta property="og:image" content="{site}/assets/og-image.png">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{title}">
  <meta name="twitter:description" content="{desc}">
  <meta name="twitter:image" content="{site}/assets/og-image.png">
</head>
<body>
<a class="skip-link" href="#main">Skip to content</a>
<header class="topbar">
  <div class="topbar-inner">
    <a class="brand" href="../index.html" aria-label="Vee home">
      <img class="mark" src="../assets/favicon.svg" alt="" width="28" height="28">
      <span><b>Vee</b></span>
    </a>
    <button class="nav-toggle" aria-label="Toggle navigation" aria-expanded="false" aria-controls="nav-links">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16"/></svg>
    </button>
    <ul class="nav-links" id="nav-links">
      <li><a href="../index.html#features">Features</a></li>
      <li><a href="../index.html#trust">Trust</a></li>
      <li><a href="../compare/index.html">Compare</a></li>
      <li><a href="./index.html" aria-current="page">Docs</a></li>
      <li><a class="nav-cta" href="https://github.com/navbytes/vee" rel="noopener">GitHub</a></li>
    </ul>
  </div>
</header>
<div class="docs-layout">
  <aside class="docs-side" aria-label="Documentation navigation">
    <div id="docs-search" class="docs-search" data-pagefind-ignore></div>
    <p class="docs-nav-title">Documentation</p>
{sidebar}
{toc}
  </aside>
  <main class="docs-main" id="main">
    <article class="docs-content" data-pagefind-body>
      <p class="doc-hero-note">Vee documentation</p>
{body}
    </article>
    {pager}
  </main>
</div>
<link rel="stylesheet" href="../pagefind/pagefind-ui.css">\n<script src="../pagefind/pagefind-ui.js"></script>\n<script src="../assets/app.js" defer></script>
</body>
</html>
"""


def toc(body_html):
    """An "On this page" list from the h2s `render` just emitted.

    Reuses the ids `slugify` already produced, so the TOC cannot disagree with
    the anchors on the page.
    """
    heads = re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', body_html, flags=re.S)
    if len(heads) < 3:
        return ""  # too few sections for a contents list to earn its space
    rows = "".join('<li><a href="#%s">%s</a></li>' % (hid, text) for hid, text in heads)
    return ('<nav class="docs-toc" aria-labelledby="toc-title">'
            '<p class="docs-nav-title" id="toc-title">On this page</p>'
            '<ul>%s</ul></nav>' % rows)


def build(page, index):
    source = os.path.join(CONTENT, "%s.md" % page["slug"])
    with open(source, encoding="utf-8") as handle:
        body = render(handle.read().splitlines())
    body_html = "\n".join(body)
    return TEMPLATE.format(
        title=escape(page["title"]), desc=escape(page["desc"]), site=SITE,
        slug=page["slug"], sidebar=sidebar(page["slug"]),
        body=body_html, pager=pager(index), toc=toc(body_html),
    )


def plain(nav):
    """A PAGES nav label as plain text.

    `nav` is inserted raw into HTML, so it carries entities (`CLI &amp; URL
    actions`). Text outputs need the character back.
    """
    return nav.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")


def sourced_pages():
    """PAGES entries that have a Markdown source (everything but the index)."""
    return [p for p in PAGES if p.get("source", True) is not None]


def llms_txt():
    """The llmstxt.org entry point: what Vee is, then every page as a link.

    Links point at the Markdown mirrors, not the HTML: a client reaching for
    this file wants source, not a rendered page. Descriptions are the ones
    PAGES already carries, so this cannot claim something the pages do not.
    """
    out = ["# Vee", "",
           "> A native, leak-free macOS menu-bar script runner, compatible with the",
           "> xbar and SwiftBar plugin protocol. Plugins are ordinary executables that",
           "> print text (or JSON) to standard output; Vee runs them on a schedule and",
           "> renders the result as menu-bar titles, dropdown menus, and native widgets.",
           "",
           "The complete documentation is also available as a single document:",
           "[%s/llms-full.txt](%s/llms-full.txt)." % (SITE, SITE),
           "", "## Documentation", ""]
    for page in sourced_pages():
        out.append("- [%s](%s/guide/%s.md): %s" % (plain(page["nav"]), SITE, page["slug"], page["desc"]))
    out += ["", "## Machine-readable contracts", "",
            "- [Widget card schema](%s/schemas/widget-card.schema.json): JSON Schema for the "
            "payload a plugin prints in widget mode, including the layout tree. Validated in "
            "CI against the SDKs' golden fixtures." % SITE,
            "- [JSON output schema](%s/schemas/json-output.schema.json): JSON Schema for the "
            "structured-JSON alternative to the text protocol." % SITE,
            "", "## Optional", "",
            "- [Plugin SDKs](https://github.com/navbytes/vee/tree/main/plugins): zero-dependency "
            "TypeScript, Python, and Go builders that emit byte-identical output.",
            "- [Example plugins](https://github.com/navbytes/vee/tree/main/examples): runnable, "
            "heavily commented showcase plugins.",
            ""]
    return "\n".join(out)


def llms_full_txt():
    """Every guide concatenated, so the whole format is one retrieval."""
    out = ["# Vee — complete documentation", "",
           "Every page of the Vee plugin documentation, concatenated. Source: %s" % SITE,
           "Machine-readable payload schemas: %s/schemas/" % SITE,
           "", "---", ""]
    for page in sourced_pages():
        with open(os.path.join(CONTENT, "%s.md" % page["slug"]), encoding="utf-8") as handle:
            body = handle.read().strip()
        out += ["<!-- %s/guide/%s.html -->" % (SITE, page["slug"]), "", body, "", "---", ""]
    return "\n".join(out)


# Static pages outside PAGES that still belong in the sitemap.
EXTRA_URLS = ["/", "/compare/", "/compare/vee-vs-swiftbar.html", "/compare/vee-vs-xbar.html"]


def sitemap():
    urls = list(EXTRA_URLS) + ["/guide/%s.html" % p["slug"] for p in PAGES]
    body = "".join("  <url><loc>%s%s</loc></url>\n" % (SITE, u) for u in urls)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
            '%s</urlset>\n' % body)


def robots():
    return "User-agent: *\nAllow: /\n\nSitemap: %s/sitemap.xml\n" % SITE


def main(argv):
    check = "--check" in argv
    stale = []
    for index, page in enumerate(PAGES):
        if page.get("source", True) is None:
            continue  # hand-written, no Markdown source
        target = os.path.join(GUIDE, "%s.html" % page["slug"])
        rendered = build(page, index)
        current = open(target, encoding="utf-8").read() if os.path.exists(target) else None
        if current == rendered:
            continue
        if check:
            stale.append(page["slug"])
            continue
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(rendered)
        print("wrote guide/%s.html" % page["slug"])
    # Markdown mirrors: the same source the HTML was rendered from, published
    # beside it so /guide/x.md is derivable from /guide/x.html. Cross-links keep
    # their .md form here — correct for a Markdown reader, unlike the HTML.
    for page in sourced_pages():
        with open(os.path.join(CONTENT, "%s.md" % page["slug"]), encoding="utf-8") as handle:
            rendered = handle.read()
        target = os.path.join(GUIDE, "%s.md" % page["slug"])
        current = open(target, encoding="utf-8").read() if os.path.exists(target) else None
        if current == rendered:
            continue
        if check:
            stale.append("guide/%s.md" % page["slug"])
            continue
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(rendered)
        print("wrote guide/%s.md" % page["slug"])

    for name, rendered in (("sitemap.xml", sitemap()), ("robots.txt", robots()),
                           ("llms.txt", llms_txt()), ("llms-full.txt", llms_full_txt())):
        target = os.path.join(DOCS, name)
        current = open(target, encoding="utf-8").read() if os.path.exists(target) else None
        if current == rendered:
            continue
        if check:
            stale.append(name)
            continue
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(rendered)
        size = " (%d KB)" % (len(rendered.encode("utf-8")) // 1024) if name == "llms-full.txt" else ""
        print("wrote %s%s" % (name, size))

    if stale:
        print("stale (run docs/scripts/build_guide.py): %s" % ", ".join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
