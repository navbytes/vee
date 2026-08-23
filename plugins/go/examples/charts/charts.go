// Example Vee plugin exercising the categorical share charts — pie, donut, and
// stacked bar. Doubles as a golden fixture: its Build() output is committed to
// plugins/fixtures/charts.txt and checked for drift by charts_test.go.
// Produces byte-identical output to the TypeScript and Python examples —
// proving cross-language parity.
//
// Using this outside the repository: go get github.com/navbytes/vee/plugins/go
package main

import (
	"fmt"

	vee "github.com/navbytes/vee/plugins/go"
)

// Build assembles the menu and returns the rendered text protocol.
func Build() string {
	m := &vee.Menu{}
	m.Title("Disk", &vee.Options{SFImage: vee.Str("chart.pie")})

	d := m.Dropdown()
	// The same three shapes over the same kind of data: switching Kind is the
	// only difference between them.
	d.Item("By category", &vee.Options{
		Chart: &vee.Chart{
			Kind:   "pie",
			Values: []float64{45, 30, 25},
			Labels: []string{"Documents", "Photos", "Apps"},
		},
	})
	// Named colors override the default palette, positionally.
	d.Item("By volume", &vee.Options{
		Chart: &vee.Chart{
			Kind:   "donut",
			Values: []float64{512, 256, 128},
			Labels: []string{"Macintosh HD", "Backup", "Scratch"},
			Colors: []string{"blue", "teal", "orange"},
		},
		Tooltip: vee.Str("896 GB across 3 volumes"),
	})
	d.Item("Budget", &vee.Options{
		Chart: &vee.Chart{
			Kind:   "stackedbar",
			Values: []float64{60, 25, 15},
			Labels: []string{"Used", "Cache", "Free"},
		},
	})
	return m.String()
}

func main() {
	fmt.Println(Build())
}
