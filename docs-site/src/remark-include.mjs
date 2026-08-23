import fs from "node:fs";
import path from "node:path";
import { visit } from "unist-util-visit";

const CONTENT = path.resolve("../docs/_content");
const PREFIX = "_generated/";

/**
 * Expand a link into `_generated/` inline, replacing it with the file's content.
 *
 * A page writes the directive as an ordinary Markdown link:
 *
 *     [**The full parameter table** →](_generated/params-table.md)
 *
 * The site splices the table in where the link sits. GitHub, which renders
 * `docs/_content/*.md` directly and has no idea this build exists, shows a
 * working link to the same generated file.
 *
 * That degradation is the whole point of the syntax. It used to be an HTML
 * comment, which GitHub renders as nothing at all — so the authoring
 * reference's forty-row parameter table and the chart matrix, the two tables
 * this project generates precisely because they must not be maintained by
 * hand, were invisible to anyone reading the docs in the repository.
 *
 * Only a paragraph whose sole content is such a link is treated as a
 * directive. A link to a generated file in the middle of a sentence stays a
 * link, which is what a sentence means by one.
 */
export function remarkInclude() {
  const processor = this;
  return (tree, file) => {
    visit(tree, "paragraph", (node, index, parent) => {
      if (node.children.length !== 1) return;
      const [link] = node.children;
      if (link.type !== "link" || !link.url.startsWith(PREFIX)) return;

      const target = path.join(CONTENT, link.url);
      if (!fs.existsSync(target)) {
        throw new Error(
          `${file.path}: includes ${link.url}, which does not exist — ` +
            `run: python3 docs/scripts/build_reference.py`
        );
      }
      const included = processor.parse(fs.readFileSync(target, "utf8"));
      parent.children.splice(index, 1, ...included.children);
      return index + included.children.length;
    });
  };
}
