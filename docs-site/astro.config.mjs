// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import { remarkInclude } from "./src/remark-include.mjs";
import { veeStaticAndMachineReadable, sidebarItems } from "./src/vee-integration.mjs";

const SITE = "https://vee.navbytes.io";

export default defineConfig({
  site: SITE,
  // docs/ is the Pages root and the guide lives under /guide/, which is the
  // URL shape already published in llms.txt and crawled.
  outDir: "./dist",
  markdown: { remarkPlugins: [remarkInclude] },
  integrations: [
    starlight({
      title: "Vee",
      description:
        "A native, leak-free macOS menu-bar script runner, compatible with the xbar and SwiftBar plugin protocol.",
      favicon: "/assets/favicon.svg",
      logo: { src: "../docs/assets/favicon.svg", alt: "Vee" },
      social: [
        { icon: "github", label: "GitHub", href: "https://github.com/navbytes/vee" },
      ],
      customCss: ["./src/theme.css"],
      // Starlight emits og:title/description and twitter:card, but no image —
      // which silently downgrades every shared link from a large card to a
      // bare text preview. The Python builder emitted all four; these restore
      // the two that do not fall back. Twitter reads og:title and
      // og:description when the twitter: equivalents are absent, so those two
      // are deliberately not duplicated.
      head: [
        { tag: "meta", attrs: { property: "og:image", content: `${SITE}/assets/og-image.png` } },
        { tag: "meta", attrs: { name: "twitter:image", content: `${SITE}/assets/og-image.png` } },
      ],
      // Order comes from each page's frontmatter, which is where PAGES[]
      // moved to — one place per page rather than a table listing them all.
      // The pages are under guide/ (see generateId in content.config.ts), so
      // that is the directory to autogenerate from. Ordering comes from each
      // page's frontmatter `sidebar.order`, which is where the Python
      // builder's PAGES[] table moved to.
      sidebar: [{ label: "Documentation", items: sidebarItems() }],
    }),
    // After starlight: its sitemap and Pagefind hooks run at astro:build:done
    // too, and this one aliases the sitemap they emit. Running last also keeps
    // the hand-authored pages and redirect stubs out of the search index,
    // since they are copied in after Pagefind has read the directory.
    veeStaticAndMachineReadable(),
  ],
});
