// Vee plugin SDK — typed builders that emit the xbar/SwiftBar text format Vee
// parses. Zero dependencies; runs directly on Node (which strips the types).

export type Color = string;

export interface ItemOptions {
  color?: Color;
  size?: number;
  font?: string;
  length?: number;
  href?: string;
  /** Shell command to run on click; `params` become param1..N. */
  shell?: string;
  params?: string[];
  terminal?: boolean;
  refresh?: boolean;
  alternate?: boolean;
  disabled?: boolean;
  checked?: boolean;
  key?: string;
  tooltip?: string;
  /** SF Symbol name (SwiftBar/Vee extension). */
  sfimage?: string;
}

function quote(value: string): string {
  if (/[\s|]/.test(value)) return `"${value.replace(/"/g, '\\"')}"`;
  return value;
}

function encode(options?: ItemOptions): string {
  if (!options) return "";
  const parts: string[] = [];
  const push = (key: string, value: unknown) => {
    if (value !== undefined && value !== null) parts.push(`${key}=${quote(String(value))}`);
  };
  push("color", options.color);
  push("size", options.size);
  push("font", options.font);
  push("length", options.length);
  push("href", options.href);
  if (options.shell !== undefined) {
    push("shell", options.shell);
    (options.params ?? []).forEach((p, i) => push(`param${i + 1}`, p));
  }
  push("terminal", options.terminal);
  push("refresh", options.refresh);
  push("alternate", options.alternate);
  push("disabled", options.disabled);
  push("checked", options.checked);
  push("key", options.key);
  push("tooltip", options.tooltip);
  push("sfimage", options.sfimage);
  return parts.length ? " | " + parts.join(" ") : "";
}

/** A menu section at a given submenu depth (0 = top level). */
export class Section {
  private readonly lines: string[];
  private readonly depth: number;

  constructor(lines: string[], depth: number) {
    this.lines = lines;
    this.depth = depth;
  }

  private prefix(): string {
    return "-".repeat(this.depth * 2);
  }

  item(text: string, options?: ItemOptions): this {
    this.lines.push(this.prefix() + text + encode(options));
    return this;
  }

  separator(): this {
    this.lines.push(this.prefix() + "---");
    return this;
  }

  /** Adds an item and returns a `Section` for its submenu. */
  submenu(text: string, options?: ItemOptions): Section {
    this.item(text, options);
    return new Section(this.lines, this.depth + 1);
  }
}

/** The top-level menu: title line(s) plus a dropdown. */
export class Menu {
  private readonly titles: string[] = [];
  private readonly body: string[] = [];

  title(text: string, options?: ItemOptions): this {
    this.titles.push(text + encode(options));
    return this;
  }

  get dropdown(): Section {
    return new Section(this.body, 0);
  }

  toString(): string {
    const head = this.titles.join("\n");
    return this.body.length ? `${head}\n---\n${this.body.join("\n")}` : head;
  }

  print(): void {
    process.stdout.write(this.toString() + "\n");
  }
}
