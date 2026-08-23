// Example Vee plugin exercising the typed rich-param builders — sparkline,
// toggle, slider, and progress. Doubles as a golden fixture: its Build() output
// is committed to plugins/fixtures/controls.txt and checked for drift by
// controls_test.go. Produces byte-identical output to the TypeScript and Python
// examples — proving cross-language parity.
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
	m.Title("Controls", &vee.Options{SFImage: vee.Str("slider.horizontal.3")})

	d := m.Dropdown()
	// progress as the format's two-argument form `progress=72,100`, which Vee
	// divides on parse, with a track color and explicit size. The tooltip has
	// spaces to prove the shared quote helper flows through the rich-param path.
	d.Item("Disk usage", &vee.Options{
		Color:              vee.Str("green"),
		ProgressValue:      vee.Float(72),
		ProgressMax:        vee.Float(100),
		ProgressTrackColor: vee.Str("#333333"),
		ProgressW:          vee.Float(80),
		ProgressH:          vee.Float(6),
		Tooltip:            vee.Str("72 GB of 100 GB used"),
	})
	d.Item("Notifications", &vee.Options{Toggle: vee.Bool(true)})
	// AccessoryW sizes whichever accessory a row carries -- here the slider
	// track, which had no size of its own before.
	d.Item("Volume", &vee.Options{Slider: &vee.Slider{Min: 0, Max: 100, Value: 40}, AccessoryW: vee.Float(120)})
	// The sparkline takes the same size/colour vocabulary as progress= and the
	// chart shapes: <Control>W / <Control>H / <Control>Color.
	d.Item("Load history", &vee.Options{
		Sparkline:      []float64{1, 2, 3, 5, 8, 13},
		SparklineW:     vee.Float(120),
		SparklineH:     vee.Float(18),
		SparklineColor: vee.Str("teal"),
	})
	return m.String()
}

func main() {
	fmt.Println(Build())
}
