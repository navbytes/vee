#!/usr/bin/env python3
"""Render the reliability soak CSV into a self-contained SVG line chart.

Reads the `elapsed_s,rss_mb,cpu_pct` time-series emitted by the soak benchmark
(`VEE_SOAK_SAMPLES_PATH`, see Tests/VeeRuntimeTests/MemorySoakBenchmarkTests.swift)
and writes a themed SVG plotting resident memory and CPU over the run — the
visual proof of the "no memory creep / no refresh-death" reliability moat.

Pure standard library (no third-party deps, matching the project policy).

    python3 docs/scripts/soak_chart.py <samples.csv> <out.svg>

Also prints headline stats (peak/median RSS, growth, sample count) to stdout so
they can be quoted in the landing-page copy.
"""
import sys
import csv
import statistics

# Site palette (docs/assets/style.css :root) — the page is dark-themed.
INK = "#eef1fb"
INK_SOFT = "#b7bfd6"
INK_MUTE = "#7b839d"
HAIR = "rgba(255,255,255,0.09)"
ACCENT_1 = "#5b5be6"
ACCENT_2 = "#2f6bfb"
GREEN = "#38cf74"

W, H = 760, 380
PAD_L, PAD_R, PAD_T, PAD_B = 60, 58, 46, 48
PLOT_W = W - PAD_L - PAD_R
PLOT_H = H - PAD_T - PAD_B


def read_samples(path):
    rows = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            rows.append((float(r["elapsed_s"]), float(r["rss_mb"]), float(r["cpu_pct"])))
    return rows


def downsample(rows, buckets=140):
    """Bucket by elapsed time and average, so a dense run renders as a clean line."""
    if len(rows) <= buckets:
        return rows
    t0, t1 = rows[0][0], rows[-1][0]
    span = (t1 - t0) or 1.0
    acc = {}
    for e, rss, cpu in rows:
        b = min(buckets - 1, int((e - t0) / span * buckets))
        acc.setdefault(b, []).append((e, rss, cpu))
    out = []
    for b in sorted(acc):
        pts = acc[b]
        out.append((
            statistics.mean(p[0] for p in pts),
            statistics.mean(p[1] for p in pts),
            statistics.mean(p[2] for p in pts),
        ))
    return out


def nice_ceiling(v, minimum):
    v = max(v, minimum)
    for step in (5, 10, 20, 25, 50, 100, 200, 250, 500, 1000):
        if v <= step:
            return step
    return (int(v / 1000) + 1) * 1000


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def build_svg(rows):
    t0, t1 = rows[0][0], rows[-1][0]
    span = (t1 - t0) or 1.0
    rss_max = nice_ceiling(max(r[1] for r in rows) * 1.25, 20)
    cpu_max = nice_ceiling(max(r[2] for r in rows) * 1.3, 10)

    def x(e):
        return PAD_L + (e - t0) / span * PLOT_W

    def y_rss(v):
        return PAD_T + PLOT_H - (v / rss_max) * PLOT_H

    def y_cpu(v):
        return PAD_T + PLOT_H - (v / cpu_max) * PLOT_H

    parts = [
        f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" '
        f'font-family="ui-sans-serif,-apple-system,Segoe UI,Roboto,sans-serif" '
        f'role="img" aria-label="Resident memory stays flat and CPU stays low across a continuous soak run.">',
        f'<defs><linearGradient id="rssfill" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{ACCENT_2}" stop-opacity="0.28"/>'
        f'<stop offset="1" stop-color="{ACCENT_2}" stop-opacity="0.02"/></linearGradient>'
        f'<linearGradient id="rssline" x1="0" y1="0" x2="1" y2="0">'
        f'<stop offset="0" stop-color="{ACCENT_1}"/><stop offset="1" stop-color="{ACCENT_2}"/></linearGradient></defs>',
    ]

    # Horizontal grid + left (RSS) axis labels.
    for i in range(5):
        gy = PAD_T + PLOT_H * i / 4
        val = rss_max * (4 - i) / 4
        parts.append(f'<line x1="{PAD_L}" y1="{gy:.1f}" x2="{PAD_L+PLOT_W}" y2="{gy:.1f}" stroke="{HAIR}" stroke-width="1"/>')
        parts.append(f'<text x="{PAD_L-10}" y="{gy+4:.1f}" text-anchor="end" font-size="11" fill="{INK_MUTE}">{val:.0f}</text>')
        parts.append(f'<text x="{PAD_L+PLOT_W+10}" y="{gy+4:.1f}" text-anchor="start" font-size="11" fill="{INK_MUTE}">{cpu_max*(4-i)/4:.0f}%</text>')

    # X axis labels (minutes).
    for i in range(5):
        gx = PAD_L + PLOT_W * i / 4
        mins = (t0 + span * i / 4) / 60
        parts.append(f'<text x="{gx:.1f}" y="{PAD_T+PLOT_H+22:.1f}" text-anchor="middle" font-size="11" fill="{INK_MUTE}">{mins:.0f}m</text>')

    # CPU line (behind RSS).
    cpu_pts = " ".join(f"{x(e):.1f},{y_cpu(cpu):.1f}" for e, _, cpu in rows)
    parts.append(f'<polyline points="{cpu_pts}" fill="none" stroke="{GREEN}" stroke-width="1.6" stroke-opacity="0.85" stroke-linejoin="round"/>')

    # RSS area + line.
    rss_line = " ".join(f"{x(e):.1f},{y_rss(rss):.1f}" for e, rss, _ in rows)
    area = f"{PAD_L},{PAD_T+PLOT_H} " + rss_line + f" {PAD_L+PLOT_W},{PAD_T+PLOT_H}"
    parts.append(f'<polygon points="{area}" fill="url(#rssfill)"/>')
    parts.append(f'<polyline points="{rss_line}" fill="none" stroke="url(#rssline)" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/>')

    # Axis titles + legend.
    parts.append(f'<text x="{PAD_L}" y="24" font-size="13" font-weight="600" fill="{INK}">Resident memory (MB)</text>')
    parts.append(f'<text x="{W-PAD_R}" y="24" text-anchor="end" font-size="13" font-weight="600" fill="{GREEN}">CPU (%)</text>')
    return "\n".join(parts) + "\n</svg>\n"


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    rows = read_samples(sys.argv[1])
    if len(rows) < 8:
        print(f"too few samples ({len(rows)})", file=sys.stderr)
        sys.exit(1)

    q = max(1, len(rows) // 4)
    rss_all = [r[1] for r in rows]
    base = statistics.median(rss_all[:q])
    tail = statistics.median(rss_all[-q:])
    stats = {
        "samples": len(rows),
        "duration_min": rows[-1][0] / 60,
        "rss_median_mb": statistics.median(rss_all),
        "rss_peak_mb": max(rss_all),
        "rss_growth_mb": tail - base,
        "cpu_median_pct": statistics.median(r[2] for r in rows),
    }

    with open(sys.argv[2], "w") as f:
        f.write(build_svg(downsample(rows)))

    for k, v in stats.items():
        print(f"{k}={v:.2f}" if isinstance(v, float) else f"{k}={v}")


if __name__ == "__main__":
    main()
