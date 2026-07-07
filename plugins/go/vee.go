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
	"os"
	"strconv"
	"strings"
)

// Options are the per-item parameters. Pointer fields are optional: a nil
// pointer is omitted, matching the TS SDK's `undefined`. Use the helpers
// (Str, Int, Bool) to set them concisely.
type Options struct {
	Color     *string
	Size      *int
	Font      *string
	Length    *int
	Href      *string
	Shell     *string
	Params    []string
	Terminal  *bool
	Refresh   *bool
	Alternate *bool
	Disabled  *bool
	Checked   *bool
	Key       *string
	Tooltip   *string
	SFImage   *string
	MD        *bool
	Badge     *string
	Symbolize *bool

	// Vee-native rich params, emitted last in a fixed order shared across SDKs.
	Sparkline  []float64
	Toggle     *bool
	Slider     *Slider
	Progress   *float64
	TrackColor *string
	ProgressW  *float64
	ProgressH  *float64
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

// fmtFloat formats a float like JS String(): whole values without a trailing
// ".0", shortest round-trippable representation otherwise.
func fmtFloat(f float64) string {
	return strconv.FormatFloat(f, 'g', -1, 64)
}

func quote(value string) string {
	if strings.ContainsAny(value, " \t\n|") {
		return `"` + strings.ReplaceAll(value, `"`, `\"`) + `"`
	}
	return value
}

func encode(o *Options) string {
	if o == nil {
		return ""
	}
	var parts []string
	push := func(key, value string) { parts = append(parts, key+"="+quote(value)) }

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
	if o.Href != nil {
		push("href", *o.Href)
	}
	if o.Shell != nil {
		push("shell", *o.Shell)
		for i, p := range o.Params {
			push(fmt.Sprintf("param%d", i+1), p)
		}
	}
	pushBool := func(key string, v *bool) {
		if v != nil {
			if *v {
				push(key, "true")
			} else {
				push(key, "false")
			}
		}
	}
	pushBool("terminal", o.Terminal)
	pushBool("refresh", o.Refresh)
	pushBool("alternate", o.Alternate)
	pushBool("disabled", o.Disabled)
	pushBool("checked", o.Checked)
	if o.Key != nil {
		push("key", *o.Key)
	}
	if o.Tooltip != nil {
		push("tooltip", *o.Tooltip)
	}
	if o.SFImage != nil {
		push("sfimage", *o.SFImage)
	}
	pushBool("md", o.MD)
	if o.Badge != nil {
		push("badge", *o.Badge)
	}
	pushBool("symbolize", o.Symbolize)

	if o.Sparkline != nil {
		nums := make([]string, len(o.Sparkline))
		for i, v := range o.Sparkline {
			nums[i] = fmtFloat(v)
		}
		push("sparkline", strings.Join(nums, ","))
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
	if o.Progress != nil {
		push("progress", fmtFloat(*o.Progress))
	}
	if o.TrackColor != nil {
		push("trackcolor", *o.TrackColor)
	}
	if o.ProgressW != nil {
		push("progressw", fmtFloat(*o.ProgressW))
	}
	if o.ProgressH != nil {
		push("progressh", fmtFloat(*o.ProgressH))
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
	*s.lines = append(*s.lines, s.prefix()+text+encode(opts))
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
	m.titles = append(m.titles, text+encode(opts))
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

// WidgetCardItem is one row for the list/board templates.
type WidgetCardItem struct {
	Label  string  `json:"label"`
	Value  *string `json:"value,omitempty"`
	Symbol *string `json:"symbol,omitempty"`
	Tint   *string `json:"tint,omitempty"`
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
	data, err := json.Marshal(widgetCardEnvelope{VeeWidget: 1, WidgetCard: *c})
	if err != nil {
		return "{}"
	}
	return string(data)
}

// Print writes String() plus a trailing newline to stdout.
func (c *WidgetCard) Print() {
	fmt.Fprintln(os.Stdout, c.String())
}
