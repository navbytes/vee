#!/usr/bin/env node
// Exercises the richer rendering params (Markdown, badge, symbolize) so the
// fixture drift guard and the Swift parser tests cover them.
import { fileURLToPath } from "node:url";
import { Menu } from "../src/vee.ts";

export function build(): string {
  const menu = new Menu();
  menu.title("Build", { sfimage: "hammer" });

  const d = menu.dropdown;
  d.item("**Bold** and _italic_", { md: true });
  d.item("Inbox", { badge: "12" });
  d.item("Status :checkmark.circle:", { symbolize: true });
  return menu.toString();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.stdout.write(build() + "\n");
}
