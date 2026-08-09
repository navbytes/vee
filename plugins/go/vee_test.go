// Regression: a literal `|`/newline/backslash in plugin-supplied text must
// survive Vee's parser instead of truncating or corrupting the item — see
// Sources/VeePluginFormat/LineParser.swift (splitTextAndParams/parseParams's
// unescape) for the parser half of this `\|`/`\n`/`\\` contract; escapeText/
// quote in vee.go are the SDK half. The TypeScript and Python SDKs mirror this
// file exactly (same original text, same expected escaped line).
package vee

import (
	"strings"
	"testing"
)

// unescape mirrors LineParser's unescape: the parser's inverse of escapeText.
func unescape(s string) string {
	var out strings.Builder
	runes := []rune(s)
	for i := 0; i < len(runes); i++ {
		if runes[i] == '\\' && i+1 < len(runes) && strings.ContainsRune("|n\\", runes[i+1]) {
			if runes[i+1] == 'n' {
				out.WriteRune('\n')
			} else {
				out.WriteRune(runes[i+1])
			}
			i++
			continue
		}
		out.WriteRune(runes[i])
	}
	return out.String()
}

func TestItemTextWithPipeAndNewlineEmitsSDKParserContract(t *testing.T) {
	m := &Menu{}
	m.Title("T", nil)
	m.Dropdown().Item("Left | Right\nSecond line", &Options{Color: Str("red")})

	// Splitting on "\n" must yield exactly 3 lines: a raw newline byte in the
	// item would otherwise be read by OutputParser as a 4th, corrupted line.
	got := strings.Split(m.String(), "\n")
	want := []string{"T", "---", `Left \| Right\nSecond line | color=red`}
	if len(got) != len(want) {
		t.Fatalf("String() lines = %q, want %q", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("line %d = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestTitleTextIsEscapedTheSameWayAsItemText(t *testing.T) {
	m := &Menu{}
	m.Title("A | B\nC", nil)
	if got, want := m.String(), `A \| B\nC`; got != want {
		t.Errorf("String() = %q, want %q", got, want)
	}
}

func TestLiteralBackslashInParamValueIsEscapedQuotedAndRoundTrips(t *testing.T) {
	path := `C:\Users\me` // one literal backslash between each segment
	m := &Menu{}
	m.Title("T", nil)
	m.Dropdown().Item("plain", &Options{Tooltip: Str(path)})

	lines := strings.Split(m.String(), "\n")
	line := lines[len(lines)-1]
	if !strings.HasPrefix(line, `plain | tooltip="`) {
		t.Fatalf("line = %q, want prefix %q", line, `plain | tooltip="`)
	}
	first := strings.Index(line, `"`)
	last := strings.LastIndex(line, `"`)
	quotedValue := line[first+1 : last]
	if got := unescape(quotedValue); got != path {
		t.Errorf("unescape(%q) = %q, want %q", quotedValue, got, path)
	}
}

func TestValuesNeedingNoEscapingStayUnquoted(t *testing.T) {
	m := &Menu{}
	m.Title("T", nil)
	m.Dropdown().Item("plain", &Options{Color: Str("red")})

	lines := strings.Split(m.String(), "\n")
	if got, want := lines[len(lines)-1], "plain | color=red"; got != want {
		t.Errorf("last line = %q, want %q", got, want)
	}
}
