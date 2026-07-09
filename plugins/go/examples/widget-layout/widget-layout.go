// Example Vee plugin using the widget-card layout tree: the composable escape
// hatch alongside the five preset templates (see the design doc §"Layout tree").
// Builds a CPU tile as a tree — a header row, a big monospaced value that scales
// to fit, and a circular gauge. Doubles as a golden fixture, byte-identical to
// the TypeScript/Python widget-layout examples.
package main

import (
	"fmt"

	"vee"
)

// Build assembles the widget card and returns its JSON payload.
func Build() string {
	layout := vee.Node.VStack(
		[]vee.WidgetNode{
			vee.Node.HStack([]vee.WidgetNode{
				vee.Node.Image("cpu", vee.Style(vee.WidgetNodeStyle{Tint: vee.Str("blue")})),
				vee.Node.Text("CPU", vee.Style(vee.WidgetNodeStyle{
					Font: &vee.WidgetNodeFont{Size: vee.Str("caption"), Weight: vee.Str("semibold")},
					Tint: vee.Str("secondary"),
				})),
				vee.Node.Spacer(),
			}, vee.Spacing(5)),
			vee.Node.Text("38%", vee.Style(vee.WidgetNodeStyle{
				Font:            &vee.WidgetNodeFont{Size: vee.Str("title"), Design: vee.Str("rounded")},
				Tint:            vee.Str("green"),
				MonospacedDigit: vee.Bool(true),
				MinScale:        vee.Float(0.6),
			})),
			vee.Node.Gauge(0.38, vee.GaugeStyle("circular"), vee.Style(vee.WidgetNodeStyle{Tint: vee.Str("green")})),
		},
		vee.Align("leading"), vee.Spacing(6),
	)

	c := &vee.WidgetCard{Layout: &layout}
	return c.String()
}

func main() {
	fmt.Println(Build())
}
