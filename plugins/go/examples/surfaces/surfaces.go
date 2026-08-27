// The two surface-targeting axes — VisibleOn (where a row exists) and
// Searchable (whether a query can reach it). Byte-identical to the TypeScript
// and Python examples; committed to plugins/fixtures/surfaces.txt.
//
// Using this outside the repository: go get github.com/navbytes/vee/plugins/go
package main

import (
	"fmt"

	vee "github.com/navbytes/vee/plugins/go"
)

// Build renders the example menu.
func Build() string {
	m := &vee.Menu{}
	m.Title("Deploy ✓", &vee.Options{Color: vee.Str("green")})

	d := m.Dropdown()
	d.Item("Open dashboard", &vee.Options{Href: vee.Str("https://deploy.example.com")})
	// Two surfaces named: the row exists on those and nowhere else. Copying to
	// the pasteboard means nothing in a terminal listing.
	d.Item("Copy build ID", &vee.Options{
		Shell:     vee.Str("/usr/bin/pbcopy"),
		Params:    []string{"4210"},
		VisibleOn: []string{"menu", "window"},
	})
	// Browsable, but never a search hit: one Return away is the wrong distance
	// for a destructive action. The ⌥ alternate inherits it from the primary.
	d.Item("Roll back", &vee.Options{
		Shell:      vee.Str("/usr/local/bin/deploy"),
		Params:     []string{"rollback"},
		Searchable: vee.Bool(false),
	})
	d.Item("Roll back (force)", &vee.Options{
		Alternate: vee.Bool(true),
		Shell:     vee.Str("/usr/local/bin/deploy"),
		Params:    []string{"rollback", "--force"},
	})
	d.Separator()
	// Hiding takes the subtree with it: both children go wherever the parent does.
	logs := d.Submenu("Logs", &vee.Options{VisibleOn: []string{"window", "cli"}})
	logs.Item("Build log", &vee.Options{Href: vee.Str("https://deploy.example.com/4210/log")})
	logs.Item("Test log", &vee.Options{Href: vee.Str("https://deploy.example.com/4210/tests")})
	return m.String()
}

func main() {
	fmt.Println(Build())
}
