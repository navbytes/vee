// Example Vee plugin exercising the typed rich-param builders — sparkline,
// toggle, slider, and progress. Doubles as a golden fixture: its Build() output
// is committed to plugins/go/fixtures/controls.txt and checked for drift by
// controls_test.go. Produces byte-identical output to the TypeScript and Python
// examples — proving cross-language parity.
package main

import (
	"fmt"

	"vee"
)

// Build assembles the menu and returns the rendered text protocol.
func Build() string {
	m := &vee.Menu{}
	m.Title("Controls", &vee.Options{SFImage: vee.Str("slider.horizontal.3")})

	d := m.Dropdown()
	// progress as the single fraction 0.72 (the TS/Python examples compute
	// 72/100 in-SDK), with a track color and explicit size. The tooltip has
	// spaces to prove the shared quote helper flows through the rich-param path.
	d.Item("Disk usage", &vee.Options{
		Color:      vee.Str("green"),
		Progress:   vee.Float(0.72),
		TrackColor: vee.Str("#333333"),
		ProgressW:  vee.Float(80),
		ProgressH:  vee.Float(6),
		Tooltip:    vee.Str("72 GB of 100 GB used"),
	})
	d.Item("Notifications", &vee.Options{Toggle: vee.Bool(true)})
	d.Item("Volume", &vee.Options{Slider: &vee.Slider{Min: 0, Max: 100, Value: 40}})
	d.Item("Load history", &vee.Options{Sparkline: []float64{1, 2, 3, 5, 8, 13}})
	return m.String()
}

func main() {
	fmt.Println(Build())
}
