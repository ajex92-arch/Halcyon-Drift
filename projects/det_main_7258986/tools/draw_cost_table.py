"""Turns the hull gallery's parts bench output into one markdown table.

WHAT THIS IS: the table maker for the parts bench (tests/hull_gallery.gd
--bench --bench-parts). The bench measures a crowd of ships and minions once
per switch set of DrawParts: every part drawn, each part left out alone, the
six drawn parts left out together, all parts left out, and an empty scene
(every unit hidden). This script reads the log lines it prints and says, part
by part, how many milliseconds per frame and how many draw calls that part
costs, and what share of the total that is.

HOW IT WORKS: every measurement is one log line:
    DRAWCOST scenario=busy view=4500 round=2 look=cinder_alien off=flames
        units=280 frame_ms=31.2 p95_ms=33.4 script_ms=9.1 render_ms=14.0
        process_ms=12.3 draw_calls=4100
(on one line). frame_ms is the whole frame. script_ms is the game's own work
(every _process and _draw call, where the ships' drawing code runs); render_ms
is Godot's drawing of the frame; the rest of the frame is waiting, mostly for
the graphics card. Round 0 is a warm-up and is skipped. For each scenario, view
and look the script averages each switch set over its rounds, then:
    saved = (all parts drawn) - (that part left out alone)
    share = saved / (all parts drawn)
A part whose frame saving is smaller than the spread of the all-parts-drawn
rounds is marked "~" (within noise). Parts overlap a little, so they need not
add up to the "all parts left out" row; the table shows the difference.

HOW TO RUN IT (from the remake folder, Python only, nothing to install):
    python -B -I tools/draw_cost_table.py LOG [LOG ...] [-o table.md]
With no -o the table is printed. Exit code 0 when it found measurements, 2 when
the logs hold no DRAWCOST line. `--selftest` checks the script on made-up lines.

WHO USES IT: the lead's measure_quiet.ps1 (Monday's official run) and anyone
who ran the parts bench by hand. Nothing in the game reads it.
"""
import argparse
import re
import sys

# The parts, in the order the bench lists them (DrawParts.PARTS), and the
# names of the two special sets: "none" = all parts drawn, "all" = all left out.
PARTS = ["flames", "arcs", "arrow", "bars", "name", "outline", "redraw"]
BASE = "none"
FLOOR = "all"
# The set with the six drawn parts left out and the every-frame redraw kept.
DRAWING = "drawing"
# The set with every unit hidden: what the rest of the scene costs by itself.
EMPTY = "empty"

# How a part is described under the table, in plain words.
PART_NOTES = {
    "flames": "3 flame emitters per ship (still made, but stopped and hidden). Costs something only when ships burn their engines (busy crowd).",
    "arcs": "the 4 shield arcs round a ship",
    "arrow": "the drift arrow and its slip tick. Drawn only on the human's own ship while it moves, so the bench's crowd of AI ships draws none.",
    "bars": "the hull and shield bars. Drawn only for a view narrower than about 4,340 world units (always for the human's ship); a minion's bar only once it is hurt.",
    "name": "the name tag. Drawn only for a view narrower than about 2,890 world units (always for the human's ship).",
    "outline": "the line round every hull (the fill stays)",
    "redraw": "drawing again every frame. CPU only: Godot replays the kept picture, so the draw calls stay. It includes the script cost of every other part (a picture that is not redrawn draws none of them), so this row is NOT additive with the others.",
}

# The looks the bench measures, as the log prints them, and their titles.
LOOK_TITLES = {
    "aurelian_only": "Aurelian only (140 units)",
    "cinder_alien": "both teams, Cinder alien (280 units)",
    "cinder_plain": "both teams, Cinder plain (280 units)",
}

LINE_RE = re.compile(r"DRAWCOST\s+(.*)$")
PAIR_RE = re.compile(r"(\w+)=(\S+)")
HEAD_RE = re.compile(r"bench-parts:\s+scenario=(\w+)\s+(.*)$")


def parse(paths):
    """Read the logs: returns (cells, heads). cells[(scenario, view, look)][off]
    is a list of measurements (dicts with floats); heads holds the bench's
    header lines (size, rounds, frames) by scenario."""
    cells = {}
    heads = {}
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                line = raw.strip()
                h = HEAD_RE.search(line)
                if h:
                    heads[h.group(1)] = dict(PAIR_RE.findall(h.group(2)))
                    continue
                m = LINE_RE.search(line)
                if not m:
                    continue
                kv = dict(PAIR_RE.findall(m.group(1)))
                try:
                    rnd = int(kv["round"])
                    rec = {
                        "round": rnd,
                        "units": int(kv.get("units", "0")),
                        "frame": float(kv["frame_ms"]),
                        "p95": float(kv["p95_ms"]),
                        "script": float(kv.get("script_ms", "nan")),
                        "render": float(kv.get("render_ms", "nan")),
                        "process": float(kv["process_ms"]),
                        "calls": float(kv["draw_calls"]),
                    }
                    key = (kv["scenario"], int(kv["view"]), kv["look"])
                    off = kv["off"]
                except (KeyError, ValueError):
                    continue
                if rnd <= 0:
                    continue  # the warm-up round
                cells.setdefault(key, {}).setdefault(off, []).append(rec)
    return cells, heads


def mean(values):
    """The average of a non-empty list."""
    return sum(values) / len(values)


def summarize(recs):
    """The average of each field over the rounds, plus the spread of the frame
    time (largest minus smallest)."""
    frames = [r["frame"] for r in recs]
    return {
        "n": len(recs),
        "units": recs[0]["units"],
        "frame": mean(frames),
        "p95": mean([r["p95"] for r in recs]),
        "script": mean([r["script"] for r in recs]),
        "render": mean([r["render"] for r in recs]),
        "process": mean([r["process"] for r in recs]),
        "calls": mean([r["calls"] for r in recs]),
        "spread": max(frames) - min(frames),
    }


def pct(part, whole):
    """A share as text, e.g. "12.3 %"; "n/a" when the whole is 0."""
    if whole <= 0:
        return "n/a"
    return "%.1f %%" % (100.0 * part / whole)


def num(value, fmt="%+.2f"):
    """A number as text, or "n/a" when it is missing (nan: an older log)."""
    if value != value:
        return "n/a"
    return fmt % value


def row(label, base, s, noise_mark=True):
    """One table row: what `s` (a summarized set) saves against `base`."""
    ms = base["frame"] - s["frame"]
    calls = base["calls"] - s["calls"]
    mark = " ~" if noise_mark and abs(ms) < base["spread"] else ""
    return "| %s | %+.2f%s | %s | %s | %s | %+d | %s |" % (
        label, ms, mark, pct(ms, base["frame"]),
        num(base["script"] - s["script"]), num(base["render"] - s["render"]),
        round(calls), pct(calls, base["calls"]))


def table(key, sets):
    """The markdown for one scenario/view/look: a heading, a summary line, the
    parts table and the raw means. `sets` maps a set name to its summary."""
    scenario, view, look = key
    base = sets.get(BASE)
    title = LOOK_TITLES.get(look, look)
    out = ["### %s crowd, view %d wide, %s" % (scenario, view, title), ""]
    if base is None:
        out.append("No all-parts-drawn measurement for this group: nothing to compare with.")
        out.append("")
        return out
    floor = sets.get(FLOOR)
    out.append("All parts drawn: **%.2f ms/frame** (95th percentile %.2f; script %s ms + render %s ms, the rest is waiting), **%d draw calls**, "
               "%d units, %d rounds. Spread of the all-drawn rounds: %.2f ms." % (
                   base["frame"], base["p95"], num(base["script"], "%.2f"), num(base["render"], "%.2f"),
                   round(base["calls"]), base["units"], base["n"], base["spread"]))
    out.append("")
    out.append("| Part left out | ms/frame saved | share of frame | script ms saved | render ms saved | draw calls saved | share of draw calls |")
    out.append("|---|---:|---:|---:|---:|---:|---:|")
    total = {"ms": 0.0, "script": 0.0, "render": 0.0, "calls": 0.0}
    for part in PARTS:
        s = sets.get(part)
        if s is None:
            out.append("| %s | n/a | n/a | n/a | n/a | n/a | n/a |" % part)
            continue
        out.append(row(part, base, s))
        total["ms"] += base["frame"] - s["frame"]
        total["script"] += base["script"] - s["script"]
        total["render"] += base["render"] - s["render"]
        total["calls"] += base["calls"] - s["calls"]
    out.append("| **sum of the parts** | %+.2f | %s | %s | %s | %+d | %s |" % (
        total["ms"], pct(total["ms"], base["frame"]), num(total["script"]), num(total["render"]),
        round(total["calls"]), pct(total["calls"], base["calls"])))
    drawing = sets.get(DRAWING)
    if drawing is not None:
        out.append(row("**the six drawn parts left out** (only the redraw of the hull fills stays)", base, drawing, noise_mark=False))
    if floor is not None:
        out.append(row("**all parts left out**", base, floor, noise_mark=False))
        f_ms = base["frame"] - floor["frame"]
        f_script = base["script"] - floor["script"]
        f_render = base["render"] - floor["render"]
        f_calls = base["calls"] - floor["calls"]
        out.append("| not explained by one part alone | %+.2f | %s | %s | %s | %+d | %s |" % (
            f_ms - total["ms"], pct(f_ms - total["ms"], base["frame"]), num(f_script - total["script"]),
            num(f_render - total["render"]), round(f_calls - total["calls"]), pct(f_calls - total["calls"], base["calls"])))
        out.append("")
        out.append("What is left with every part out: %.2f ms/frame, %d draw calls (the hull fills, the scene and the engine itself)." % (floor["frame"], round(floor["calls"])))
    empty = sets.get(EMPTY)
    if empty is not None:
        out.append("")
        out.append("With no unit drawn at all (the empty scene): %.2f ms/frame, %d draw calls (the units are only hidden, so their own per-frame work still runs). No change to how the units are drawn can go below that; "
                   "the units themselves add %.2f ms and %d draw calls at the very least (with every part left out)." % (
                       empty["frame"], round(empty["calls"]),
                       (floor["frame"] - empty["frame"]) if floor is not None else float("nan"),
                       round(floor["calls"] - empty["calls"]) if floor is not None else 0))
    out.append("")
    out.append("Raw means over the rounds:")
    out.append("")
    out.append("| Set | frame ms | p95 ms | script ms | render ms | process ms (slowest frame of the second) | draw calls | rounds |")
    out.append("|---|---:|---:|---:|---:|---:|---:|---:|")
    for name in [BASE] + PARTS + [DRAWING, FLOOR, EMPTY]:
        s = sets.get(name)
        if s is None:
            continue
        label = {BASE: "all parts drawn", DRAWING: "the six drawn parts left out", FLOOR: "all parts left out", EMPTY: "empty scene (no unit drawn)"}.get(name, name + " left out")
        out.append("| %s | %.2f | %.2f | %s | %s | %.2f | %d | %d |" % (
            label, s["frame"], s["p95"], num(s["script"], "%.2f"), num(s["render"], "%.2f"), s["process"], round(s["calls"]), s["n"]))
    out.append("")
    return out


def build(paths):
    """The whole markdown document for the given logs, or None when they hold no
    measurements."""
    cells, heads = parse(paths)
    if not cells:
        return None
    lines = ["# What each part of the per-unit drawing costs (T-21 stage A)", ""]
    lines.append("Saved = (all parts drawn) minus (that part left out alone), the average over the rounds "
                 "(the warm-up round is skipped). Share = saved divided by all parts drawn. "
                 "\"~\" marks a frame saving smaller than the spread of the all-drawn rounds (within noise). "
                 "Parts overlap (above all, the redraw row contains the script cost of every other part), so the rows need not add up to the all-left-out row. "
                 "Script ms is the game's own work in a frame (all _process and _draw calls), render ms is Godot's drawing of it; "
                 "the rest of the frame is waiting, mostly for the graphics card. "
                 "\"process ms\" is Godot's own monitor, refreshed once a second with the slowest frame of that second: a rough hint, not an average.")
    lines.append("")
    for scenario, head in sorted(heads.items()):
        lines.append("- %s crowd: game view %s, %s rounds of %s frames each." % (scenario, head.get("size", "?"), head.get("rounds", "?"), head.get("frames", "?")))
    lines.append("")
    look_order = list(LOOK_TITLES)
    for key in sorted(cells, key=lambda k: (k[0], k[1], look_order.index(k[2]) if k[2] in look_order else 99)):
        sets = {off: summarize(recs) for off, recs in cells[key].items()}
        lines.extend(table(key, sets))
    lines.append("Notes on the parts:")
    lines.append("")
    for part in PARTS:
        lines.append("- %s: %s" % (part, PART_NOTES[part]))
    lines.append("")
    return "\n".join(lines)


def selftest():
    """Check the maths on made-up lines; returns the number of failures."""
    import os
    import tempfile
    rows = []
    # A base of 40 ms (script 20, render 15) and 1000 calls; flames save 4 ms / 100 calls; redraw saves 6 ms / 0 calls; all off 25 ms / 600 calls.
    spec = {BASE: (40.0, 1000), "flames": (36.0, 900), "arcs": (38.0, 800), "arrow": (39.9, 1000), "bars": (39.0, 950),
            "name": (40.0, 1000), "outline": (37.0, 850), "redraw": (34.0, 1000), DRAWING: (30.0, 450), FLOOR: (20.0, 400), EMPTY: (12.0, 300)}
    for rnd in (0, 1, 2, 3):
        for off, (ms, calls) in spec.items():
            wobble = 0.1 * (rnd - 2)
            rows.append("DRAWCOST scenario=busy view=4500 round=%d look=cinder_alien off=%s units=280 frame_ms=%.3f p95_ms=%.3f script_ms=%.3f render_ms=%.3f process_ms=%.3f draw_calls=%d"
                        % (rnd, off, ms + wobble + (50.0 if rnd == 0 else 0.0), ms + 2, ms / 2, ms * 0.375, ms / 2, calls))
    rows.insert(0, "bench-parts: scenario=busy view=4500 size=1302x720 rounds=3 frames=240 sets=9 looks=3")
    rows.append("some other log line")
    fd, path = tempfile.mkstemp(suffix=".txt")
    os.close(fd)
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(rows) + "\n")
        doc = build([path])
    finally:
        os.remove(path)
    fails = 0

    def check(cond, what):
        nonlocal fails
        if not cond:
            fails += 1
            print("selftest FAIL: " + what)
    check(doc is not None, "no document")
    if doc:
        check("| flames | +4.00 | 10.0 % | +2.00 | +1.50 | +100 | 10.0 %" in doc, "flames row (saves 4 ms, script 2, render 1.5, 100 calls)")
        check("| redraw | +6.00 | 15.0 % | +3.00 | +2.25 | +0 | 0.0 %" in doc, "redraw saves no draw calls")
        check("| arrow | +0.10 ~" in doc, "arrow marked within noise")
        check("| **all parts left out** | +20.00 | 50.0 % | +10.00 | +7.50 | +600 | 60.0 %" in doc, "all-off row")
        check("| **the six drawn parts left out** (only the redraw of the hull fills stays) | +10.00 | 25.0 % | +5.00 | +3.75 | +550 | 55.0 %" in doc, "drawing row")
        check("With no unit drawn at all (the empty scene): 12.00 ms/frame, 300 draw calls (the units are only hidden" in doc, "empty scene line")
        check("the units themselves add 8.00 ms and 100 draw calls" in doc, "units over the empty scene")
        check("All parts drawn: **40.00 ms/frame**" in doc, "base line (round 0 warm-up skipped)")
    print("draw_cost_table selftest: %d failures" % fails)
    return fails


def main():
    ap = argparse.ArgumentParser(description="Make the draw-cost table from parts bench logs.")
    ap.add_argument("logs", nargs="*", help="log files that hold DRAWCOST lines")
    ap.add_argument("-o", "--out", help="write the markdown here instead of printing it")
    ap.add_argument("--selftest", action="store_true", help="check the script on made-up lines")
    args = ap.parse_args()
    if args.selftest:
        return 1 if selftest() else 0
    if not args.logs:
        ap.error("give at least one log file")
    doc = build(args.logs)
    if doc is None:
        print("draw_cost_table: no DRAWCOST lines in the logs")
        return 2
    if args.out:
        with open(args.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(doc)
        print("draw_cost_table: wrote %s" % args.out)
    else:
        print(doc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
