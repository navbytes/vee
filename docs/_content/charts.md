# Charts

Vee draws six kinds of chart, and a plugin reaches them through three different
output formats. This page is the index: what exists, how to emit it, and what
each one takes. The prose that explains any given chart lives with its surface —
[Plugin authoring](plugin-authoring.md) for the menu bar, [Widgets](widgets.md)
for the desktop — and each row below links into it.

Every chart is drawn natively. There is no WebView anywhere in Vee, and no
charting library: an inline chart is an AppKit or SwiftUI row view, a popover is
Swift Charts, and a widget is WidgetKit.

## The matrix

<!-- include: _generated/chart-matrix.md -->

## Where a chart appears

A menu-bar chart occupies the row's **accessory slot** — the same slot for all
of them, which is why a row draws one chart and not three. When a line carries
more than one, the last one wins in the order `progress=` → `sparkline=` →
share chart. `accessory=leading` moves it to the other edge of the row.

Most of them are also clickable. A sparkline or a share chart opens a Liquid
Glass popover with the same data at full size — the legend that `chartlabels=`
feeds is only visible there, since a menu row has no room for it. A progress bar
has no popover: the bar already shows everything it has.

## Sizing

Each chart is sized by knobs named after itself:

| Chart | Width | Height | Stretch to the row |
| ----- | ----- | ------ | ------------------ |
| Sparkline | `sparklinew=` | `sparklineh=` | `sparklinew=full` |
| Progress bar | `progressw=` | `progressh=` | `progressw=full` |
| Pie, donut | `chartw=` or `charth=` — either sizes both | | not supported |
| Stacked bar | `chartw=` | `charth=` | `chartw=full` |

`full` stretches a chart to the width the row actually has, rather than a fixed
number of points. It exists because a menu is as wide as its widest row, so a
fixed width cannot fill a menu whose width some *other* row decides. It applies
only to charts with free width: a pie and a donut are circles, whose width *is*
their diameter, so stretching one would make the row as tall as the menu is
wide. Vee refuses it there and says so in a diagnostic rather than guessing.

## Choosing one

- A value **over time** — load average, request rate, temperature — is a
  sparkline.
- A single value **against a maximum** — disk used, battery, quota — is a
  progress bar, or a gauge in a widget.
- A total that **divides into categories** — disk by folder, spend by
  department — is a share chart. Pie, donut, and stacked bar read the same
  numbers and differ only in shape, so switching between them needs no change
  to the values, labels, or colors.

Share charts carry at most eight segments, because the categorical palette has
eight slots and a ninth would have to reuse a hue — exactly the ambiguity a
share chart must not have. A longer series is **folded, not truncated**: the
leading segments are kept and the rest are summed into a final `Other`, so the
shares still add up to the plugin's own total.

## Colors

A share chart's segments take a fixed eight-slot categorical palette, assigned
in order and never cycled — slot *n* always means "the nth segment", so a series
that shrinks does not repaint the segments that survived. Each slot is a
light/dark pair chosen against its own mode's background rather than one color
flipped, and the set is validated for colorblind separation including the
first-to-last pair, which a pie makes adjacent by wrapping around.

`chartcolors=` overrides it positionally, and a blank or unrecognised entry
keeps that segment's palette slot rather than shifting every later color left —
so `chartcolors=,,red` recolors only the third segment.

Color is never the only channel: every chart carries an accessibility summary
reading its segments and their shares aloud, so the data survives for a reader
who cannot see the difference.

## See also

- [Plugin authoring](plugin-authoring.md#rich-inline-charts-liquid-glass-popovers)
  — the menu-bar charts in full, with worked examples.
- [Widgets](widgets.md) — the gauge and sparkline layout nodes, and the `trend`
  and `gauge` templates.
- [JSON output](json-output.md) — the structured spelling of every chart.
- [Plugin SDKs](sdk.md) — emitting charts from TypeScript, Python, or Go.
