// Drift guard: the example's Build() output must match its committed golden
// fixture. The fixtures are byte-identical to the TypeScript and Python SDKs',
// so this keeps every SDK, the shared fixtures, and the Swift parser in
// lockstep.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFixtureUpToDate(t *testing.T) {
	name := "controls"
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
