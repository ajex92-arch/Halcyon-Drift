"""Compare deep-dive A/B runs.

usage: python -I ab_compare.py <runs\\ab dir> [<runs\\admiral dir>]

Pilot audits (ab_*, late_*): for each fix tag vs its base (ab_base or
late_base), only on seeds both have (paired), the key AUDIT_JSON counters
summed over those seeds, and the change. Admiral audits: a per-team summary.
Minion and targeting probes: use minions_tools\\summ.py and
tools_targeting\\ana.py.
"""
import json, os, re, sys


def load(path, key="AUDIT_JSON "):
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            if line.startswith(key):
                return json.loads(line[len(key):])
    except OSError:
        pass
    return None


def runs(d, prefix):
    out = {}
    for f in os.listdir(d):
        m = re.match(r"(%s[A-Za-z0-9_]*)_seed(\d+)\.txt$" % prefix, f)
        if m:
            j = load(os.path.join(d, f))
            if j:
                out.setdefault(m.group(1), {})[int(m.group(2))] = j["counters"]
    return out


def g(c, k):
    return float(c.get(k, 0.0))


METRICS = [
    ("stuck episodes", lambda c: g(c, "stuck_episodes")),
    ("stuck seconds", lambda c: g(c, "stuck_seconds")),
    ("rock contact ship-s", lambda c: g(c, "rock_contact_ticks") / 60.0),
    ("rock contact while fighting s", lambda c: g(c, "rock_contact_ticks_fighting") / 60.0),
    ("fight samples", lambda c: g(c, "fight_samples")),
    ("occluded fight samples", lambda c: g(c, "occluded")),
    ("occluded while firing", lambda c: g(c, "occluded_firing")),
    ("home, target in reach", lambda c: g(c, "home_target_in_reach")),
    ("big ship hold far", lambda c: g(c, "hold_far")),
    ("hold far, not approaching", lambda c: g(c, "hold_far_not_approaching")),
    ("no route while far", lambda c: g(c, "no_route_far")),
    ("pilot deaths", lambda c: g(c, "pilot_deaths")),
    ("  crash", lambda c: g(c, "death_crash")),
    ("  turret", lambda c: g(c, "death_turret")),
    ("  minion", lambda c: g(c, "death_minion")),
    ("  pilot", lambda c: g(c, "death_pilot")),
    ("  monster", lambda c: g(c, "death_monster")),
    ("  mothership", lambda c: g(c, "death_mothership")),
    ("state flips", lambda c: g(c, "state_flips")),
    ("target switches", lambda c: g(c, "target_switches")),
    ("turret-targeted samples", lambda c: g(c, "turret_targeted_samples")),
    ("samples in state home", lambda c: g(c, "state_home")),
    ("samples in state retreat", lambda c: g(c, "state_retreat")),
    ("samples in state jungle", lambda c: g(c, "state_jungle")),
]


def pilot(d):
    allr = runs(d, "ab")
    allr.update(runs(d, "late"))
    for base in ["ab_base", "late_base"]:
        if base not in allr:
            continue
        pre = base.split("_")[0] + "_"
        for tag in sorted(t for t in allr if t.startswith(pre) and t != base):
            seeds = sorted(set(allr[base]) & set(allr[tag]))
            if not seeds:
                print("%s vs %s: no common seeds yet (%s / %s)" % (tag, base, sorted(allr[base]), sorted(allr[tag])))
                continue
            print("\n== %s vs %s, seeds %s ==" % (tag, base, seeds))
            print("%-32s %10s %10s %8s" % ("metric", base, tag, "change"))
            for name, f in METRICS:
                a = sum(f(allr[base][s]) for s in seeds)
                b = sum(f(allr[tag][s]) for s in seeds)
                ch = ("%+.0f%%" % ((b - a) / a * 100.0)) if a > 0 else ("new" if b > 0 else "")
                print("%-32s %10.0f %10.0f %8s" % (name, a, b, ch))


def admiral(d):
    for f in sorted(os.listdir(d)):
        if not f.endswith(".txt") or "_err" in f or f == "progress.txt":
            continue
        j = load(os.path.join(d, f))
        if not j:
            print("%s: not finished" % f)
            continue
        print("\n== %s: ended %s at t=%s ==" % (f, j.get("phase"), j.get("time")))
        for t, c in enumerate(j["counters"]):
            n = max(1.0, g(c, "samples"))
            share = lambda pre: " ".join("%s=%.0f%%" % (k[len(pre):], v / n * 100) for k, v in sorted(c.items()) if k.startswith(pre))
            print(" T%d push[%s] flips=%d push!=fracfront=%.0f%%" % (t, share("push_"), g(c, "push_flips"), g(c, "push_ne_fracfront") / n * 100))
            print("    fracfront[%s] wp[%s]" % (share("fracfront_"), share("wp_")))
            print("    sieges=%d off=%d gather_s=%d assault_s=%d  ms_moves=%d ms_away_s=%d ms_lane[%s]" % (g(c, "siege_declared"), g(c, "siege_off"), g(c, "siege_s_gather"), g(c, "siege_s_assault"), g(c, "ms_moves"), g(c, "ms_away_s"), share("ms_lane_")))
            print("    treasury avg=%d max=%d over2k=%d s over5k=%d s over10k=%d s  plan steps=%d done_t=%s end_hull=%.2f" % (g(c, "tre_sum") / n, g(c, "tre_max"), g(c, "tre_over_2000_s"), g(c, "tre_over_5000_s"), g(c, "tre_over_10000_s"), len(j["plan_t"][t]), c.get("plan_done_t", "-"), g(c, "end_ms_hull")))
            print("    avg bays=%.1f wards=%.1f turrets=%.1f drones=%.1f bigs=%.1f  bays_made=%d defending_s=%d fleet_edge_s=%d" % (g(c, "bays_sum") / n, g(c, "wards_sum") / n, g(c, "turrets_sum") / n, g(c, "drones_sum") / n, g(c, "bigs_sum") / n, g(c, "bays_made"), g(c, "defending_s"), g(c, "fleet_edge_s")))
            cmds = " ".join("%s=%d" % (k[4:], v) for k, v in sorted(c.items()) if k.startswith("cmd_"))
            fails = "; ".join("%s x%d" % (k[5:], v) for k, v in sorted(c.items()) if k.startswith("fail_"))
            print("    orders: %s" % cmds)
            if fails:
                print("    failed: %s" % fails)
        evs = [e for e in j["events"] if e[2] != "bay"]
        print(" events:", "; ".join("%s T%d %s %s" % (e[0], e[1], e[2], e[3]) for e in evs[:40]))
        bays = [e for e in j["events"] if e[2] == "bay"]
        print(" bays:", "; ".join("%s T%d %s" % (e[0], e[1], e[3]["lane"]) for e in bays[:20]))


FILTER = ""


def matrix(d):
    """One compact table per base: rows = metrics, columns = fix tags,
    cells = base>fix summed over the seeds both have (seeds in the header)."""
    allr = runs(d, "ab")
    allr.update(runs(d, "late"))
    for base in ["ab_base", "late_base"]:
        if base not in allr:
            continue
        pre = base.split("_")[0] + "_"
        tags = sorted(t for t in allr if t.startswith(pre) and t != base and re.search(FILTER, t))
        cols = []
        for tag in tags:
            seeds = sorted(set(allr[base]) & set(allr[tag]))
            if seeds:
                cols.append((tag, seeds))
        print("\n== vs %s (cells: base>fix, summed over the paired seeds) ==" % base)
        print("%-24s" % "metric" + "".join("%15s" % t[len(pre):] for t, _ in cols))
        print("%-24s" % "seeds" + "".join("%15s" % ",".join(str(s) for s in ss) for _, ss in cols))
        for name, f in METRICS:
            cells = []
            for tag, seeds in cols:
                a = sum(f(allr[base][s]) for s in seeds)
                b = sum(f(allr[tag][s]) for s in seeds)
                cells.append("%15s" % ("%d>%d" % (round(a), round(b))))
            print("%-24s" % name[:24] + "".join(cells))


if __name__ == "__main__":
    if sys.argv[1] == "--matrix":
        FILTER = sys.argv[3] if len(sys.argv) > 3 else ""
        matrix(sys.argv[2])
        sys.exit(0)
    pilot(sys.argv[1])
    if len(sys.argv) > 2 and os.path.isdir(sys.argv[2]):
        admiral(sys.argv[2])

