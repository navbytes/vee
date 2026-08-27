// Example Vee plugin using the widget-card SDK: the rich, structured
// VEE_TARGET=widget stdout payload described in
// docs/design/widget-surface-contract.md §4. Doubles as a golden fixture,
// byte-identical to the TypeScript/Python widget-card examples — proving
// cross-language parity for the card schema too.
//
// Using this outside the repository: go get github.com/navbytes/vee/plugins/go
package main

import (
	"fmt"

	vee "github.com/navbytes/vee/plugins/go"
)

// Build assembles the widget card and returns its JSON payload.
func Build() string {
	c := &vee.WidgetCard{
		Template: vee.TemplateStat,
		Title:    vee.Str("Revenue"),
		Symbol:   vee.Str("chart.line.uptrend.xyaxis"),
		Tint:     vee.Str("green"),
		Value:    vee.Str("$18.2k"),
		Caption:  vee.Str("today"),
		Detail:   vee.Str("214 orders"),
		Status:   vee.StatusOK,
		Progress: vee.Float(0.72),
		Trend:    []float64{12.1, 13.4, 12.9, 15.0, 18.2},
		// The two tap targets a row can carry: a URL the system opens, and a
		// Shortcut Vee runs. A row declaring neither stays inert.
		Items: []vee.WidgetCardItem{
			{Label: "Orders", Value: vee.Str("214"), Symbol: vee.Str("bag"), Tint: vee.Str("blue"),
				URL: vee.Str("https://dash.example.com/orders")},
			{Label: "Refunds", Value: vee.Str("3"), Symbol: vee.Str("arrow.uturn.left"), Tint: vee.Str("red"),
				Shortcut: vee.Str("Review Refunds")},
		},
		Actions: []vee.WidgetCardAction{
			{Kind: vee.ActionRefresh, Label: "Refresh"},
			{Kind: vee.ActionHref, Label: "Open", URL: vee.Str("https://dash.example.com")},
		},
		RefreshAfter: vee.Float(900),
		StaleAfter:   vee.Float(3600),
	}
	return c.String()
}

func main() {
	fmt.Println(Build())
}
