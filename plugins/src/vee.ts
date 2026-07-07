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
  /** Render the text as inline Markdown. */
  md?: boolean;
  /** Trailing badge chip. */
  badge?: string;
  /** Render `:sf.symbol:` tokens in the text as inline SF Symbols. */
  symbolize?: boolean;
  /** Inline data series → `sparkline=1,2,3`. */
  sparkline?: number[];
  /** On/off switch → `toggle=on` / `toggle=off`. */
  toggle?: boolean;
  /** Continuous control → `slider=min,max,value`. */
  slider?: { min: number; max: number; value: number };
  /**
   * Progress gauge → `progress=<fraction>`. Pass a fraction directly, or
   * `{ value, max }` to have the SDK compute `value / max`.
   */
  progress?: number | { value: number; max: number };
  /** Progress track (background) color → `trackcolor=`. */
  trackColor?: Color;
  /** Progress bar width in points → `progressw=`. */
  progressW?: number;
  /** Progress bar height in points → `progressh=`. */
  progressH?: number;
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
  push("md", options.md);
  push("badge", options.badge);
  push("symbolize", options.symbolize);
  if (options.sparkline !== undefined) push("sparkline", options.sparkline.map(String).join(","));
  if (options.toggle !== undefined) push("toggle", options.toggle ? "on" : "off");
  if (options.slider !== undefined) {
    const s = options.slider;
    push("slider", `${s.min},${s.max},${s.value}`);
  }
  if (options.progress !== undefined) {
    const p = options.progress;
    const fraction = typeof p === "number" ? p : p.max === 0 ? 0 : p.value / p.max;
    push("progress", String(fraction));
  }
  push("trackcolor", options.trackColor);
  push("progressw", options.progressW);
  push("progressh", options.progressH);
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

// ---------------------------------------------------------------------------
// Widget surface contract — the rich JSON payload a plugin prints to stdout
// when invoked with VEE_TARGET=widget, instead of the xbar/SwiftBar text
// format above. See docs/design/widget-surface-contract.md §4.

export type WidgetTemplate = "stat" | "gauge" | "trend" | "list" | "board";
export type WidgetStatus = "ok" | "warning" | "error";
export type WidgetActionKind = "refresh" | "href" | "shortcut";

export interface WidgetCardItem {
  label: string;
  value?: string;
  symbol?: string;
  tint?: Color;
}

export interface WidgetCardAction {
  kind: WidgetActionKind;
  label: string;
  /** The URL to open, for `kind: "href"`. Scheme-filtered by Vee on parse. */
  url?: string;
  /** The Shortcut name to run, for `kind: "shortcut"`. */
  name?: string;
}

export interface WidgetCardOptions {
  template?: WidgetTemplate;
  title?: string;
  /** SF Symbol name for the glyph. */
  symbol?: string;
  tint?: Color;
  /** The headline value, already formatted (e.g. `"$18.2k"`). */
  value?: string;
  caption?: string;
  detail?: string;
  status?: WidgetStatus;
  /** `0…1`; clamped by Vee if out of range. */
  progress?: number;
  trend?: number[];
  /** Rows for the `list`/`board` templates. */
  items?: WidgetCardItem[];
  /** Up to two are rendered as buttons; the templates decide which. */
  actions?: WidgetCardAction[];
  /** Seconds — a hint for the next widget reload. */
  refreshAfter?: number;
  /** Seconds — when the tile should show a stale treatment. */
  staleAfter?: number;
}

/**
 * The widget-mode payload (see `WidgetCardOptions`). Call `.toString()`/
 * `.print()` exactly once per `VEE_TARGET=widget` run with the richest data
 * available — each native template (small/medium/large) takes what fits.
 */
export class WidgetCard {
  private readonly options: WidgetCardOptions;

  constructor(options: WidgetCardOptions = {}) {
    this.options = options;
  }

  toString(): string {
    const o = this.options;
    const payload: Record<string, unknown> = { vee_widget: 1 };
    const push = (key: string, value: unknown) => {
      if (value !== undefined) payload[key] = value;
    };
    push("template", o.template);
    push("title", o.title);
    push("symbol", o.symbol);
    push("tint", o.tint);
    push("value", o.value);
    push("caption", o.caption);
    push("detail", o.detail);
    push("status", o.status);
    push("progress", o.progress);
    push("trend", o.trend);
    push("items", o.items);
    push("actions", o.actions);
    push("refresh_after", o.refreshAfter);
    push("stale_after", o.staleAfter);
    return JSON.stringify(payload);
  }

  print(): void {
    process.stdout.write(this.toString() + "\n");
  }
}

/** Builds a widget card. Equivalent to `new WidgetCard(options)`. */
export function widgetCard(options?: WidgetCardOptions): WidgetCard {
  return new WidgetCard(options);
}

type TemplatelessOptions = Omit<WidgetCardOptions, "template">;

/** Glyph, big `value` in `tint`, `title`/`caption`. The default template. */
export function Stat(options: TemplatelessOptions): WidgetCard {
  return new WidgetCard({ ...options, template: "stat" });
}

/** Stat + a native gauge from `progress`. */
export function Gauge(options: TemplatelessOptions): WidgetCard {
  return new WidgetCard({ ...options, template: "gauge" });
}

/** Stat + a sparkline from `trend`. */
export function Trend(options: TemplatelessOptions): WidgetCard {
  return new WidgetCard({ ...options, template: "trend" });
}

/** `title` header + `items` as rows. */
export function List(options: TemplatelessOptions): WidgetCard {
  return new WidgetCard({ ...options, template: "list" });
}

/** A compact grid of `items` as stat cells (KPI board). */
export function Board(options: TemplatelessOptions): WidgetCard {
  return new WidgetCard({ ...options, template: "board" });
}
