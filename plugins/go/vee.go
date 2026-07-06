// Package vee is a zero-dependency Go SDK for writing Vee plugins with typed
// builders instead of hand-formatting the xbar/SwiftBar text protocol.
//
// It mirrors the TypeScript and Python SDKs — the same builder shape, option
// names, encoding order, and quoting — so a plugin reads the same in any of the
// three languages and all produce byte-identical output for the same menu.
package vee

import (
	"fmt"
	"os"
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
}

// Str returns a pointer to s, for setting optional string options.
func Str(s string) *string { return &s }

// Int returns a pointer to i, for setting optional int options.
func Int(i int) *int { return &i }

// Bool returns a pointer to b, for setting optional bool options.
func Bool(b bool) *bool { return &b }

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
