// Encoder edge cases, as a golden fixture. See plugins/typescript/examples/
// edges.ts for what each line pins down; this file must produce byte-identical
// output. Committed to plugins/fixtures/edges.txt.
package main

import (
	"fmt"

	"vee"
)

// Build renders the example menu.
func Build() string {
	m := &vee.Menu{}
	m.Title("Edges", nil)

	d := m.Dropdown()
	d.Item("large", &vee.Options{Sparkline: []float64{1000000, 1234567, 999999, 12000000}})
	d.Item("boundaries", &vee.Options{Sparkline: []float64{1e-7, 0.000001, 1e20, 1e21}})
	d.Item("signs", &vee.Options{Sparkline: []float64{-0.0, -1.5, 0.30000000000000004}})
	d.Item("nbsp", &vee.Options{Tooltip: vee.Str("a b")})
	d.Item("leading-double", &vee.Options{Tooltip: vee.Str(`"quoted"`)})
	d.Item("leading-single", &vee.Options{Tooltip: vee.Str("'tis")})
	d.Item("inner-quote", &vee.Options{Tooltip: vee.Str(`has"inside`)})
	d.Item("reserved", &vee.Options{Tooltip: vee.Str(`a|b\c`)})
	return m.String()
}

func main() {
	fmt.Println(Build())
}
