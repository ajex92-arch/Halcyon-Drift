"""Puts two folders of test runs side by side, with a PASS or FLAG for each gate of the user test fork.

WHAT THIS IS: the fork's comparison tool (docs/USER_FORK_PLAN.md, "How every
stage is built and checked"). Every stage of the fork is measured against the
stage before it, and this tool does that comparison. Folder A is the
reference (the stage before, or the v0.1.0 yardstick); folder B is the new
stage. It reads the logs the tests print and writes a markdown report with
one PASS or FLAG per gate:

  Gate 3  The AI stays decent. From pilot_audit and admiral_audit (the
          AUDIT_JSON lines): stuck episodes, rock contacts, shots into rocks
          and crash deaths (per pilot-minute in space, so a stage with fewer
          pilots can be compared with one that has more), the admiral's
          decisions per minute (the band is 0.5-3), mining-drone losses and
          idle drones. FLAG when one is more than 10% worse than in A.
  Gate 4  Match health. From the fun_probe logs (or, failing those, the
          other logs): the share of matches that end, the median length and
          the side split (Aurelian's share of the ended matches should be
          50% +- 10), and any script error in the logs. FLAG when the split
          is outside 40-60%, when a script error is found, or when the share
          of matches that end drops by more than 10 points.
  Gate 5  Performance. From perf_probe (its PERF_JSON line, or else its
          minute lines): the mean computer time per game second (CPU time
          when the log has it, else wall time) and the 3 slowest ticks (with
          the p99.9 tick and the share of ticks over 33 ms beside them, to
          tell bad luck on a busy PC from a pattern). FLAG when B's mean is
          more than 15% above A's, or when a tick took more than 33 ms (two
          frames at 60 fps).
  Gate 6  The fun meter, for information. FUN and its 11 ingredients from
          fun_probe (FUN_JSON lines), matched by seed and scored by
          tools/fun_score.py. FLAG when an ingredient falls by more than 15
          points in B.
Every gate says "n/a" when a folder holds none of the logs it needs. The
thresholds are the constants at the top of this file. Keep one kind of run in
a folder (full matches, or --late runs): the tool pairs the audit logs of A
and B by seed (two audit runs with one seed would replace each other), while
the perf logs are grouped by kind (late or not, worst-case switch or not)
and averaged.

HOW TO RUN IT (from the remake folder; it needs only Python itself):
    python -I tools/utf_compare.py --a <folder A> --b <folder B>
Options:
    --a FOLDER, --b FOLDER   the two folders of logs (every file in them is
                             read; names like <tag>_seed<N>.txt give the seed)
    --label-a TEXT, --label-b TEXT   the names used in the report (default:
                             the folder names)
    --out FILE               also write the report to this file
    --resamples N            the fun meter's bootstrap rounds (default 2,000)
    --at30                   score the fun meter at 30:00 (see fun_score.py)
Exit code: 0 when no gate is flagged, 1 when one is, 2 on a usage error.

HOW IT WORKS:
  1. read_side() reads one folder: the FUN_JSON lines (through fun_lib, as
     fun_score.py does), the AUDIT_JSON lines of pilot_audit (their
     "counters" is a dictionary) and of admiral_audit ("counters" is a list
     of two dictionaries), the PERF_JSON lines (or minute lines), the
     SUMMARY lines, and a count of script errors.
  2. Each gate has a function that takes both sides and returns a Gate: its
     result ("PASS", "FLAG" or "n/a"), a one-line detail and the markdown of
     its tables.
  3. report() puts the gates together.
Audit and performance numbers are compared on the seeds both folders have.

WHO USES IT: the lead and the stage builders, after every stage's runs
(docs/USER_FORK_PLAN.md). It uses fun_lib.py and fun_score.py in the same
folder.
"""
import argparse
import glob
import json
import math
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fun_lib  # noqa: E402  (the shared parts of the fun score)
import fun_score  # noqa: E402

# --- the thresholds of the gates (docs/USER_FORK_PLAN.md) ----------------------------

# Gate 3: a metric more than this much (a fraction) worse than in A is flagged.
WORSE_LIMIT = 0.10
# Gate 3: the band (decisions per minute) the admiral should stay in.
DECISION_BAND = (0.5, 3.0)
# Gate 3: the admiral orders that are not decisions (as in tests/lib/fun_probe_economy.gd).
NOT_DECISIONS = ("drone", "waypoint", "order")
# Gate 3: fewer events than this in A and B together: the flag is marked "few events".
FEW_EVENTS = 10
# Gate 4: Aurelian's share of the ended matches must lie in this band.
SPLIT_BAND = (0.40, 0.60)
# Gate 4: the share of matches that end may fall by this much (a fraction).
ENDED_DROP = 0.10
# Gate 5: B's mean computer time may be this much (a fraction) above A's.
PERF_LIMIT = 0.15
# Gate 5: no single tick may take longer than this (milliseconds).
WORST_TICK_MS = 33.0
# Gate 5: the first seconds of a run are left out of the slowest ticks.
PERF_SKIP_S = 120.0
# Gate 6: an ingredient may fall by this many points before it is flagged.
INGREDIENT_DROP = 15.0

# Lines in a log that mean the game itself failed (as in SP\run_checks.ps1).
ERROR_RE = re.compile(r"SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Nonexistent function|Identifier .* not declared")
# A minute line of main.gd: "t=25:00  sim 12.3 ms/sim-s  worst tick 4.5 ms  units=...".
MINUTE_RE = re.compile(r"^t=(\d+):(\d+)\s+sim ([\d.]+) ms/sim-s\s+worst tick ([\d.]+) ms")


class Gate:
    """The verdict on one gate: `result` is "PASS", "FLAG" or "n/a", `detail`
    is one line for the summary table, `body` is the markdown of its tables."""

    def __init__(self, number, name):
        self.number = number
        self.name = name
        self.result = "n/a"
        self.detail = "no logs for this gate in one or both folders"
        self.body = ""


# --- reading a folder ---------------------------------------------------------------------------

def seed_of_name(name):
    """The seed number in a log file name such as "tag_seed301.txt" (None if
    there is none)."""
    m = re.search(r"_seed(\d+)", name)
    return int(m.group(1)) if m else None


def read_side(path, label, at30=False):
    """Read folder `path` into a dictionary (a "side"):
      label, path, files          the name, the folder, how many log files
      fun                         {mode: {seed: record}} (fun_lib)
      duel                        the DUEL_JSON dictionary, or None
      pilot                       {seed: AUDIT_JSON of pilot_audit}
      admiral                     {seed: AUDIT_JSON of admiral_audit}
      perf                        [one dictionary per perf_probe run]
      summary                     {seed: the SUMMARY dictionary}
      errors                      [lines that show a script error]
      notes                       warnings from reading"""
    if not os.path.isdir(path):
        sys.exit(f"utf_compare: no such folder: {path}")
    side = {"label": label, "path": path, "files": 0, "pilot": {}, "admiral": {}, "perf": [], "summary": {}, "errors": [], "notes": []}
    records, duel, fnotes = fun_lib.read_dir(path, at30)
    side["fun"] = fun_lib.by_mode_and_seed(records, fnotes)
    side["duel"] = duel
    side["notes"] += fnotes
    for full in sorted(glob.glob(os.path.join(path, "*"))):
        name = os.path.basename(full)
        if not os.path.isfile(full) or name.endswith(".timeout.txt") or name.endswith(".done.txt"):
            continue
        side["files"] += 1
        seed = seed_of_name(name)
        minutes = []
        other_test = False   # the log also holds a fun_probe or audit result, so it is not a perf log
        profiled = False     # the log has main.gd's "prof ms/sim-s" lines (perf_probe switches them on)
        with open(full, encoding="utf-8", errors="replace") as f:
            for line in f:
                if ERROR_RE.search(line):
                    side["errors"].append(f"{name}: {line.strip()[:160]}")
                if line.startswith("FUN_JSON") or line.startswith("AUDIT_JSON "):
                    other_test = True
                elif "prof ms/sim-s" in line:
                    profiled = True
                if line.startswith("AUDIT_JSON "):
                    j = _json(line[len("AUDIT_JSON "):], name, side)
                    if j is None:
                        continue
                    key = seed if seed is not None else f"{name}"
                    if isinstance(j.get("counters"), list):
                        side["admiral"][key] = j
                    elif isinstance(j.get("counters"), dict):
                        side["pilot"][key] = j
                elif line.startswith("PERF_JSON "):
                    j = _json(line[len("PERF_JSON "):], name, side)
                    if j is not None:
                        j["_file"] = name
                        j["_seed"] = seed
                        side["perf"].append(j)
                        minutes = None
                elif line.startswith("SUMMARY "):
                    j = _json(line[len("SUMMARY "):], name, side)
                    if j is not None and seed is not None:
                        side["summary"][seed] = j
                elif minutes is not None:
                    m = MINUTE_RE.match(line)
                    if m:
                        minutes.append((int(m.group(1)) * 60 + int(m.group(2)), float(m.group(3)), float(m.group(4))))
        # A perf log made before PERF_JSON existed: build the same record from its minute lines.
        # (Every test prints minute lines; only a perf_probe log, which has the
        # "prof" lines and no other test's result line, is a perf log.)
        if minutes and profiled and not other_test:
            side["perf"].append(_perf_from_minutes(minutes, name, seed))
    return side


def _json(text, name, side):
    """Parse the JSON in `text`, or note the problem and return None."""
    try:
        return json.loads(text)
    except ValueError:
        side["notes"].append(f"{name}: a JSON line could not be read (skipped)")
        return None


def _perf_from_minutes(minutes, name, seed):
    """A perf record (like PERF_JSON) from the minute lines [(clock s, sim ms
    per sim-s, worst tick ms)] of an older perf_probe log. There is no CPU time
    in such a log. A run that starts at 25:00 shows clock times from 1,500."""
    late = minutes[0][0] >= 1500
    start = 1500 if late else 0
    slow = sorted((m[2] for m in minutes if m[0] - start >= PERF_SKIP_S), reverse=True)[:3]
    return {"late": late, "perf_worst": None, "wall_ms_per_sim_s": statistics.fmean(m[1] for m in minutes),
            "worst3_ms": slow, "cpu_ms_per_sim_s": -1.0, "_file": name, "_seed": seed, "_from": "minute lines"}


# --- small helpers --------------------------------------------------------------------------------

def pct(a, b):
    """The change from `a` to `b` as text such as "+12%" ("new" when a is 0, "-" when both are)."""
    if a == 0:
        return "new" if b else "-"
    return f"{(b - a) / a * 100:+.0f}%"


def num(x, digits=2):
    """A number as short text, "n/a" for None."""
    if x is None:
        return "n/a"
    if abs(x) >= 1000:
        return f"{x:,.0f}"
    return f"{x:.{digits}f}"


def table(head, rows):
    """A markdown table from a header list and a list of row lists."""
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out) + "\n"


def paired(a, b):
    """The seeds that are in both dictionaries `a` and `b` (sorted, numbers only)."""
    return sorted(s for s in set(a) & set(b) if isinstance(s, int))


def worse_flag(a, b, small=False):
    """Is `b` more than WORSE_LIMIT worse than `a` for a lower-is-better
    number? Returns "FLAG" / "ok". (A flag from 0 up to anything counts.)"""
    return "FLAG" if b > a * (1.0 + WORSE_LIMIT) + 1e-12 else "ok"


# --- gate 3: the AI stays decent --------------------------------------------------------------

def pilot_numbers(j):
    """The pilot_audit numbers of one run, from its AUDIT_JSON `j`: pilot-
    minutes in space, and the counts. (The audit samples every flying AI
    pilot every 0.5 s, so samples x 0.5 s is the time spent in space.)"""
    c = j["counters"]
    minutes = float(c.get("samples", 0.0)) * 0.5 / 60.0
    return {"minutes": minutes, "stuck": float(c.get("stuck_episodes", 0.0)),
            "rock_s": float(c.get("rock_contact_ticks", 0.0)) / 60.0,
            "rock_shots": float(c.get("occluded_firing", 0.0)), "crash": float(c.get("death_crash", 0.0))}


def admiral_numbers(j):
    """The admiral_audit numbers of one run, from its AUDIT_JSON `j`, added up
    over the teams that had a computer admiral: admiral-minutes, decisions,
    drones lost, and the idle-drone figures (None if the log does not have
    them: it was made before the audit counted idle drones)."""
    minutes = decisions = lost = idle_sum = samples = 0.0
    has_idle = False
    for c in j["counters"]:
        n = float(c.get("samples", 0.0))
        if n <= 0:
            continue
        samples += n
        minutes += n / 60.0
        for k, v in c.items():
            if k.startswith("cmd_") and k.endswith("_ok") and k[4:-3] not in NOT_DECISIONS:
                decisions += float(v)
        lost += float(c.get("drone_died", 0.0))
        if "drones_idle_sum" in c or "drones_sum" in c and "drones_idle_s" in c:
            has_idle = True
        idle_sum += float(c.get("drones_idle_sum", 0.0))
    return {"minutes": minutes, "decisions": decisions, "lost": lost, "samples": samples,
            "idle_sum": idle_sum if has_idle else None}


def rate(sum_num, sum_den, scale):
    """sum_num / sum_den x scale, or None when sum_den is 0."""
    return sum_num / sum_den * scale if sum_den > 0 else None


def gate3(a, b):
    """Gate 3, the AI stays decent (see the top of this file)."""
    g = Gate(3, "The AI stays decent")
    rows = []
    flags = []
    seeds_p = paired(a["pilot"], b["pilot"])
    seeds_a = paired(a["admiral"], b["admiral"])
    # Each metric: (name, how to read it from the summed numbers of one side, unit, direction).
    def pilot_metric(name, key, scale, unit):
        na = [pilot_numbers(a["pilot"][s]) for s in seeds_p]
        nb = [pilot_numbers(b["pilot"][s]) for s in seeds_p]
        ra = rate(sum(x[key] for x in na), sum(x["minutes"] for x in na), scale)
        rb = rate(sum(x[key] for x in nb), sum(x["minutes"] for x in nb), scale)
        ev_a, ev_b = sum(x[key] for x in na), sum(x[key] for x in nb)
        # Seeds where B was lower / higher than A (per seed, same rate).
        lo = hi = 0
        for x, y in zip(na, nb):
            rx, ry = rate(x[key], x["minutes"], scale), rate(y[key], y["minutes"], scale)
            if rx is not None and ry is not None:
                lo += ry < rx
                hi += ry > rx
        verdict = "ok"
        if ra is not None and rb is not None:
            verdict = worse_flag(ra, rb)
            if verdict == "FLAG" and ev_a + ev_b < FEW_EVENTS:
                verdict = "FLAG (few events)"
        rows.append([name, unit, num(ra), num(rb), pct(ra or 0.0, rb or 0.0), f"{num(ev_a, 0)} / {num(ev_b, 0)}", f"{lo} / {hi}", verdict])
        if verdict.startswith("FLAG"):
            flags.append(name)
    if seeds_p:
        pilot_metric("stuck episodes", "stuck", 100.0, "per 100 pilot-min")
        pilot_metric("rock contact", "rock_s", 1.0, "ship-s per pilot-min")
        pilot_metric("shots into rocks", "rock_shots", 100.0, "per 100 pilot-min")
        pilot_metric("crash deaths", "crash", 100.0, "per 100 pilot-min")
    if seeds_a:
        na = [admiral_numbers(a["admiral"][s]) for s in seeds_a]
        nb = [admiral_numbers(b["admiral"][s]) for s in seeds_a]
        # Decisions per minute against the band.
        da = rate(sum(x["decisions"] for x in na), sum(x["minutes"] for x in na), 1.0)
        db = rate(sum(x["decisions"] for x in nb), sum(x["minutes"] for x in nb), 1.0)
        if da is not None and db is not None:
            lo_band, hi_band = DECISION_BAND

            def outside(x):
                return max(lo_band - x, x - hi_band, 0.0)
            verdict = "FLAG" if outside(db) > outside(da) * (1.0 + WORSE_LIMIT) + 1e-12 else "ok"
            band = "in band" if outside(db) == 0 else "outside band"
            rows.append(["admiral decisions", f"per min (band {lo_band}-{hi_band})", num(da), num(db), pct(da, db),
                         f"{num(sum(x['decisions'] for x in na), 0)} / {num(sum(x['decisions'] for x in nb), 0)}", "-", f"{verdict} ({band})"])
            if verdict == "FLAG":
                flags.append("admiral decisions")
        # Drone losses per 10 admiral-minutes.
        la = rate(sum(x["lost"] for x in na), sum(x["minutes"] for x in na), 10.0)
        lb = rate(sum(x["lost"] for x in nb), sum(x["minutes"] for x in nb), 10.0)
        if la is not None and lb is not None:
            verdict = worse_flag(la, lb)
            ev = sum(x["lost"] for x in na) + sum(x["lost"] for x in nb)
            if verdict == "FLAG" and ev < FEW_EVENTS:
                verdict = "FLAG (few events)"
            rows.append(["mining drones lost", "per 10 team-min", num(la), num(lb), pct(la, lb),
                         f"{num(sum(x['lost'] for x in na), 0)} / {num(sum(x['lost'] for x in nb), 0)}", "-", verdict])
            if verdict.startswith("FLAG"):
                flags.append("drone losses")
        # Idle drones: the mean number idle at a sample.
        if all(x["idle_sum"] is not None for x in na + nb) and na:
            ia = rate(sum(x["idle_sum"] for x in na), sum(x["samples"] for x in na), 1.0)
            ib = rate(sum(x["idle_sum"] for x in nb), sum(x["samples"] for x in nb), 1.0)
            verdict = "ok"
            if ia is not None and ib is not None:
                verdict = worse_flag(ia, ib)
            rows.append(["idle mining drones", "mean per team", num(ia, 3), num(ib, 3), pct(ia or 0.0, ib or 0.0), "-", "-", verdict])
            if verdict == "FLAG":
                flags.append("idle drones")
        else:
            rows.append(["idle mining drones", "mean per team", "n/a", "n/a", "-", "-", "-", "not in these logs (the audit counts them from stage 0 on)"])
    if not rows:
        return g
    g.result = "FLAG" if flags else "PASS"
    g.detail = ("FLAG: " + ", ".join(flags)) if flags else f"none worse than +{WORSE_LIMIT * 100:.0f}% ({len(seeds_p)} pilot-audit and {len(seeds_a)} admiral-audit seeds)"
    g.body = (f"Seeds in both folders: pilot_audit {seeds_p}, admiral_audit {seeds_a}. Columns: A and B are the figures per the unit, "
              "then the change, the event counts in A / B, the seeds where B was lower / higher than A, and the verdict "
              f"(FLAG = more than {WORSE_LIMIT * 100:.0f}% worse than A).\n\n"
              + table(["metric", "unit", a["label"], b["label"], "change", "events A / B", "seeds B lower / higher", "verdict"], rows))
    return g


# --- gate 4: match health ---------------------------------------------------------------------

def health(side):
    """The match health of one side, from the best logs it has: a list of
    (seed, ended, minutes, winner) and where they came from. fun_probe's
    FUN_JSON first, else the SUMMARY lines, else the admiral audit."""
    out = {}
    source = ""
    fun = {}
    for mode in ("normal",):
        fun.update(side["fun"].get(mode, {}))
    if fun:
        source = "fun_probe"
        for s, r in fun.items():
            out[s] = (bool(r.get("ended")), float(r.get("minutes", 0.0)), r.get("winner"))
    elif side["summary"]:
        source = "SUMMARY lines"
        for s, j in side["summary"].items():
            ended = j.get("winner", -1) in (0, 1)
            out[s] = (ended, float(j.get("time", 0.0)) / 60.0, j.get("winner") if ended else None)
    elif side["admiral"]:
        source = "admiral_audit"
        for s, j in side["admiral"].items():
            ended = j.get("winner") in (0, 1)
            out[s] = (ended, float(j.get("time", 0.0)) / 60.0, j.get("winner") if ended else None)
    return out, source


def health_numbers(h):
    """From {seed: (ended, minutes, winner)}: matches, ended, share ended,
    Aurelian wins, Aurelian's share of the ended matches, median length."""
    n = len(h)
    ended = [v for v in h.values() if v[0]]
    wins = sum(1 for v in ended if v[2] == 0)
    return {"n": n, "ended": len(ended), "share": len(ended) / n if n else None, "wins": wins,
            "split": wins / len(ended) if ended else None,
            "median": statistics.median(v[1] for v in h.values()) if n else None}


def gate4(a, b):
    """Gate 4, match health (see the top of this file)."""
    g = Gate(4, "Match health")
    ha, sa = health(a)
    hb, sb = health(b)
    if not ha or not hb:
        return g
    na, nb = health_numbers(ha), health_numbers(hb)
    flags = []
    lo, hi = SPLIT_BAND
    split_ok = nb["split"] is None or lo <= nb["split"] <= hi
    if not split_ok:
        flags.append(f"side split {nb['split'] * 100:.0f}% outside {lo * 100:.0f}-{hi * 100:.0f}%")
    if nb["share"] is not None and na["share"] is not None and na["share"] - nb["share"] > ENDED_DROP + 1e-12:
        flags.append(f"matches that end fell from {na['share'] * 100:.0f}% to {nb['share'] * 100:.0f}%")
    errors_b = len(b["errors"])
    if errors_b:
        flags.append(f"{errors_b} script error line(s) in B")
    rows = [
        ["matches", na["n"], nb["n"], ""],
        ["share that end", num(na["share"] * 100 if na["share"] is not None else None, 0) + "%", num(nb["share"] * 100 if nb["share"] is not None else None, 0) + "%",
         f"FLAG (fell more than {ENDED_DROP * 100:.0f} points)" if any("matches that end" in f for f in flags) else "ok"],
        ["median length (min)", num(na["median"], 1), num(nb["median"], 1), pct(na["median"] or 0.0, nb["median"] or 0.0)],
        ["Aurelian wins / ended", f"{na['wins']} / {na['ended']}", f"{nb['wins']} / {nb['ended']}", ""],
        ["Aurelian share of ended", num(na["split"] * 100 if na["split"] is not None else None, 0) + "%", num(nb["split"] * 100 if nb["split"] is not None else None, 0) + "%",
         "ok" if split_ok else f"FLAG (outside {lo * 100:.0f}-{hi * 100:.0f}%)"],
        ["script error lines", len(a["errors"]), errors_b, "ok" if not errors_b else "FLAG"],
    ]
    g.result = "FLAG" if flags else "PASS"
    g.detail = ("FLAG: " + "; ".join(flags)) if flags else f"split {num((nb['split'] or 0) * 100, 0)}%, {nb['ended']}/{nb['n']} ended, median {num(nb['median'], 1)} min, no script errors"
    g.body = f"A from {sa}, B from {sb}. Unended matches count at their run length.\n\n" + table(["", a["label"], b["label"], "verdict"], rows)
    if errors_b:
        g.body += "\nFirst script error lines in B:\n\n" + "\n".join("- " + e for e in b["errors"][:8]) + "\n"
    return g


# --- gate 5: performance -----------------------------------------------------------------------

def perf_groups(side):
    """The perf runs of one side by kind: {(late, perf_worst): [runs]}."""
    out = {}
    for r in side["perf"]:
        out.setdefault((bool(r.get("late")), r.get("perf_worst")), []).append(r)
    return out


def perf_mean(runs, key):
    """The mean of `key` over the runs that have it (> 0), or None."""
    vals = [float(r[key]) for r in runs if r.get(key) is not None and float(r[key]) > 0]
    return statistics.fmean(vals) if vals else None


def perf_avg(runs, key):
    """The mean of `key` over the runs that have it (a 0 counts), or None."""
    vals = [float(r[key]) for r in runs if r.get(key) is not None]
    return statistics.fmean(vals) if vals else None


def share(x):
    """A share (0..1) as text such as "0.31%" ("n/a" for None)."""
    return "n/a" if x is None else f"{x * 100:.2f}%"


def perf_worst(runs):
    """The 3 slowest ticks over all the runs (milliseconds, slowest first)."""
    allv = sorted((float(v) for r in runs for v in r.get("worst3_ms", [])), reverse=True)
    return allv[:3]


def gate5(a, b):
    """Gate 5, performance (see the top of this file)."""
    g = Gate(5, "Performance")
    ga, gb = perf_groups(a), perf_groups(b)
    kinds = [k for k in sorted(gb, key=lambda k: (k[0], str(k[1]))) if k in ga]
    if not kinds:
        return g
    rows = []
    flags = []
    for k in kinds:
        ra, rb = ga[k], gb[k]
        name = ("late " if k[0] else "normal ") + ("worst-case" if k[1] else "plain" if k[1] is not None else "")
        # CPU time when both sides have it, else wall time.
        ca, cb = perf_mean(ra, "cpu_ms_per_sim_s"), perf_mean(rb, "cpu_ms_per_sim_s")
        wa, wb = perf_mean(ra, "wall_ms_per_sim_s"), perf_mean(rb, "wall_ms_per_sim_s")
        use_cpu = ca is not None and cb is not None
        ma, mb = (ca, cb) if use_cpu else (wa, wb)
        basis = "CPU" if use_cpu else "wall"
        verdict = "ok"
        if ma is not None and mb is not None and mb > ma * (1.0 + PERF_LIMIT):
            verdict = f"FLAG (mean {basis} over +{PERF_LIMIT * 100:.0f}%)"
            flags.append(f"{name.strip()} mean {basis} {pct(ma, mb)}")
        wt_a, wt_b = perf_worst(ra), perf_worst(rb)
        # How common slow ticks are (one slow tick can be luck on a busy PC).
        qa, qb = perf_avg(ra, "p999_ms"), perf_avg(rb, "p999_ms")
        oa, ob = perf_avg(ra, "over_33ms"), perf_avg(rb, "over_33ms")
        tick = "ok"
        if wt_b and max(wt_b) > WORST_TICK_MS:
            more = "" if qb is None else f"; B's p99.9 is {qb:.0f} ms and {share(ob)} of its ticks are over {WORST_TICK_MS:.0f} ms"
            tick = f"FLAG (a tick over {WORST_TICK_MS:.0f} ms{more})"
            flags.append(f"{name.strip()} worst tick {max(wt_b):.1f} ms")
        rows.append([name.strip() or "perf", f"{len(ra)} / {len(rb)}", num(wa, 1), num(wb, 1), num(ca, 1), num(cb, 1),
                     f"{pct(ma or 0.0, mb or 0.0)} ({basis})", verdict,
                     ", ".join(f"{v:.1f}" for v in wt_a) or "n/a", ", ".join(f"{v:.1f}" for v in wt_b) or "n/a",
                     f"{num(qa, 0)} / {num(qb, 0)}", f"{share(oa)} / {share(ob)}", tick])
    g.result = "FLAG" if flags else "PASS"
    g.detail = ("FLAG: " + "; ".join(flags)) if flags else f"mean within +{PERF_LIMIT * 100:.0f}% and no tick over {WORST_TICK_MS:.0f} ms"
    g.body = ("Milliseconds of computer time per game second, as wall-clock time (it grows when other programs use the cores) and as CPU time "
              "(it does not; the verdict uses CPU time when both sides have it, else wall time). "
              f"FLAG = B's mean more than {PERF_LIMIT * 100:.0f}% above A's, or a tick over {WORST_TICK_MS:.0f} ms. The slowest ticks are the 3 slowest "
              f"single ticks after the first {PERF_SKIP_S:.0f} s of the runs. On a PC that is busy with other matches a single slow tick can be luck: "
              f"the p99.9 column (the cost 99.9% of the ticks stay under) and the share of ticks over {WORST_TICK_MS:.0f} ms say whether slow ticks "
              "are the rule (both come from the PERF_JSON line; older logs do not have them).\n\n"
              + table(["kind", "runs A / B", f"wall {a['label']}", f"wall {b['label']}", f"CPU {a['label']}", f"CPU {b['label']}", "change", "mean",
                       "slowest ticks A (ms)", "slowest ticks B (ms)", "p99.9 A / B (ms)", f"over {WORST_TICK_MS:.0f} ms A / B", "ticks"], rows))
    return g


# --- gate 6: the fun meter ---------------------------------------------------------------------

def gate6(a, b, resamples):
    """Gate 6, the fun meter (see the top of this file). B is scored against
    A on the seeds both have, with fun_score.score_group (so the differences
    are B minus A)."""
    g = Gate(6, "The fun meter (for information)")
    parts = []
    flags = []
    detail = []
    for mode in ("normal", "late"):
        recs_a, recs_b = a["fun"].get(mode, {}), b["fun"].get(mode, {})
        if not recs_a or not recs_b:
            continue
        res = fun_score.score_group(mode, recs_b, b["duel"], recs_a, a["duel"], resamples, 20261015)
        if res.get("no_match") or "diff" not in res:
            parts.append(f"{mode} runs: the folders share no seed, so they cannot be compared.\n")
            continue
        boot = res.get("boot") or {}
        diff = res["diff"]
        rows = []
        for ing, name, _w in fun_lib.INGREDIENTS:
            sa = res["b"]["ingredients"][ing]["score"]
            sb = res["a"]["ingredients"][ing]["score"]
            d = diff.get(ing)
            ci = (boot.get("ci80") or {}).get(ing)
            verdict = "-"
            if d is not None:
                verdict = "ok"
                if d < -INGREDIENT_DROP:
                    verdict = f"FLAG (down {-d:.1f})"
                    flags.append(f"{mode} {ing} {name} {d:+.1f}")
            rows.append([ing, name, num(sa, 1), num(sb, 1), num(d, 1) if d is None else f"{d:+.1f}",
                         f"[{ci[0]:+.1f}, {ci[1]:+.1f}]" if ci else "-", verdict])
        fa, fb = res["b"]["fun"], res["a"]["fun"]
        line = f"FUN {num(fa, 1)} -> {num(fb, 1)} ({diff['fun']:+.1f})" if diff.get("fun") is not None else "FUN n/a"
        if boot:
            line += f", lower bound 90% {boot['lb90']:+.1f}, 95% {boot['lb95']:+.1f}"
        detail.append(f"{mode}: {line}")
        parts.append(f"**{mode} runs**, {len(res['matched'])} matched seeds ({res['matched'][0]}-{res['matched'][-1]}): {line}\n\n"
                     + table(["", "ingredient", a["label"], b["label"], "change", "80% interval", "verdict"], rows)
                     + (f"Not measured in both, left out: {', '.join(res['not_measured'])}.\n" if res.get("not_measured") else "")
                     + (f"Dropped so the two compare: {', '.join(res['dropped_vs'])}.\n" if res.get("dropped_vs") else ""))
    if not parts:
        return g
    g.result = "FLAG" if flags else "PASS"
    g.detail = ("FLAG: " + "; ".join(flags)) if flags else "; ".join(detail) + f"; no ingredient fell by more than {INGREDIENT_DROP:.0f}"
    g.body = f"FUN is for information; an ingredient that falls by more than {INGREDIENT_DROP:.0f} points is flagged and reported, never hidden.\n\n" + "\n".join(parts)
    return g


# --- the report -------------------------------------------------------------------------------------

def report(a, b, resamples):
    """Run every gate and return (the markdown text, whether any gate is flagged)."""
    gates = [gate3(a, b), gate4(a, b), gate5(a, b), gate6(a, b, resamples)]
    lines = [f"# {a['label']} vs {b['label']}", "",
             f"- A (reference): `{a['path']}` ({a['files']} log files)",
             f"- B (new): `{b['path']}` ({b['files']} log files)", ""]
    for side in (a, b):
        kinds = []
        for mode in ("normal", "late"):
            if side["fun"].get(mode):
                kinds.append(f"fun_probe {mode}: {len(side['fun'][mode])}")
        for key, nm in (("pilot", "pilot_audit"), ("admiral", "admiral_audit"), ("perf", "perf_probe")):
            if side[key]:
                kinds.append(f"{nm}: {len(side[key])}")
        lines.append(f"- {side['label']} holds " + (", ".join(kinds) if kinds else "none of the logs this tool reads") + " runs")
    lines += ["", "## Gates", "", table(["gate", "name", "result", "detail"], [[f"{g.number}", g.name, f"**{g.result}**", g.detail] for g in gates])]
    for g in gates:
        if g.result != "n/a":
            lines += [f"## Gate {g.number}: {g.name}", "", g.body]
    notes = a["notes"] + b["notes"]
    if notes:
        lines += ["## Notes from reading the logs", ""] + [f"- {n}" for n in notes[:20]] + [""]
    return "\n".join(lines), any(g.result == "FLAG" for g in gates)


def main():
    """Read the options, read both folders, print (and optionally save) the report."""
    ap = argparse.ArgumentParser(description="Two folders of test runs side by side, with a PASS or FLAG per gate (docs/USER_FORK_PLAN.md).")
    ap.add_argument("--a", required=True, help="folder A: the reference (the stage before, or the v0.1.0 yardstick)")
    ap.add_argument("--b", required=True, help="folder B: the new stage")
    ap.add_argument("--label-a", help="name of A in the report")
    ap.add_argument("--label-b", help="name of B in the report")
    ap.add_argument("--out", help="also write the report to this file")
    ap.add_argument("--resamples", type=int, default=2000, help="bootstrap rounds of the fun meter (default 2000)")
    ap.add_argument("--at30", action="store_true", help="score the fun meter at 30:00 (FUN_JSON30 lines)")
    args = ap.parse_args()
    a = read_side(args.a, args.label_a or os.path.basename(os.path.normpath(args.a)), args.at30)
    b = read_side(args.b, args.label_b or os.path.basename(os.path.normpath(args.b)), args.at30)
    text, flagged = report(a, b, args.resamples)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    sys.exit(1 if flagged else 0)


if __name__ == "__main__":
    main()
