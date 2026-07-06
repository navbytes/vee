// Example Vee plugin built with the Go SDK. Doubles as a golden fixture: its
// Build() output is committed to plugins/go/fixtures/cpu.txt and checked for
// drift by cpu_test.go. Produces byte-identical output to the TypeScript and
// Python examples — proving cross-language parity.
package main

import (
	"fmt"

	"vee"
)

// Build assembles the menu and returns the rendered text protocol.
func Build() string {
	m := &vee.Menu{}
	m.Title("CPU 12%", &vee.Options{Color: vee.Str("green"), SFImage: vee.Str("cpu")})

	d := m.Dropdown()
	d.Item("Top processes", &vee.Options{Href: vee.Str("https://example.com/procs")})
	d.Separator()

	details := d.Submenu("Details", nil)
	details.Item("Load: 1.20", nil)
	details.Item("Cores: 8", nil)

	d.Item("Refresh", &vee.Options{Refresh: vee.Bool(true)})
	return m.String()
}

func main() {
	fmt.Println(Build())
}
