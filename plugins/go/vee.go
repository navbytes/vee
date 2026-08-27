// Package vee is a zero-dependency Go SDK for writing Vee plugins with typed
// builders instead of hand-formatting the xbar/SwiftBar text protocol.
//
// It mirrors the TypeScript and Python SDKs — the same builder shape, option
// names, encoding order, and quoting — so a plugin reads the same in any of the
// three languages and all produce byte-identical output for the same menu.
package vee

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

// Options are the per-item parameters. Pointer fields are optional: a nil
// pointer is omitted, matching the TS SDK's `undefined`. Use the helpers
// (Str, Int, Bool, Float) to set them concisely.
//
// Naming rule for a control's knobs: inside a control's own struct they are
// unprefixed (Chart.W, Chart.FullWidth), because the struct already names the
// control; on this flat struct they carry the control's name (ProgressW,
// ProgressFullWidth, SparklineW). The two spellings are the same rule applied
// to two shapes, not two conventions.
type Options struct {
	Color  *string
	Size   *int
	Font   *string
	Length *int
	// Trim removes surrounding whitespace from the text.
	Trim *bool
	// Ansi interprets ANSI colour escapes in the text.
	Ansi *bool
	// Emojize expands `:emoji:` shortcodes in the text.
	Emojize  *bool
	Href     *string
	Shell    *string
	Params   []string
	Terminal *bool
	Refresh  *bool
	// Dropdown shows this line in the dropdown only, never in the menu bar.
	// On a dropdown row it is the older spelling of "on no surface at all";
	// VisibleOn says the same thing precisely, and wins when both are set.
	Dropdown  *bool
	Alternate *bool
	Disabled  *bool
	Checked   *bool
	Key       *string
	Tooltip   *string
	// Image is a base64 payload or file path for the row's image.
	Image *string
	// TemplateImage is like Image, but adapts to the theme.
	TemplateImage *string
	SFImage       *string
	// SFColor sets the SF Symbol's colour(s): one entry per layer of a
	// multicolour symbol. Vee reads it as a comma-separated list, so keep
	// commas out of colour names.
	SFColor []string
	// SFSize is the SF Symbol's point size.
	SFSize *float64
	// SFConfig is the SF Symbol configuration string.
	SFConfig  *string
	MD        *bool
	Badge     *string
	Symbolize *bool
	// Webview opens this web URL in a web view on click.
	Webview *string
	// WebviewW and WebviewH size that web view, in points.
	WebviewW *float64
	WebviewH *float64
	// Shortcut is the name of a macOS Shortcut to run on click.
	Shortcut *string
	// Header renders the row as a native, non-interactive section header --
	// a real NSMenuItem.sectionHeader, not a disabled row dressed up as one.
	Header *bool
	// Accessory is which edge this row's visual accessory anchors to,
	// "leading" or "trailing". It applies uniformly to Sparkline, Progress
	// and Chart, which share the same in-row geometry. Nil sits trailing.
	Accessory *string
	// VisibleOn lists the surfaces this row exists on -- "menu", "search",
	// "window", "cli" (`visibleon=`). Nil means all of them: targeting only
	// ever subtracts, and it takes the row's whole subtree with it.
	VisibleOn []string
	// Searchable set to false keeps the row out of every filter query's reach
	// -- the search panel, a window's filter field, and `vee search` -- while
	// leaving it visible and clickable in an idle listing. A separate axis
	// from VisibleOn: where a row exists and whether a query can reach it are
	// different questions.
	Searchable *bool

	// Vee-native rich params, emitted last in a fixed order shared across SDKs.
	Sparkline []float64
	// SparklineW and SparklineH set the chart's inline size in points.
	SparklineW *float64
	// AccessoryW sets the width in points for whichever accessory this row
	// carries -- gauge, sparkline, chart, or slider (`accessoryw=`). Use it to
	// size a Slider, which has no field of its own; for the others the
	// per-accessory fields below are equivalent.
	AccessoryW *float64
	// AccessoryH sets the accessory's height in points (`accessoryh=`).
	// Ignored for a Toggle or Slider, whose height is its control size.
	AccessoryH *float64
	// AccessoryFullWidth emits `accessoryw=full`: stretch the accessory to the
	// row's own width. Refused on a pie or donut, which can only fill a width
	// by growing the row.
	AccessoryFullWidth bool
	// SparklineFullWidth emits `accessoryw=full`: stretch the chart to the
	// row's own width rather than a fixed number of points. Takes precedence
	// over SparklineW.
	SparklineFullWidth bool
	SparklineH         *float64
	// SparklineColor is the line colour; falls back to the row's Color.
	SparklineColor *string
	Toggle         *bool
	Slider         *Slider
	// Progress is the completion fraction, 0..1, emitted as
	// `progress=<fraction>`.
	Progress *float64
	// ProgressValue and ProgressMax are the alternative to Progress: set both
	// to emit the format's two-argument form (`progress=72,100`) and let Vee
	// do the division on parse, keeping your own numbers on the wire. They
	// take precedence over Progress.
	ProgressValue *float64
	ProgressMax   *float64
	// ProgressTrackColor is the bar's background track colour.
	ProgressTrackColor *string
	// TrackColor is the pre-v2 spelling of ProgressTrackColor.
	//
	// Deprecated: use ProgressTrackColor. Still accepted and still emitted
	// (as `progresstrackcolor=`); removed in the next major version.
	TrackColor *string
	ProgressW  *float64
	// ProgressFullWidth emits `accessoryw=full`: stretch the bar to the row's
	// own width rather than a fixed number of points. Takes precedence over
	// ProgressW, mirroring Chart.FullWidth.
	ProgressFullWidth bool
	ProgressH         *float64
	Chart             *Chart
}

// Chart is a categorical share chart, emitted as `pie=`/`donut=`/`stackedbar=`
// plus its positional `chartlabels=`/`chartcolors=`. All three shapes take the
// same data — one series of non-negative values read as shares of a whole — so
// switching Kind needs no other change.
//
// Labels and Colors are positional against Values. Vee reads both as
// comma-separated lists, so a label containing a comma would be read as two
// labels: keep commas out of segment names.
type Chart struct {
	// Kind is "pie", "donut", or "stackedbar".
	Kind   string
	Values []float64
	Labels []string
	Colors []string
	// W and H set the inline size in points (`accessoryw=`/`accessoryh=`). A pie or
	// donut is a circle, so either one sizes both sides; a stacked bar takes
	// them independently. Nil takes the per-kind default (24pt circle,
	// 110x12 bar).
	W *float64
	H *float64
	// FullWidth emits `accessoryw=full`: stretch to the row's own width rather
	// than a fixed number of points. Takes precedence over W. Stacked bars
	// only — a circle has no free width, and Vee warns and falls back to
	// points on a pie/donut.
	FullWidth bool
}

// Slider is a continuous control bounded by Min..Max at the current Value,
// emitted as `slider=min,max,value`.
type Slider struct {
	Min   float64
	Max   float64
	Value float64
}

// Str returns a pointer to s, for setting optional string options.
func Str(s string) *string { return &s }

// Int returns a pointer to i, for setting optional int options.
func Int(i int) *int { return &i }

// Bool returns a pointer to b, for setting optional bool options.
func Bool(b bool) *bool { return &b }

// Float returns a pointer to f, for setting optional float64 options.
func Float(f float64) *float64 { return &f }

// fmtFloat formats f exactly as JavaScript's String(Number) does (ECMA-262
// Number::toString), which is the number format all three SDKs commit to.
//
// Go's own 'g' verb is not that format and diverges much earlier than it
// looks: it renders 1000000 as "1e+06" where JavaScript and Python both render
// "1000000". Since the fixtures are shared byte-for-byte, the rule has to be
// written down once rather than inherited from each language's default.
func fmtFloat(f float64) string {
	switch {
	case math.IsNaN(f):
		return "NaN"
	case math.IsInf(f, 1):
		return "Infinity"
	case math.IsInf(f, -1):
		return "-Infinity"
	case f == 0:
		return "0" // also normalizes -0, matching String(-0)
	}

	negative := math.Signbit(f)
	// Shortest round-trippable digits, as "d.ddde±dd".
	mantissa, exponent, _ := strings.Cut(strconv.FormatFloat(math.Abs(f), 'e', -1, 64), "e")
	exp10, _ := strconv.Atoi(exponent)
	digits := strings.Replace(mantissa, ".", "", 1)
	k := len(digits)
	n := exp10 + 1 // position of the decimal point (ECMA-262 `n`)

	var out string
	switch {
	case k <= n && n <= 21:
		out = digits + strings.Repeat("0", n-k)
	case 0 < n && n <= 21:
		out = digits[:n] + "." + digits[n:]
	case -6 < n && n <= 0:
		out = "0." + strings.Repeat("0", -n) + digits
	default:
		e := n - 1
		sign := "+"
		if e < 0 {
			sign = "-"
			e = -e
		}
		if k == 1 {
			out = digits + "e" + sign + strconv.Itoa(e)
		} else {
			out = digits[:1] + "." + digits[1:] + "e" + sign + strconv.Itoa(e)
		}
	}
	if negative {
		return "-" + out
	}
	return out
}

// needsQuote reports whether value must go through the quoted path: it holds
// one of the two characters the format reserves (`|`, `\`) or one of
// JavaScript's `\s` characters, which is the set the TypeScript and Python
// SDKs use. Go's unicode.IsSpace is close but not the same set -- it omits
// U+FEFF and includes U+0085 -- so the characters are listed rather than
// inherited.
func needsQuote(value string) bool {
	for _, r := range value {
		switch r {
		case '|', '\\', '\t', '\n', '\v', '\f', '\r', ' ',
			'\u00a0', '\u1680', '\u2028', '\u2029', '\u202f', '\u205f', '\u3000', '\ufeff':
			return true
		}
		if r >= '\u2000' && r <= '\u200a' {
			return true
		}
	}
	return false
}

// escapeText escapes the three characters Vee's parser
// (LineParser.splitTextAndParams/parseParams) reads back as `\|`/`\n`/`\\`: a
// literal `|` would otherwise be read as the text/params delimiter, and a
// literal newline would otherwise split a plugin's single stdout line into
// two corrupted ones. Order matters: backslashes are escaped first, or the
// backslash inserted for `|`/newline would itself get re-escaped.
func escapeText(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, `|`, `\|`)
	value = strings.ReplaceAll(value, "\n", `\n`)
	return value
}

func quote(value string) string {
	escaped := escapeText(value)
	// Backslash also forces quoting: an unquoted (bare) value is never
	// unescaped by the parser, so anything containing an escape must go
	// through the quoted path, which is.
	//
	// A leading quote character forces it too: the parser decides a value is
	// quoted by looking at its first character, so emitting `"a"` bare would
	// round-trip back as `a` with the quotes eaten. Values that merely
	// *contain* a quote are safe bare -- only the first position is read as a
	// delimiter.
	if needsQuote(value) || strings.HasPrefix(value, `"`) || strings.HasPrefix(value, "'") {
		return `"` + strings.ReplaceAll(escaped, `"`, `\"`) + `"`
	}
	return escaped
}

func encode(o *Options) string {
	if o == nil {
		return ""
	}
	var parts []string
	push := func(key, value string) { parts = append(parts, key+"="+quote(value)) }
	pushBool := func(key string, v *bool) {
		if v != nil {
			if *v {
				push(key, "true")
			} else {
				push(key, "false")
			}
		}
	}

	if o.Color != nil {
		push("color", *o.Color)
	}
	if o.Size != nil {
		push("size", fmt.Sprintf("%d", *o.Size))
	}
	if o.Font != nil {
		push("font", *o.Font)
	}
	if o.Length != nil {
		push("length", fmt.Sprintf("%d", *o.Length))
	}
	pushBool("trim", o.Trim)
	pushBool("ansi", o.Ansi)
	pushBool("emojize", o.Emojize)
	if o.Href != nil {
		push("href", *o.Href)
	}
	if o.Shell != nil {
		push("shell", *o.Shell)
		for i, p := range o.Params {
			push(fmt.Sprintf("param%d", i+1), p)
		}
	}
	pushBool("terminal", o.Terminal)
	pushBool("refresh", o.Refresh)
	pushBool("dropdown", o.Dropdown)
	pushBool("alternate", o.Alternate)
	pushBool("disabled", o.Disabled)
	pushBool("checked", o.Checked)
	if o.Key != nil {
		push("key", *o.Key)
	}
	if o.Tooltip != nil {
		push("tooltip", *o.Tooltip)
	}
	if o.Image != nil {
		push("image", *o.Image)
	}
	if o.TemplateImage != nil {
		push("templateimage", *o.TemplateImage)
	}
	if o.SFImage != nil {
		push("sfimage", *o.SFImage)
	}
	if o.SFColor != nil {
		push("sfcolor", strings.Join(o.SFColor, ","))
	}
	if o.SFSize != nil {
		push("sfsize", fmtFloat(*o.SFSize))
	}
	if o.SFConfig != nil {
		push("sfconfig", *o.SFConfig)
	}
	pushBool("md", o.MD)
	if o.Badge != nil {
		push("badge", *o.Badge)
	}
	pushBool("symbolize", o.Symbolize)
	if o.Webview != nil {
		push("webview", *o.Webview)
	}
	if o.WebviewW != nil {
		push("webvieww", fmtFloat(*o.WebviewW))
	}
	if o.WebviewH != nil {
		push("webviewh", fmtFloat(*o.WebviewH))
	}
	if o.Shortcut != nil {
		push("shortcut", *o.Shortcut)
	}
	pushBool("header", o.Header)
	if o.Accessory != nil {
		push("accessory", *o.Accessory)
	}
	if o.VisibleOn != nil {
		push("visibleon", strings.Join(o.VisibleOn, ","))
	}
	pushBool("searchable", o.Searchable)

	if o.Sparkline != nil {
		nums := make([]string, len(o.Sparkline))
		for i, v := range o.Sparkline {
			nums[i] = fmtFloat(v)
		}
		push("sparkline", strings.Join(nums, ","))
	}
	if o.SparklineColor != nil {
		push("sparklinecolor", *o.SparklineColor)
	}
	if o.Toggle != nil {
		if *o.Toggle {
			push("toggle", "on")
		} else {
			push("toggle", "off")
		}
	}
	if o.Slider != nil {
		push("slider", fmtFloat(o.Slider.Min)+","+fmtFloat(o.Slider.Max)+","+fmtFloat(o.Slider.Value))
	}
	if o.ProgressValue != nil && o.ProgressMax != nil {
		push("progress", fmtFloat(*o.ProgressValue)+","+fmtFloat(*o.ProgressMax))
	} else if o.Progress != nil {
		push("progress", fmtFloat(*o.Progress))
	}
	if o.ProgressTrackColor != nil {
		push("progresstrackcolor", *o.ProgressTrackColor)
	} else if o.TrackColor != nil {
		push("progresstrackcolor", *o.TrackColor)
	}
	if o.Chart != nil {
		nums := make([]string, len(o.Chart.Values))
		for i, v := range o.Chart.Values {
			nums[i] = fmtFloat(v)
		}
		push(o.Chart.Kind, strings.Join(nums, ","))
		if o.Chart.Labels != nil {
			push("chartlabels", strings.Join(o.Chart.Labels, ","))
		}
		if o.Chart.Colors != nil {
			push("chartcolors", strings.Join(o.Chart.Colors, ","))
		}
	}

	// One wire parameter sizes whichever accessory the row carries, so every
	// per-accessory field funnels here. They stay separate in the API because a
	// typed builder already knows which accessory you are describing -- the
	// ambiguity accessoryw= solves for hand-written lines cannot arise. The
	// three SDKs are compared byte-for-byte against plugins/fixtures/, so this
	// order is a contract, not a preference.
	switch {
	case o.AccessoryFullWidth || o.SparklineFullWidth || o.ProgressFullWidth ||
		(o.Chart != nil && o.Chart.FullWidth):
		push("accessoryw", "full")
	case o.AccessoryW != nil:
		push("accessoryw", fmtFloat(*o.AccessoryW))
	case o.SparklineW != nil:
		push("accessoryw", fmtFloat(*o.SparklineW))
	case o.ProgressW != nil:
		push("accessoryw", fmtFloat(*o.ProgressW))
	case o.Chart != nil && o.Chart.W != nil:
		push("accessoryw", fmtFloat(*o.Chart.W))
	}
	switch {
	case o.AccessoryH != nil:
		push("accessoryh", fmtFloat(*o.AccessoryH))
	case o.SparklineH != nil:
		push("accessoryh", fmtFloat(*o.SparklineH))
	case o.ProgressH != nil:
		push("accessoryh", fmtFloat(*o.ProgressH))
	case o.Chart != nil && o.Chart.H != nil:
		push("accessoryh", fmtFloat(*o.Chart.H))
	}

	if len(parts) == 0 {
		return ""
	}
	return " | " + strings.Join(parts, " ")
}

// Section is a menu section at a given submenu depth (0 = top level).
type Section struct {
	lines *[]string
	depth int
}

func (s Section) prefix() string { return strings.Repeat("-", s.depth*2) }

// Item adds a menu item. Pass nil for opts when there are no options.
func (s Section) Item(text string, opts *Options) Section {
	*s.lines = append(*s.lines, s.prefix()+escapeText(text)+encode(opts))
	return s
}

// Separator adds a "---" separator at this depth.
func (s Section) Separator() Section {
	*s.lines = append(*s.lines, s.prefix()+"---")
	return s
}

// Submenu adds an item and returns a Section for its submenu.
func (s Section) Submenu(text string, opts *Options) Section {
	s.Item(text, opts)
	return Section{lines: s.lines, depth: s.depth + 1}
}

// Menu is the top-level menu: title line(s) plus a dropdown.
type Menu struct {
	titles []string
	body   []string
}

// Title adds a menu-bar title line. Call more than once for multiple lines.
func (m *Menu) Title(text string, opts *Options) *Menu {
	m.titles = append(m.titles, escapeText(text)+encode(opts))
	return m
}

// Dropdown returns a Section for the dropdown body (everything after "---").
func (m *Menu) Dropdown() Section {
	return Section{lines: &m.body, depth: 0}
}

// String renders the whole menu to the text protocol.
func (m *Menu) String() string {
	head := strings.Join(m.titles, "\n")
	if len(m.body) > 0 {
		return head + "\n---\n" + strings.Join(m.body, "\n")
	}
	return head
}

// Print writes String() plus a trailing newline to stdout. This is what a real
// plugin calls.
func (m *Menu) Print() {
	fmt.Fprintln(os.Stdout, m.String())
}

// ---------------------------------------------------------------------------
// Widget surface contract — the rich JSON payload a plugin prints to stdout
// when invoked with VEE_TARGET=widget, instead of the xbar/SwiftBar text
// protocol above. See docs/design/widget-surface-contract.md §4. Mirrors the
// TypeScript SDK's WidgetCard field-for-field (same JSON keys, same order).

// WidgetTemplate is the native template a card renders with.
type WidgetTemplate string

// The five native templates (see the design doc §5).
const (
	TemplateStat  WidgetTemplate = "stat"
	TemplateGauge WidgetTemplate = "gauge"
	TemplateTrend WidgetTemplate = "trend"
	TemplateList  WidgetTemplate = "list"
	TemplateBoard WidgetTemplate = "board"
)

// WidgetStatus is the health state a card reports.
type WidgetStatus string

// The three status values.
const (
	StatusOK      WidgetStatus = "ok"
	StatusWarning WidgetStatus = "warning"
	StatusError   WidgetStatus = "error"
)

// WidgetActionKind is what a card action button does when tapped.
type WidgetActionKind string

// The three action kinds. There is deliberately no "shell" — see the design
// doc §6: a widget button must not run an arbitrary command.
const (
	ActionRefresh  WidgetActionKind = "refresh"
	ActionHref     WidgetActionKind = "href"
	ActionShortcut WidgetActionKind = "shortcut"
)

// WidgetCardItem is one row for the list/board templates. A row declaring URL
// or Shortcut is a tap target; one declaring neither renders inert.
type WidgetCardItem struct {
	Label  string  `json:"label"`
	Value  *string `json:"value,omitempty"`
	Symbol *string `json:"symbol,omitempty"`
	Tint   *string `json:"tint,omitempty"`
	// URL is opened when the row is tapped. Scheme-filtered by Vee on parse,
	// exactly like an href action's; a blocked URL drops the tap and leaves the
	// row inert, keeping its data.
	URL *string `json:"url,omitempty"`
	// Shortcut is the macOS Shortcut the row runs when tapped. A row declaring
	// both opens its URL — the same href-before-shortcut precedence the menu
	// applies. There is deliberately no Shell: a widget row must not run an
	// arbitrary command without the menu's context.
	Shortcut *string `json:"shortcut,omitempty"`
}

// WidgetCardAction is one button; up to two are rendered.
type WidgetCardAction struct {
	Kind  WidgetActionKind `json:"kind"`
	Label string           `json:"label"`
	// URL is the destination for Kind == ActionHref. Scheme-filtered by Vee
	// on parse.
	URL *string `json:"url,omitempty"`
	// Name is the Shortcut name to run, for Kind == ActionShortcut.
	Name *string `json:"name,omitempty"`
}

// WidgetCard is the VEE_TARGET=widget stdout payload — a plugin builds one
// with the richest data it has and calls String()/Print() exactly once per
// run; each native template (small/medium/large) takes what fits.
type WidgetCard struct {
	Template WidgetTemplate `json:"template,omitempty"`
	Title    *string        `json:"title,omitempty"`
	// Symbol is an SF Symbol name for the glyph.
	Symbol *string `json:"symbol,omitempty"`
	Tint   *string `json:"tint,omitempty"`
	// Value is the headline value, already formatted (e.g. "$18.2k").
	Value   *string      `json:"value,omitempty"`
	Caption *string      `json:"caption,omitempty"`
	Detail  *string      `json:"detail,omitempty"`
	Status  WidgetStatus `json:"status,omitempty"`
	// Progress is 0…1; clamped by Vee if out of range.
	Progress *float64  `json:"progress,omitempty"`
	Trend    []float64 `json:"trend,omitempty"`
	// Items are rows for the list/board templates.
	Items []WidgetCardItem `json:"items,omitempty"`
	// Actions: up to two are rendered as buttons; the templates decide which.
	Actions []WidgetCardAction `json:"actions,omitempty"`
	// RefreshAfter is seconds — a hint for the next widget reload.
	RefreshAfter *float64 `json:"refresh_after,omitempty"`
	// StaleAfter is seconds — when the tile should show a stale treatment.
	StaleAfter *float64 `json:"stale_after,omitempty"`
	// Layout is an optional composable layout tree — the escape hatch
	// alongside the five preset templates. When present, Vee renders the tree
	// instead of Template. Build it with Node.VStack/HStack/Text/… .
	Layout *WidgetNode `json:"layout,omitempty"`
}

// ── Layout tree ──────────────────────────────────────────────────────────────
// The composable escape hatch alongside the five preset templates. Field order
// on WidgetNode/WidgetNodeStyle/WidgetNodeFont is the canonical key order the
// three SDKs share, so encoding/json produces byte-identical output.

// WidgetNodeFont is a text node's font: a semantic token (Size) or an explicit
// PointSize (clamped 8…96 by Vee) when a token won't fit.
type WidgetNodeFont struct {
	Size      *string  `json:"size,omitempty"`
	PointSize *float64 `json:"point_size,omitempty"`
	Weight    *string  `json:"weight,omitempty"`
	Design    *string  `json:"design,omitempty"`
}

// WidgetNodeStyle is the bounded set of per-element modifiers a node can carry.
type WidgetNodeStyle struct {
	Font  *WidgetNodeFont `json:"font,omitempty"`
	Tint  *string         `json:"tint,omitempty"`
	Align *string         `json:"align,omitempty"`
	// Padding is uniform, in points (clamped 0…64).
	Padding *float64 `json:"padding,omitempty"`
	// LineLimit is the maximum text lines (clamped 1…20).
	LineLimit *int `json:"line_limit,omitempty"`
	// MonospacedDigit keeps numeric columns from jittering.
	MonospacedDigit *bool `json:"monospaced_digit,omitempty"`
	// MinScale lets a headline shrink to fit rather than truncate (clamped 0.3…1).
	MinScale *float64 `json:"min_scale,omitempty"`
	// Fill grows to fill the available width (the only, bounded, width control).
	Fill *bool `json:"fill,omitempty"`
}

// WidgetNode is one node in a card's layout tree. Vee sanitizes/caps the tree
// on parse (depth 8, ≤64 nodes, text ≤512, sparkline ≤256, numeric clamps).
type WidgetNode struct {
	// Type is vstack/hstack/zstack/grid (containers) or
	// text/image/gauge/sparkline/chart/spacer/divider (leaves).
	Type   string   `json:"type"`
	Text   *string  `json:"text,omitempty"`
	Symbol *string  `json:"symbol,omitempty"`
	Value  *float64 `json:"value,omitempty"`
	// Values is the series for a sparkline node, or the segment magnitudes for
	// a chart node.
	Values     []float64 `json:"values,omitempty"`
	GaugeStyle *string   `json:"gauge_style,omitempty"`
	// Kind is a chart node's shape: "pie", "donut" or "stackedbar".
	Kind *string `json:"kind,omitempty"`
	// Labels and Colors are a chart node's per-segment names and color
	// overrides, positional against Values and allowed to be shorter.
	Labels    []string         `json:"labels,omitempty"`
	Colors    []string         `json:"colors,omitempty"`
	Align     *string          `json:"align,omitempty"`
	Spacing   *float64         `json:"spacing,omitempty"`
	Columns   *int             `json:"columns,omitempty"`
	MinLength *float64         `json:"min_length,omitempty"`
	Families  []string         `json:"families,omitempty"`
	Style     *WidgetNodeStyle `json:"style,omitempty"`
	Children  []WidgetNode     `json:"children,omitempty"`
}

// Node option kinds. A builder accepts only the options that mean something
// for its node type, so `Columns` on a text node or `MinLen` on a gauge is a
// compile error rather than a key that ships in the payload and is ignored.
// This mirrors the TypeScript SDK, whose option types draw the same lines; the
// Python SDK checks the same rules at call time.
type (
	// ContainerOpt is accepted by VStack, HStack and ZStack.
	ContainerOpt interface{ applyContainer(*WidgetNode) }
	// GridOpt is accepted by Grid: every ContainerOpt, plus Columns.
	GridOpt interface{ applyGrid(*WidgetNode) }
	// LeafOpt is accepted by Text, Image and Sparkline.
	LeafOpt interface{ applyLeaf(*WidgetNode) }
	// GaugeOpt is accepted by Gauge: every LeafOpt, plus GaugeStyle.
	GaugeOpt interface{ applyGauge(*WidgetNode) }
	// ChartOpt is accepted by Chart: every LeafOpt, plus Labels and Colors.
	ChartOpt interface{ applyChart(*WidgetNode) }
	// SpacerOpt is accepted by Spacer: Families, plus MinLen.
	SpacerOpt interface{ applySpacer(*WidgetNode) }
	// DividerOpt is accepted by Divider: Families only.
	DividerOpt interface{ applyDivider(*WidgetNode) }
)

// The concrete option types, each declaring where it is legal.
type (
	anyOpt       func(*WidgetNode) // every node type
	styleOpt     func(*WidgetNode) // everything except Spacer and Divider
	stackOpt     func(*WidgetNode) // containers and Grid
	gridOnlyOpt  func(*WidgetNode) // Grid
	gaugeOnlyOpt func(*WidgetNode) // Gauge
	chartOnlyOpt func(*WidgetNode) // Chart
	spacerOnly   func(*WidgetNode) // Spacer
)

func (f anyOpt) applyContainer(n *WidgetNode) { f(n) }
func (f anyOpt) applyGrid(n *WidgetNode)      { f(n) }
func (f anyOpt) applyLeaf(n *WidgetNode)      { f(n) }
func (f anyOpt) applyGauge(n *WidgetNode)     { f(n) }
func (f anyOpt) applyChart(n *WidgetNode)     { f(n) }
func (f anyOpt) applySpacer(n *WidgetNode)    { f(n) }
func (f anyOpt) applyDivider(n *WidgetNode)   { f(n) }

func (f styleOpt) applyContainer(n *WidgetNode) { f(n) }
func (f styleOpt) applyGrid(n *WidgetNode)      { f(n) }
func (f styleOpt) applyLeaf(n *WidgetNode)      { f(n) }
func (f styleOpt) applyGauge(n *WidgetNode)     { f(n) }
func (f styleOpt) applyChart(n *WidgetNode)     { f(n) }

func (f stackOpt) applyContainer(n *WidgetNode) { f(n) }
func (f stackOpt) applyGrid(n *WidgetNode)      { f(n) }

func (f gridOnlyOpt) applyGrid(n *WidgetNode) { f(n) }

func (f gaugeOnlyOpt) applyGauge(n *WidgetNode) { f(n) }

func (f chartOnlyOpt) applyChart(n *WidgetNode) { f(n) }

func (f spacerOnly) applySpacer(n *WidgetNode) { f(n) }

// Align sets a container's cross-axis alignment.
func Align(s string) stackOpt { return func(n *WidgetNode) { n.Align = &s } }

// Spacing sets a container's inter-child spacing.
func Spacing(f float64) stackOpt { return func(n *WidgetNode) { n.Spacing = &f } }

// Columns sets a grid's column count (default 2; clamped 1…4 by Vee).
func Columns(i int) gridOnlyOpt { return func(n *WidgetNode) { n.Columns = &i } }

// MinLen sets a spacer's minimum length.
func MinLen(f float64) spacerOnly { return func(n *WidgetNode) { n.MinLength = &f } }

// GaugeStyle selects a gauge's style: "linear" (default) or "circular".
func GaugeStyle(s string) gaugeOnlyOpt { return func(n *WidgetNode) { n.GaugeStyle = &s } }

// Labels names a chart's segments, positionally against its values. May be
// shorter than the series; an unnamed segment simply has no legend entry.
func Labels(s ...string) chartOnlyOpt { return func(n *WidgetNode) { n.Labels = s } }

// Colors overrides a chart's segment colors, positionally against its values.
// May be shorter than the series; an unset segment takes its slot in Vee's
// eight-color categorical palette.
func Colors(s ...string) chartOnlyOpt { return func(n *WidgetNode) { n.Colors = s } }

// Families restricts a node to the given widget families (small/medium/large).
func Families(f ...string) anyOpt { return func(n *WidgetNode) { n.Families = f } }

// Style attaches per-element styling to a node.
func Style(s WidgetNodeStyle) styleOpt { return func(n *WidgetNode) { n.Style = &s } }

// nodeBuilders namespaces the layout-node constructors so they read as
// Node.VStack(…) — node-level, distinct from the card-level struct literal.
type nodeBuilders struct{}

// Node is the entry point for the layout-node builders (Node.VStack(…)).
var Node nodeBuilders

// VStack builds a vertical stack.
func (nodeBuilders) VStack(children []WidgetNode, opts ...ContainerOpt) WidgetNode {
	n := WidgetNode{Type: "vstack", Children: children}
	for _, o := range opts {
		o.applyContainer(&n)
	}
	return n
}

// HStack builds a horizontal stack — side-by-side regions.
func (nodeBuilders) HStack(children []WidgetNode, opts ...ContainerOpt) WidgetNode {
	n := WidgetNode{Type: "hstack", Children: children}
	for _, o := range opts {
		o.applyContainer(&n)
	}
	return n
}

// ZStack builds a depth stack — overlays and rings.
func (nodeBuilders) ZStack(children []WidgetNode, opts ...ContainerOpt) WidgetNode {
	n := WidgetNode{Type: "zstack", Children: children}
	for _, o := range opts {
		o.applyContainer(&n)
	}
	return n
}

// Grid builds a grid of Columns (default 2, clamped 1…4).
func (nodeBuilders) Grid(children []WidgetNode, opts ...GridOpt) WidgetNode {
	n := WidgetNode{Type: "grid", Children: children}
	for _, o := range opts {
		o.applyGrid(&n)
	}
	return n
}

// Text builds a text run.
func (nodeBuilders) Text(text string, opts ...LeafOpt) WidgetNode {
	n := WidgetNode{Type: "text", Text: &text}
	for _, o := range opts {
		o.applyLeaf(&n)
	}
	return n
}

// Image builds an SF Symbol glyph (v1 renders SF Symbols only).
func (nodeBuilders) Image(symbol string, opts ...LeafOpt) WidgetNode {
	n := WidgetNode{Type: "image", Symbol: &symbol}
	for _, o := range opts {
		o.applyLeaf(&n)
	}
	return n
}

// Gauge builds a gauge — "linear" (default) or "circular"; value is 0…1.
func (nodeBuilders) Gauge(value float64, opts ...GaugeOpt) WidgetNode {
	n := WidgetNode{Type: "gauge", Value: &value}
	for _, o := range opts {
		o.applyGauge(&n)
	}
	return n
}

// Sparkline builds a dependency-free line chart from values.
func (nodeBuilders) Sparkline(values []float64, opts ...LeafOpt) WidgetNode {
	n := WidgetNode{Type: "sparkline", Values: values}
	for _, o := range opts {
		o.applyLeaf(&n)
	}
	return n
}

// Chart builds a share chart — the same "pie"/"donut"/"stackedbar" a menu row
// draws, from one series of non-negative values read as shares of a whole. A
// series longer than eight segments is folded (not truncated) into a trailing
// "Other".
func (nodeBuilders) Chart(kind string, values []float64, opts ...ChartOpt) WidgetNode {
	n := WidgetNode{Type: "chart", Values: values, Kind: &kind}
	for _, o := range opts {
		o.applyChart(&n)
	}
	return n
}

// Spacer builds flexible empty space.
func (nodeBuilders) Spacer(opts ...SpacerOpt) WidgetNode {
	n := WidgetNode{Type: "spacer"}
	for _, o := range opts {
		o.applySpacer(&n)
	}
	return n
}

// Divider builds a hairline divider.
func (nodeBuilders) Divider(opts ...DividerOpt) WidgetNode {
	n := WidgetNode{Type: "divider"}
	for _, o := range opts {
		o.applyDivider(&n)
	}
	return n
}

// The five template constructors, mirroring the TypeScript and Python SDKs.
// Each presets Template on a card you have already filled in, so the template
// is chosen the same way in all three languages:
//
//	vee.Stat(vee.WidgetCard{Title: vee.Str("Revenue"), Value: vee.Str("$18.2k")}).Print()

// Stat presets the stat template: glyph, big Value in Tint, Title/Caption.
func Stat(c WidgetCard) *WidgetCard { return withTemplate(c, TemplateStat) }

// Gauge presets the gauge template: stat plus a native gauge from Progress.
func Gauge(c WidgetCard) *WidgetCard { return withTemplate(c, TemplateGauge) }

// Trend presets the trend template: stat plus a sparkline from Trend.
func Trend(c WidgetCard) *WidgetCard { return withTemplate(c, TemplateTrend) }

// List presets the list template: Title header plus Items as rows.
func List(c WidgetCard) *WidgetCard { return withTemplate(c, TemplateList) }

// Board presets the board template: a compact grid of Items as stat cells.
func Board(c WidgetCard) *WidgetCard { return withTemplate(c, TemplateBoard) }

func withTemplate(c WidgetCard, t WidgetTemplate) *WidgetCard {
	c.Template = t
	return &c
}

// widgetCardEnvelope prefixes the schema-version field the parser reads for
// forward-compat, then inlines WidgetCard's own fields (Go's encoding/json
// promotes an embedded struct's fields into the same object).
type widgetCardEnvelope struct {
	VeeWidget int `json:"vee_widget"`
	WidgetCard
}

// String renders the card as its JSON payload.
func (c *WidgetCard) String() string {
	return marshalJSON(widgetCardEnvelope{VeeWidget: 1, WidgetCard: *c})
}

// marshalJSON encodes v the way JSON.stringify does, which is the reference
// the three SDKs share.
//
// encoding/json escapes <, > and & as \u003c/\u003e/\u0026 by default -- a
// defence against embedding JSON in HTML that this payload never does -- so a
// card titled "R&D" would go out differently from the TypeScript and Python
// SDKs. Encoder.SetEscapeHTML(false) turns it off; the trailing newline
// Encode appends is trimmed.
func marshalJSON(v any) string {
	var buf strings.Builder
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return "{}"
	}
	return strings.TrimSuffix(buf.String(), "\n")
}

// Print writes String() plus a trailing newline to stdout.
func (c *WidgetCard) Print() {
	fmt.Fprintln(os.Stdout, c.String())
}

// ---------------------------------------------------------------------------
// Structured-JSON output — the optional alternative to the text protocol above.
// A plugin opts in by printing a single `{"vee":1,…}` object; Vee decodes it
// directly, with no line parsing, no `|`-separated parameters and no quoting
// rules. See docs/_content/json-output.md.
//
// JSONMenu deliberately mirrors Menu method for method — Title, Dropdown,
// Item, Separator, Submenu, String, Print — so choosing a wire format does not
// mean learning a second builder.

// JSONOptions are the per-item parameters of a JSON menu item.
//
// The JSON protocol carries a subset of the text protocol's parameters, so
// this is a distinct type rather than Options: a parameter JSON cannot express
// is simply not a field here, rather than one that is silently dropped on the
// way out. Field order is the canonical key order the three SDKs share.
type JSONOptions struct {
	Color    *string  `json:"color,omitempty"`
	Size     *float64 `json:"size,omitempty"`
	Href     *string  `json:"href,omitempty"`
	Shell    *string  `json:"shell,omitempty"`
	Params   []string `json:"params,omitempty"`
	Terminal *bool    `json:"terminal,omitempty"`
	Refresh  *bool    `json:"refresh,omitempty"`
	SFImage  *string  `json:"sfimage,omitempty"`
	Disabled *bool    `json:"disabled,omitempty"`
	Checked  *bool    `json:"checked,omitempty"`
	Tooltip  *string  `json:"tooltip,omitempty"`
	Header   *bool    `json:"header,omitempty"`
	// Accessory is "leading" or "trailing".
	Accessory *string `json:"accessory,omitempty"`
	// VisibleOn lists the surfaces this item exists on; nil means all of them.
	VisibleOn []string `json:"visibleOn,omitempty"`
	// Searchable set to false keeps the item out of every filter query, but
	// still browsable.
	Searchable *bool     `json:"searchable,omitempty"`
	Sparkline  []float64 `json:"sparkline,omitempty"`
	// SparklineWidth is a number of points, or the string "full".
	AccessoryWidth  any      `json:"accessoryWidth,omitempty"`
	AccessoryHeight any      `json:"accessoryHeight,omitempty"`
	SparklineWidth  any      `json:"sparklineWidth,omitempty"`
	SparklineHeight *float64 `json:"sparklineHeight,omitempty"`
	SparklineColor  *string  `json:"sparklineColor,omitempty"`
	Toggle          *bool    `json:"toggle,omitempty"`
	Slider          *Slider  `json:"slider,omitempty"`
	// Progress is a completion fraction, clamped to 0…1 by Vee.
	Progress           *float64 `json:"progress,omitempty"`
	ProgressTrackColor *string  `json:"progressTrackColor,omitempty"`
	// ProgressWidth is a number of points, or the string "full".
	ProgressWidth  any        `json:"progressWidth,omitempty"`
	ProgressHeight *float64   `json:"progressHeight,omitempty"`
	Chart          *JSONChart `json:"chart,omitempty"`
	// Alternate is a row shown while ⌥ is held.
	Alternate *JSONItem `json:"alternate,omitempty"`
}

// JSONChart is the structured-JSON spelling of `pie=`/`donut=`/`stackedbar=`:
// one object rather than three sibling keys, because the shape is a property
// of the same data.
type JSONChart struct {
	// Kind is "pie", "donut", or "stackedbar".
	Kind   string    `json:"kind"`
	Values []float64 `json:"values,omitempty"`
	Labels []string  `json:"labels,omitempty"`
	Colors []string  `json:"colors,omitempty"`
	// W is a number of points, or the string "full".
	W any      `json:"w,omitempty"`
	H *float64 `json:"h,omitempty"`
}

// JSONItem is one item in a JSON menu: JSONOptions plus the structural keys.
type JSONItem struct {
	Text      *string `json:"text,omitempty"`
	Separator *bool   `json:"separator,omitempty"`
	JSONOptions
	Submenu []JSONItem `json:"submenu,omitempty"`
}

// JSONSection is a JSON menu section at a given submenu depth. Mirrors Section.
type JSONSection struct {
	items *[]JSONItem
}

// Item adds a menu item. Pass nil for opts when there are no options.
func (s JSONSection) Item(text string, opts *JSONOptions) JSONSection {
	*s.items = append(*s.items, newJSONItem(text, opts))
	return s
}

// Separator adds a separator row at this depth.
func (s JSONSection) Separator() JSONSection {
	yes := true
	*s.items = append(*s.items, JSONItem{Separator: &yes})
	return s
}

// Submenu adds an item and returns a JSONSection for its submenu.
func (s JSONSection) Submenu(text string, opts *JSONOptions) JSONSection {
	item := newJSONItem(text, opts)
	item.Submenu = []JSONItem{}
	*s.items = append(*s.items, item)
	return JSONSection{items: &(*s.items)[len(*s.items)-1].Submenu}
}

func newJSONItem(text string, opts *JSONOptions) JSONItem {
	item := JSONItem{Text: &text}
	if opts != nil {
		item.JSONOptions = *opts
	}
	return item
}

// JSONMenu is the top-level JSON menu: title line(s) plus a dropdown.
// Mirrors Menu.
type JSONMenu struct {
	titles []JSONItem
	body   []JSONItem
}

// Title adds a menu-bar title line. Call more than once for multiple lines.
func (m *JSONMenu) Title(text string, opts *JSONOptions) *JSONMenu {
	m.titles = append(m.titles, newJSONItem(text, opts))
	return m
}

// Dropdown returns a JSONSection for the dropdown body.
func (m *JSONMenu) Dropdown() JSONSection {
	return JSONSection{items: &m.body}
}

// jsonMenuEnvelope is the wire object: the format version, then the menu.
type jsonMenuEnvelope struct {
	Vee   int        `json:"vee"`
	Title []JSONItem `json:"title"`
	Items []JSONItem `json:"items,omitempty"`
}

// String renders the whole menu as its JSON payload.
func (m *JSONMenu) String() string {
	titles := m.titles
	if titles == nil {
		titles = []JSONItem{}
	}
	return marshalJSON(jsonMenuEnvelope{Vee: 1, Title: titles, Items: m.body})
}

// Print writes String() plus a trailing newline to stdout. This is what a real
// plugin calls.
func (m *JSONMenu) Print() {
	fmt.Fprintln(os.Stdout, m.String())
}
