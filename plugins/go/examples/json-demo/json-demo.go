// The structured-JSON protocol, built with JSONMenu. Byte-identical to the
// TypeScript and Python examples; committed to plugins/fixtures/json-demo.txt.
//
// Using this outside the repository: go get github.com/navbytes/vee/plugins/go
package main

import (
	"fmt"

	vee "github.com/navbytes/vee/plugins/go"
)

// Build renders the example menu.
func Build() string {
	m := &vee.JSONMenu{}
	m.Title("JSON ✓", &vee.JSONOptions{Color: vee.Str("green"), SFImage: vee.Str("curlybraces")})

	d := m.Dropdown()
	// Surface targeting, in its JSON spelling: the same two axes the text
	// protocol writes as `visibleon=`/`searchable=` (see the surfaces example).
	d.Item("Structured item", &vee.JSONOptions{
		Href:       vee.Str("https://example.com"),
		VisibleOn:  []string{"menu", "window"},
		Searchable: vee.Bool(false),
	})
	d.Separator()
	d.Submenu("Submenu", nil).Item("Child", &vee.JSONOptions{Color: vee.Str("blue")})
	// See the TypeScript example: characters the three JSON encoders disagree
	// about by default.
	d.Item("R&D <beta> ✓", &vee.JSONOptions{Tooltip: vee.Str("a & b")})
	return m.String()
}

func main() {
	fmt.Println(Build())
}
