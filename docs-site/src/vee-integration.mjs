import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve("..");
const DOCS = path.join(ROOT, "docs");
const CONTENT = path.join(DOCS, "_content");
const SITE = "https://vee.navbytes.io";

// Hand-authored surfaces published from the same origin as the guide. The
// landing page is 40K of bespoke layout over its own stylesheet, and the
// comparison pages are marketing; Starlight owns /guide/ and nothing else, so
// these are copied through byte-for-byte rather than ported.
const PASSTHROUGH = [
  "assets", "compare", "schemas", "index.html",
  "robots.txt", "CNAME", ".nojekyll", "site.webmanifest",
];

// A paragraph that is only a link into _generated/ is an include directive.
// Written as a link rather than an HTML comment so the same file reads
// correctly on GitHub, where the directive stays a link to the generated table
// instead of rendering as nothing. See docs-site/src/remark-include.mjs.
const INCLUDE = /^\[[^\]]*\]\((_generated\/[^)\s]+)\)\s*$/;

/** Read a page's Markdown: frontmatter removed, `# Title` restored, includes expanded. */
function readContent(slug) {
  const lines = fs.readFileSync(path.join(CONTENT, `${slug}.md`), "utf8").split("\n");
  const meta = frontmatter(lines);
  const out = [];
  if (meta.title) out.push(`# ${meta.title}`, "");
  for (const line of meta.body) {
    const match = INCLUDE.exec(line);
    if (!match) { out.push(line); continue; }
    const target = path.join(CONTENT, match[1]);
    if (!fs.existsSync(target)) {
      throw new Error(
        `${slug}.md includes ${match[1]}, which does not exist — ` +
          `run: python3 docs/scripts/build_reference.py`
      );
    }
    out.push(...fs.readFileSync(target, "utf8").split("\n"));
  }
  return { meta, text: out.join("\n").replace(/\n+$/, "\n") };
}

/**
 * The frontmatter fields this site needs, parsed without a YAML dependency.
 *
 * Deliberately narrow: it reads the exact shape the pages carry (title,
 * description, sidebar.label, sidebar.order) and ignores everything else. A
 * general YAML parser would be a dependency to serve four scalar fields.
 */
function frontmatter(lines) {
  if (lines[0]?.trim() !== "---") return { body: lines };
  const end = lines.findIndex((l, i) => i > 0 && l.trim() === "---");
  const meta = { body: lines.slice(end + 1) };
  for (const line of lines.slice(1, end)) {
    const scalar = /^(title|description):\s*"(.*)"\s*$/.exec(line);
    if (scalar) meta[scalar[1]] = scalar[2].replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    const label = /^\s+label:\s*"(.*)"\s*$/.exec(line);
    if (label) meta.label = label[1];
    const order = /^\s+order:\s*(\d+)\s*$/.exec(line);
    if (order) meta.order = Number(order[1]);
  }
  while (meta.body.length && !meta.body[0].trim()) meta.body.shift();
  return meta;
}

/** Every page, in sidebar order — the running order llms.txt and the pager use. */
function pages() {
  return fs.readdirSync(CONTENT)
    .filter((name) => name.endsWith(".md"))
    .map((name) => {
      const slug = name.replace(/\.md$/, "");
      return { slug, ...readContent(slug) };
    })
    .sort((a, b) => (a.meta.order ?? 99) - (b.meta.order ?? 99));
}

function copy(from, to) {
  fs.cpSync(from, to, { recursive: true });
}

/**
 * The guide's running order, as Starlight sidebar entries.
 *
 * Starlight's `autogenerate` cannot see these pages: it infers structure from
 * a directory under `src/content`, and this collection is a glob loader
 * pointed at `docs/_content` so the prose can stay where it has always lived.
 * So the sidebar is built here instead — still derived, from each page's own
 * `sidebar.order` and `sidebar.label` frontmatter, never a hand-kept list.
 */
export function sidebarItems() {
  return pages().map((page) => ({
    label: page.meta.label ?? page.meta.title,
    link: `/guide/${page.slug}/`,
  }));
}

export function veeStaticAndMachineReadable() {
  return {
    name: "vee-static-and-machine-readable",
    hooks: {
      "astro:build:done": ({ dir, logger }) => {
        const out = dir.pathname;

        for (const name of PASSTHROUGH) {
          const from = path.join(DOCS, name);
          if (!fs.existsSync(from)) throw new Error(`missing passthrough: ${from}`);
          copy(from, path.join(out, name));
        }
        logger.info(`copied ${PASSTHROUGH.length} hand-authored surfaces`);

        const all = pages();

        // Markdown mirrors: /guide/<slug>.md beside /guide/<slug>/, so swapping
        // a page's URL for its source works. Published since #95 and required
        // by plugin-docs-integrity; Starlight provides nothing like it.
        for (const page of all) {
          fs.writeFileSync(path.join(out, "guide", `${page.slug}.md`), page.text);
        }

        // llms.txt — the llmstxt.org entry point.
        const index = [
          "# Vee", "",
          "> A native, leak-free macOS menu-bar script runner, compatible with the",
          "> xbar and SwiftBar plugin protocol. Plugins are ordinary executables that",
          "> print text (or JSON) to standard output; Vee runs them on a schedule and",
          "> renders the result as menu-bar titles, dropdown menus, and native widgets.",
          "",
          "The complete documentation is also available as a single document:",
          `[${SITE}/llms-full.txt](${SITE}/llms-full.txt).`, "",
          "## Documentation", "",
          ...all.map((p) => `- [${p.meta.label ?? p.meta.title}](${SITE}/guide/${p.slug}.md): ${p.meta.description}`),
          "", "## Machine-readable contracts", "",
          `- [Widget card schema](${SITE}/schemas/widget-card.schema.json): JSON Schema for the payload a plugin prints in widget mode, including the layout tree. Validated in CI against the SDKs' golden fixtures.`,
          `- [JSON output schema](${SITE}/schemas/json-output.schema.json): JSON Schema for the structured-JSON alternative to the text protocol.`,
          `- [Parameter reference](${SITE}/api/params.json): every menu-line parameter as data — type, accepted values, default, and the chart it belongs to. The published tables are generated from it, and CI holds it in agreement with the parser, the linter, and all three SDKs.`,
          "", "## Optional", "",
          `- [Plugin SDKs](https://github.com/navbytes/vee/tree/main/plugins): zero-dependency TypeScript, Python, and Go builders that emit byte-identical output.`,
          `- [Example plugins](https://github.com/navbytes/vee/tree/main/plugins/showcase): runnable, heavily commented showcase plugins.`,
          "",
        ].join("\n");
        fs.writeFileSync(path.join(out, "llms.txt"), index);

        // llms-full.txt — the whole format in one retrieval rather than 15 crawls.
        const full = [
          "# Vee — complete documentation", "",
          `Every page of the Vee plugin documentation, concatenated. Source: ${SITE}`,
          `Machine-readable payload schemas: ${SITE}/schemas/`,
          "", "---", "",
          ...all.flatMap((p) => [`<!-- ${SITE}/guide/${p.slug}/ -->`, "", p.text.trim(), "", "---", ""]),
        ].join("\n");
        fs.writeFileSync(path.join(out, "llms-full.txt"), full);

        // The parameter record, published so a client can read the surface as
        // data instead of parsing a rendered table.
        fs.mkdirSync(path.join(out, "api"), { recursive: true });
        copy(path.join(DOCS, "api", "params.json"), path.join(out, "api", "params.json"));

        // Redirect stubs. /guide/<slug>.html is published in llms.txt, in the
        // README, and in whatever has already crawled the site; GitHub Pages
        // serves static files and has no redirect rules, so each old path gets
        // a stub naming the new one as canonical.
        for (const page of all) {
          writeStub(path.join(out, "guide", `${page.slug}.html`),
                    `${SITE}/guide/${page.slug}/`, page.meta.title);
        }

        // /guide/ was a hand-written overview whose card grid restated the 15
        // sidebar entries beside it — 171 lines, renumbered by hand whenever a
        // page was inserted. Starlight's sidebar is that index, so the URL
        // redirects to the first guide rather than duplicating it.
        writeStub(path.join(out, "guide", "index.html"),
                  `${SITE}/guide/${all[0].slug}/`, "Documentation");

        // /sitemap.xml is the URL robots.txt names and search engines already
        // hold; @astrojs/sitemap emits /sitemap-index.xml. Publish both rather
        // than rewrite robots.txt and wait for a recrawl.
        const generated = path.join(out, "sitemap-index.xml");
        if (fs.existsSync(generated)) copy(generated, path.join(out, "sitemap.xml"));

        logger.info(`wrote ${all.length} Markdown mirrors, ${all.length + 1} redirect stubs, llms.txt, llms-full.txt`);
      },
    },
  };
}

/**
 * A page that moved: canonical at the new location, and a refresh to follow it.
 *
 * data-pagefind-ignore keeps stubs out of the search index — without it every
 * page has a second result reading "moved".
 */
function writeStub(file, to, title) {
  fs.writeFileSync(file, [
    "<!doctype html>",
    '<html lang="en">',
    "<head>",
    '<meta charset="utf-8">',
    `<link rel="canonical" href="${to}">`,
    `<meta http-equiv="refresh" content="0; url=${to}">`,
    '<meta name="robots" content="noindex">',
    `<title>${title} — moved</title>`,
    "</head>",
    `<body data-pagefind-ignore><p>This page moved to <a href="${to}">${to}</a>.</p></body>`,
    "</html>", "",
  ].join("\n"));
}
