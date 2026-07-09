// Drift guard: the example's Build() output must match its committed golden
// fixture, which is byte-identical to the TypeScript/Python SDKs' — keeping
// every SDK, the shared fixture, and the Swift WidgetCardParser in lockstep.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFixtureUpToDate(t *testing.T) {
	name := "widget-layout"
	fixture := filepath.Join("..", "..", "fixtures", name+".txt")
	raw, err := os.ReadFile(fixture)
	if err != nil {
		t.Fatalf("read fixture %s: %v", fixture, err)
	}
	expected := strings.TrimRight(string(raw), "\n")
	got := Build()
	if got != expected {
		t.Errorf("Build() drifted from fixtures/%s.txt.\nRegenerate with: "+
			"go run ./examples/%s > fixtures/%s.txt\n--- got ---\n%s\n--- want ---\n%s",
			name, name, name, got, expected)
	}
}
