import { defineCollection } from "astro:content";
import { glob } from "astro/loaders";
import { docsSchema } from "@astrojs/starlight/schema";

// The prose stays in docs/_content, where it has always lived: every existing
// cross-reference, anchor, and docs/scripts/* path keeps working, and the
// Markdown remains readable on GitHub without a build step. Only top-level
// *.md are pages — _generated/ holds partials that pages include.
export const collections = {
  docs: defineCollection({
    // The `guide/` prefix keeps the published URL shape: /guide/<slug>/ where
    // the Python builder emitted /guide/<slug>.html. Only the extension
    // changes, which task 4's redirects cover.
    loader: glob({
      base: "../docs/_content",
      pattern: "*.md",
      generateId: ({ entry }) => `guide/${entry.replace(/\.md$/, "")}`,
    }),
    schema: docsSchema(),
  }),
};
