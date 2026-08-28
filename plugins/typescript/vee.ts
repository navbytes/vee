// Vee plugin SDK — typed builders that emit the xbar/SwiftBar text format Vee
// parses. Zero dependencies; runs directly on Node (which strips the types).
//
// Node only *erases* types, it does not compile them, so this file must stay
// within erasable syntax: no `enum`, no `namespace`, and no constructor
// parameter properties (`constructor(private readonly x: number)`) — Node
// rejects the file outright, which breaks every plugin that imports it, not
// just the new code.

export type Color = string;

/**
 * One presentation of a plugin's menu, in the vocabulary `visibleOn` takes:
 * the menu-bar dropdown, the transient search panel, a detached window, and
 * terminal listings (`vee search`).
 *
 * There is deliberately no `"widget"`: menu rows never reach the widget, which
 * a plugin targets whole with `<vee.surface>`.
 */
export type Surface = "menu" | "search" | "window" | "cli";

export interface ItemOptions {
  color?: Color;
  size?: number;
  font?: string;
  length?: number;
  /** Trim surrounding whitespace from the text. */
  trim?: boolean;
  /** Interpret ANSI colour escapes in the text. */
  ansi?: boolean;
  /** Expand `:emoji:` shortcodes in the text. */
  emojize?: boolean;
  href?: string;
  /** Shell command to run on click; `params` become param1..N. */
  shell?: string;
  params?: string[];
  terminal?: boolean;
  refresh?: boolean;
  /**
   * Show this line in the dropdown only, never in the menu bar. On a dropdown
   * row `dropdown: false` is the older spelling of "on no surface at all";
   * `visibleOn` says the same thing precisely, and wins when both are set.
   */
  dropdown?: boolean;
  alternate?: boolean;
  disabled?: boolean;
  checked?: boolean;
  key?: string;
  tooltip?: string;
  /** An image for the row: a base64 payload or a file path. */
  image?: string;
  /** Like `image`, but rendered as a template image (adapts to the theme). */
  templateImage?: string;
  /** SF Symbol name (SwiftBar/Vee extension). */
  sfimage?: string;
  /**
   * SF Symbol colour(s) → `sfcolor=`. A list supplies one colour per layer of
   * a multicolour symbol; Vee reads it as a comma-separated list, so keep
   * commas out of colour names.
   */
  sfColor?: Color | Color[];
  /** SF Symbol point size → `sfsize=`. */
  sfSize?: number;
  /** SF Symbol configuration string → `sfconfig=`. */
  sfConfig?: string;
  /** Render the text as inline Markdown. */
  md?: boolean;
  /** Trailing badge chip. */
  badge?: string;
  /** Render `:sf.symbol:` tokens in the text as inline SF Symbols. */
  symbolize?: boolean;
  /** Open this web URL in a web view on click → `webview=`. */
  webview?: string;
  /** Web view width in points → `webvieww=`. */
  webviewW?: number;
  /** Web view height in points → `webviewh=`. */
  webviewH?: number;
  /** Name of a macOS Shortcut to run on click → `shortcut=`. */
  shortcut?: string;
  /**
   * Render as a native, non-interactive section header (`header=true`) — a
   * real `NSMenuItem.sectionHeader`, not a disabled row dressed up as one.
   */
  header?: boolean;
  /**
   * Which edge this row's visual accessory anchors to → `accessory=`. Applies
   * uniformly to `sparkline`, `progress`, and the `chart` shapes, since they
   * share the same in-row geometry. Omitted, the accessory sits trailing.
   */
  accessory?: "leading" | "trailing";
  /**
   * The surfaces this row exists on → `visibleon=menu,window`. Omitted, the row
   * exists on all of them — targeting only ever subtracts, and it takes the
   * row's whole subtree with it.
   */
  visibleOn?: Surface[];
  /**
   * `false` keeps the row out of every filter query's reach — the search panel,
   * a window's filter field, and `vee search` — while leaving it visible and
   * clickable in an idle listing. A separate axis from `visibleOn`: where a row
   * exists and whether a query can reach it are different questions.
   */
  searchable?: boolean;
  /** Inline data series → `sparkline=1,2,3`. */
  sparkline?: number[];
  /**
   * Sparkline width in points. `"full"` stretches the chart to the row's own
   * width instead. Emitted as `accessoryw=`, which sizes whichever accessory a
   * row carries; `progressW`, `chart.w` and `accessoryW` are the same knob
   * reached from different option sets.
   */
  sparklineW?: number | "full";

  /**
   * Width in points for whichever accessory this row carries — gauge,
   * sparkline, chart, or slider → `accessoryw=`. `"full"` stretches it to the
   * row's own width. Use this to size a `slider`, which has no option of its
   * own; for the others the per-accessory options are equivalent.
   */
  accessoryW?: number | "full";

  /** Height in points for this row's accessory → `accessoryh=`. Ignored for a toggle or slider. */
  accessoryH?: number;
  /** Sparkline height in points, emitted as `accessoryh=`. */
  sparklineH?: number;
  /** Sparkline line colour → `sparklinecolor=`. Falls back to the row's `color`. */
  sparklineColor?: Color;
  /** On/off switch → `toggle=on` / `toggle=off`. */
  toggle?: boolean;
  /** Continuous control → `slider=min,max,value`. */
  slider?: { min: number; max: number; value: number };
  /**
   * Progress gauge. Pass a fraction directly → `progress=<fraction>`, or
   * `{ value, max }` → `progress=<value>,<max>`, which the format accepts
   * natively and Vee divides on parse. The two-argument form keeps the
   * author's own numbers on the wire instead of a pre-divided float.
   */
  progress?: number | { value: number; max: number };
  /** Progress track (background) colour → `progresstrackcolor=`. */
  progressTrackColor?: Color;
  /**
   * @deprecated The pre-v2 spelling of `progressTrackColor`. Still accepted and
   * still emitted as `progresstrackcolor=`; will be removed in the next major
   * version.
   */
  trackColor?: Color;
  /**
   * Progress bar width in points, emitted as `accessoryw=`. `"full"` stretches the bar to
   * the row's own width instead, the same knob `chart.w` takes.
   */
  progressW?: number | "full";
  /** Progress bar height in points, emitted as `accessoryh=`. */
  progressH?: number;
  /**
   * Categorical share chart → `pie=` / `donut=` / `stackedbar=`. All three
   * shapes take the same data — one series of non-negative values read as
   * shares of a whole — so switching `kind` needs no other change.
   *
   * `labels`/`colors` are positional against `values`. Vee reads both as
   * comma-separated lists, so a label containing a comma would be read as two
   * labels: keep commas out of segment names.
   */
  chart?: {
    kind: "pie" | "donut" | "stackedbar";
    values: number[];
    labels?: string[];
    colors?: Color[];
    /**
     * Inline size in points, emitted as `accessoryw=`/`accessoryh=`. A pie/donut is a circle, so
     * either knob sizes both sides; a stacked bar takes them independently.
     * Omitted, a chart takes its per-kind default (24pt circle, 110×12 bar).
     * `w: "full"` stretches the chart to the row's own width instead — a
     * stacked bar only, since a circle has no free width (Vee warns and falls
     * back to points on `pie`/`donut`).
     */
    w?: number | "full";
    h?: number;
  };
}

// Vee's parser (LineParser.splitTextAndParams/parseParams) reads `\|`, `\n`,
// and `\\` as escapes — for a literal `|` (which would otherwise be read as
// the text/params delimiter) and a literal newline (which would otherwise
// split a plugin's single stdout line into two corrupted ones). Order matters:
// backslashes must be escaped first, or the backslash `escapeText` inserts for
// `|`/newline would itself get re-escaped.
function escapeText(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/\|/g, "\\|").replace(/\n/g, "\\n");
}

// The characters that force a value through the quoted path. `\s` here is the
// reference definition the Python and Go SDKs mirror explicitly — each
// language's own "whitespace" class differs at the edges (Python's adds
// U+001C–U+001F, Go's `unicode.IsSpace` omits U+FEFF), so the set is written
// out there rather than inherited.
const NEEDS_QUOTE = /[\s|\\]/;

function quote(value: string): string {
  const escaped = escapeText(value);
  // Backslash also forces quoting: an unquoted (bare) value is never
  // unescaped by the parser, so anything containing an escape must go through
  // the quoted path, which is.
  //
  // A leading quote character forces it too: the parser decides a value is
  // quoted by looking at its first character, so emitting `"a"` bare would
  // round-trip back as `a` with the quotes eaten. Values that merely *contain*
  // a quote are safe bare — only the first position is read as a delimiter.
  if (NEEDS_QUOTE.test(value) || value.startsWith('"') || value.startsWith("'")) {
    return `"${escaped.replace(/"/g, '\\"')}"`;
  }
  return escaped;
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
  push("trim", options.trim);
  push("ansi", options.ansi);
  push("emojize", options.emojize);
  push("href", options.href);
  if (options.shell !== undefined) {
    push("shell", options.shell);
    (options.params ?? []).forEach((p, i) => push(`param${i + 1}`, p));
  }
  push("terminal", options.terminal);
  push("refresh", options.refresh);
  push("dropdown", options.dropdown);
  push("alternate", options.alternate);
  push("disabled", options.disabled);
  push("checked", options.checked);
  push("key", options.key);
  push("tooltip", options.tooltip);
  push("image", options.image);
  push("templateimage", options.templateImage);
  push("sfimage", options.sfimage);
  if (options.sfColor !== undefined) {
    push("sfcolor", Array.isArray(options.sfColor) ? options.sfColor.join(",") : options.sfColor);
  }
  push("sfsize", options.sfSize);
  push("sfconfig", options.sfConfig);
  push("md", options.md);
  push("badge", options.badge);
  push("symbolize", options.symbolize);
  push("webview", options.webview);
  push("webvieww", options.webviewW);
  push("webviewh", options.webviewH);
  push("shortcut", options.shortcut);
  push("header", options.header);
  push("accessory", options.accessory);
  if (options.visibleOn !== undefined) push("visibleon", options.visibleOn.join(","));
  push("searchable", options.searchable);
  if (options.sparkline !== undefined) push("sparkline", options.sparkline.map(String).join(","));
  push("sparklinecolor", options.sparklineColor);
  if (options.toggle !== undefined) push("toggle", options.toggle ? "on" : "off");
  if (options.slider !== undefined) {
    const s = options.slider;
    push("slider", `${s.min},${s.max},${s.value}`);
  }
  if (options.progress !== undefined) {
    const p = options.progress;
    push("progress", typeof p === "number" ? String(p) : `${p.value},${p.max}`);
  }
  push("progresstrackcolor", options.progressTrackColor ?? options.trackColor);
  if (options.chart !== undefined) {
    const c = options.chart;
    push(c.kind, c.values.map(String).join(","));
    if (c.labels !== undefined) push("chartlabels", c.labels.join(","));
    if (c.colors !== undefined) push("chartcolors", c.colors.join(","));
  }
  // One wire parameter sizes whichever accessory the row carries, so the
  // per-accessory options above all funnel here. They stay separate in the API
  // because a typed builder already knows which accessory you are describing —
  // the ambiguity `accessoryw=` solves for hand-written lines cannot arise.
  push("accessoryw", options.accessoryW ?? options.sparklineW ?? options.progressW ?? options.chart?.w);
  push("accessoryh", options.accessoryH ?? options.sparklineH ?? options.progressH ?? options.chart?.h);
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
    this.lines.push(this.prefix() + escapeText(text) + encode(options));
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
    this.titles.push(escapeText(text) + encode(options));
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
  /**
   * Makes this `list`/`board` row a tap target that opens a URL.
   * Scheme-filtered by Vee on parse, exactly like an `href` action's; a blocked
   * URL drops the tap and leaves the row inert, keeping its data.
   */
  url?: string;
  /**
   * Makes this row a tap target that runs a named macOS Shortcut. A row
   * declaring both opens its `url` — the same href-before-shortcut precedence
   * the menu applies. There is deliberately no `shell`: a widget row must not
   * run an arbitrary command without the menu's context.
   */
  shortcut?: string;
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
  /**
   * An optional composable **layout tree** — the escape hatch alongside the
   * five preset templates, for layouts the presets can't express (two columns,
   * a date rail, activity rings, a KPI grid). Build it with the node helpers
   * (`VStack`/`HStack`/`Text`/`Image`/`Gauge`/…). When present, Vee renders the
   * tree instead of `template`. See docs/design/widget-surface-contract.md.
   */
  layout?: WidgetNode;
}

// ── Layout tree ──────────────────────────────────────────────────────────────
// A bounded, native primitive tree (no freeform drawing). Each node maps to one
// SwiftUI primitive; Vee sanitizes/caps the tree on parse (depth 8, ≤64 nodes,
// text ≤512, sparkline ≤256, numeric clamps). Node keys are emitted in a fixed
// canonical order so the three SDKs produce byte-identical output.

/** A font token, or an explicit point size (clamped 8…96) when a token won't fit. */
export interface NodeFont {
  size?: "caption2" | "caption" | "footnote" | "subheadline" | "body" | "headline" | "title3" | "title2" | "title" | "largeTitle";
  pointSize?: number;
  weight?: "regular" | "medium" | "semibold" | "bold";
  design?: "default" | "rounded" | "monospaced" | "serif";
}

/** Per-element modifiers. Only bounded, SwiftUI-cheap options are exposed. */
export interface NodeStyle {
  font?: NodeFont;
  tint?: Color;
  /** Multiline text alignment. */
  align?: "leading" | "center" | "trailing";
  /** Uniform padding in points (clamped 0…64). */
  padding?: number;
  /** Maximum text lines (clamped 1…20). */
  lineLimit?: number;
  /** Keep numeric columns from jittering. */
  monospacedDigit?: boolean;
  /** Let a headline shrink to fit rather than truncate (clamped 0.3…1). */
  minScale?: number;
  /** Grow to fill available width (the only, bounded, width control). */
  fill?: boolean;
}

export type NodeType =
  | "vstack" | "hstack" | "zstack" | "grid"
  | "text" | "image" | "gauge" | "sparkline" | "chart" | "spacer" | "divider";

/** The three share-chart shapes, spelled as they are on a menu row. */
export type ChartNodeKind = "pie" | "donut" | "stackedbar";

export interface WidgetNode {
  type: NodeType;
  text?: string;
  /** SF Symbol name, for an `image` node (v1 renders SF Symbols only). */
  symbol?: string;
  /** `0…1` fill, for a `gauge` node. */
  value?: number;
  /** Series, for a `sparkline` node, or segment magnitudes for a `chart` one. */
  values?: number[];
  /** `"linear"` (default) or `"circular"`, for a `gauge` node. */
  gaugeStyle?: "linear" | "circular";
  /** The shape, for a `chart` node. Unknown kinds drop the leaf. */
  kind?: ChartNodeKind;
  /** Per-segment names, for a `chart` node. May be shorter than `values`. */
  labels?: string[];
  /** Per-segment colors, for a `chart` node. Recolors a prefix; unset segments take the palette. */
  colors?: Color[];
  /** Cross-axis alignment, for a container. */
  align?: string;
  /** Inter-child spacing, for a container. */
  spacing?: number;
  /** Column count, for a `grid` (default 2; clamped 1…4). */
  columns?: number;
  /** Minimum length, for a `spacer`. */
  minLength?: number;
  /** Families this node renders in (`small`/`medium`/`large`); absent = all. */
  families?: Array<"small" | "medium" | "large">;
  style?: NodeStyle;
  children?: WidgetNode[];
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
    push("layout", o.layout ? orderNode(o.layout) : undefined);
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

// ── Layout node serialization + builders ─────────────────────────────────────

/** Rebuilds a node with keys in the canonical order the three SDKs share, so
 *  output is byte-identical regardless of how the node object was constructed.
 *  `undefined` keys are dropped; `0`/`false` are kept. */
function orderNode(n: WidgetNode): Record<string, unknown> {
  const o: Record<string, unknown> = {};
  const put = (k: string, v: unknown) => { if (v !== undefined) o[k] = v; };
  put("type", n.type);
  put("text", n.text);
  put("symbol", n.symbol);
  put("value", n.value);
  put("values", n.values);
  put("gauge_style", n.gaugeStyle);
  put("kind", n.kind);
  put("labels", n.labels);
  put("colors", n.colors);
  put("align", n.align);
  put("spacing", n.spacing);
  put("columns", n.columns);
  put("min_length", n.minLength);
  put("families", n.families);
  put("style", n.style ? orderStyle(n.style) : undefined);
  put("children", n.children ? n.children.map(orderNode) : undefined);
  return o;
}

function orderStyle(s: NodeStyle): Record<string, unknown> {
  const o: Record<string, unknown> = {};
  const put = (k: string, v: unknown) => { if (v !== undefined) o[k] = v; };
  put("font", s.font ? orderFont(s.font) : undefined);
  put("tint", s.tint);
  put("align", s.align);
  put("padding", s.padding);
  put("line_limit", s.lineLimit);
  put("monospaced_digit", s.monospacedDigit);
  put("min_scale", s.minScale);
  put("fill", s.fill);
  return o;
}

function orderFont(f: NodeFont): Record<string, unknown> {
  const o: Record<string, unknown> = {};
  const put = (k: string, v: unknown) => { if (v !== undefined) o[k] = v; };
  put("size", f.size);
  put("point_size", f.pointSize);
  put("weight", f.weight);
  put("design", f.design);
  return o;
}

type ContainerOpts = { align?: string; spacing?: number; families?: WidgetNode["families"]; style?: NodeStyle };
type LeafOpts = { families?: WidgetNode["families"]; style?: NodeStyle };

/**
 * Builders for the layout tree. Namespaced (`Node.VStack(…)`) so they don't
 * collide with the card-level template builders (`Stat`/`Gauge`/…) and stay
 * clearly node-level. Each returns a `WidgetNode`; `widgetCard({ layout })`
 * serializes it in the canonical key order the three SDKs share.
 */
export const Node = {
  /** A vertical stack. */
  VStack: (children: WidgetNode[], opts: ContainerOpts = {}): WidgetNode => ({ type: "vstack", children, ...opts }),
  /** A horizontal stack — side-by-side regions (two columns, a date rail, a row of cells). */
  HStack: (children: WidgetNode[], opts: ContainerOpts = {}): WidgetNode => ({ type: "hstack", children, ...opts }),
  /** A depth stack — overlays and rings (e.g. concentric gauges). */
  ZStack: (children: WidgetNode[], opts: ContainerOpts = {}): WidgetNode => ({ type: "zstack", children, ...opts }),
  /** A grid of `columns` (default 2, clamped 1…4) — KPI boards. */
  Grid: (children: WidgetNode[], opts: ContainerOpts & { columns?: number } = {}): WidgetNode => ({ type: "grid", children, ...opts }),
  /** A text run. */
  Text: (text: string, opts: LeafOpts = {}): WidgetNode => ({ type: "text", text, ...opts }),
  /** An SF Symbol glyph (v1 renders SF Symbols only). */
  Image: (symbol: string, opts: LeafOpts = {}): WidgetNode => ({ type: "image", symbol, ...opts }),
  /** A gauge — `linear` (default) or `circular`. `value` is `0…1`. */
  Gauge: (value: number, opts: { gaugeStyle?: "linear" | "circular" } & LeafOpts = {}): WidgetNode => ({ type: "gauge", value, ...opts }),
  /** A dependency-free line chart from `values`. */
  Sparkline: (values: number[], opts: LeafOpts = {}): WidgetNode => ({ type: "sparkline", values, ...opts }),
  /**
   * A share chart — the same `pie`/`donut`/`stackedbar` a menu row draws, from
   * one series of non-negative values read as shares of a whole. `labels` and
   * `colors` are positional against `values` and may be shorter; an unset
   * segment takes its slot in Vee's eight-color categorical palette. A series
   * longer than eight is folded (not truncated) into a trailing `Other`.
   */
  Chart: (kind: ChartNodeKind, values: number[], opts: { labels?: string[]; colors?: Color[] } & LeafOpts = {}): WidgetNode =>
    ({ type: "chart", kind, values, ...opts }),
  /** Flexible empty space. */
  Spacer: (opts: { minLength?: number; families?: WidgetNode["families"] } = {}): WidgetNode => ({ type: "spacer", ...opts }),
  /** A hairline divider. */
  Divider: (opts: { families?: WidgetNode["families"] } = {}): WidgetNode => ({ type: "divider", ...opts }),
};

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

// ---------------------------------------------------------------------------
// Structured-JSON output — the optional alternative to the text protocol above.
// A plugin opts in by printing a single `{"vee":1,…}` object; Vee decodes it
// directly, with no line parsing, no `|`-separated parameters and no quoting
// rules. See docs/_content/json-output.md.
//
// `JSONMenu` deliberately mirrors `Menu` method for method — `title`,
// `dropdown`, `item`, `separator`, `submenu`, `toString`, `print` — so choosing
// a wire format does not mean learning a second builder.

/** Options for a JSON menu item.
 *
 * The JSON protocol carries a subset of the text protocol's parameters, so this
 * is a distinct type rather than `ItemOptions`: an option JSON cannot express
 * is a compile error here, not a key that is silently dropped on the way out.
 */
export interface JSONItemOptions {
  color?: Color;
  size?: number;
  href?: string;
  shell?: string;
  params?: string[];
  terminal?: boolean;
  refresh?: boolean;
  sfimage?: string;
  disabled?: boolean;
  checked?: boolean;
  tooltip?: string;
  header?: boolean;
  accessory?: "leading" | "trailing";
  /** The surfaces this item exists on; absent = all of them. */
  visibleOn?: Surface[];
  /** `false` keeps the item out of every filter query, but still browsable. */
  searchable?: boolean;
  sparkline?: number[];
  /** Sparkline width in points; `"full"` stretches it to the row's width. */
  /** @deprecated Use `accessoryWidth`. */
  sparklineWidth?: number | "full";
  /** Width for whichever accessory this item carries, or `"full"`. */
  accessoryWidth?: number | "full";
  /** Height for whichever accessory this item carries. */
  accessoryHeight?: number;
  sparklineHeight?: number;
  sparklineColor?: Color;
  toggle?: boolean;
  slider?: { min: number; max: number; value: number };
  /** A completion fraction, clamped to `0…1` by Vee. */
  progress?: number;
  progressTrackColor?: Color;
  /** Progress bar width in points; `"full"` stretches it to the row's width. */
  progressWidth?: number | "full";
  progressHeight?: number;
  chart?: {
    kind: "pie" | "donut" | "stackedbar";
    values: number[];
    labels?: string[];
    colors?: Color[];
    w?: number | "full";
    h?: number;
  };
  /** An alternate row, shown while ⌥ is held. */
  alternate?: JSONItem;
}

/** One item in a JSON menu: `JSONItemOptions` plus the structural keys. */
export interface JSONItem extends JSONItemOptions {
  text?: string;
  separator?: boolean;
  submenu?: JSONItem[];
}

// The key order every SDK emits, so the three produce byte-identical JSON.
const JSON_ITEM_KEYS: Array<keyof JSONItem> = [
  "text", "separator", "color", "size", "href", "shell", "params", "terminal",
  "refresh", "sfimage", "disabled", "checked", "tooltip", "header", "accessory",
  "visibleOn", "searchable",
  "sparkline", "sparklineWidth", "sparklineHeight", "sparklineColor",
  "accessoryWidth", "accessoryHeight",
  "toggle", "slider", "progress", "progressTrackColor", "progressWidth",
  "progressHeight", "chart", "submenu", "alternate",
];

/** Rebuilds an item with keys in the shared canonical order, dropping absent
 *  ones and recursing into `submenu`/`alternate`. */
function orderJSONItem(item: JSONItem): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of JSON_ITEM_KEYS) {
    const value = item[key];
    if (value === undefined) continue;
    if (key === "submenu") out[key] = (value as JSONItem[]).map(orderJSONItem);
    else if (key === "alternate") out[key] = orderJSONItem(value as JSONItem);
    else out[key] = value;
  }
  return out;
}

/** A JSON menu section at a given submenu depth. Mirrors `Section`. */
export class JSONSection {
  private readonly items: JSONItem[];

  constructor(items: JSONItem[]) {
    this.items = items;
  }

  item(text: string, options?: JSONItemOptions): this {
    this.items.push({ text, ...options });
    return this;
  }

  separator(): this {
    this.items.push({ separator: true });
    return this;
  }

  /** Adds an item and returns a `JSONSection` for its submenu. */
  submenu(text: string, options?: JSONItemOptions): JSONSection {
    const submenu: JSONItem[] = [];
    this.items.push({ text, ...options, submenu });
    return new JSONSection(submenu);
  }
}

/** The top-level JSON menu: title line(s) plus a dropdown. Mirrors `Menu`. */
export class JSONMenu {
  private readonly titles: JSONItem[] = [];
  private readonly body: JSONItem[] = [];

  title(text: string, options?: JSONItemOptions): this {
    this.titles.push({ text, ...options });
    return this;
  }

  get dropdown(): JSONSection {
    return new JSONSection(this.body);
  }

  toString(): string {
    const payload: Record<string, unknown> = { vee: 1, title: this.titles.map(orderJSONItem) };
    if (this.body.length) payload.items = this.body.map(orderJSONItem);
    return JSON.stringify(payload);
  }

  print(): void {
    process.stdout.write(this.toString() + "\n");
  }
}
