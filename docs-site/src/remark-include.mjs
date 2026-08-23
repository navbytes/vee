import fs from "node:fs";
import path from "node:path";
import { visit } from "unist-util-visit";

const CONTENT = path.resolve("../docs/_content");
const INCLUDE = /^<!--\s*include:\s*(\S+)\s*-->$/;

/**
 * Expand `<!-- include: _generated/x.md -->` into the partial's parsed content.
 *
 * The generated reference tables live in `docs/_content/_generated/` and are
 * pulled into pages rather than pasted, so `docs/api/params.json` stays the one
 * place the parameter surface is written down. Without this the directive is an
 * HTML comment, and every generated table would silently render as nothing —
 * the failure mode being an empty section rather than an error.
 *
 * Ported from `read_content` in the Python builder this replaces.
 */
export function remarkInclude() {
  const processor = this;
  return (tree, file) => {
    visit(tree, "html", (node, index, parent) => {
      const match = INCLUDE.exec(node.value.trim());
      if (!match) return;
      const target = path.join(CONTENT, match[1]);
      if (!fs.existsSync(target)) {
        throw new Error(
          `${file.path}: includes ${match[1]}, which does not exist — ` +
            `run python3 docs/scripts/build_reference.py first`
        );
      }
      const included = processor.parse(fs.readFileSync(target, "utf8"));
      parent.children.splice(index, 1, ...included.children);
    });
  };
}
