"""Scores a batch of fun-probe matches: the FUN score of docs/FUN_RESEARCH.md.

WHAT THIS IS: a command-line tool that reads the FUN_JSON lines printed by
tests/fun_probe.gd (one per match) in a folder of logs, plus the DUEL_JSON
line of tests/arena_matrix.gd if one is there, and works out every
ingredient score and the FUN total (0-100) exactly as the research's "Fun
score formula" says. With --vs it compares two folders seed by seed and
says how sure we can be that one really scores higher.

HOW TO RUN IT (from the remake folder; it needs only Python itself):
    python tools/fun_score.py --dir <folder>
    python tools/fun_score.py --dir <new folder> --vs <baseline folder>
Options:
    --dir FOLDER      the logs to score (every file in it is read)
    --vs FOLDER       a second batch to compare against: differences are
                      "dir minus vs", with seeds matched by number
    --resamples N     bootstrap rounds (default 2,000)
    --seed N          the bootstrap's random seed (default 20261015), so the
                      same folders always give the same bounds
    --at30            score the 30:00 snapshots: read the FUN_JSON30 lines
                      (printed by tests/fun_probe.gd when a normal match
                      reaches 30:00) instead of FUN_JSON, in --dir and in
                      --vs. A log without such a line counts when its final
                      FUN_JSON already is a 30:00 result (the match ended
                      before 30:00, or the run was stopped at 30:00 with
                      --secs=1800); any other log is skipped with a note
                      (a full match made before the snapshot existed)
    --vs-at30         the same, for the --vs folder only (the baseline)

30:00 SCREENS (docs/FUN_PLAN.md section 4.3): an idea whose target is
measured by 30:00 is run in matches capped at 30:00 (--secs=1800), so their
final FUN_JSON IS a 30:00 result and plain fun_score scores them (a folder
whose runs all have secs_cap 1800 is labelled "30:00 results"). Baseline
v2 runs full 60-minute matches, so take its state at 30:00 from FUN_JSON30:
  (a) a 30-minute screen folder against the baseline's 30:00 snapshot:
      python tools/fun_score.py --dir <screen folder> --vs <baseline folder> --vs-at30
  (b) a full baseline folder on its own, at 30:00:
      python tools/fun_score.py --dir <baseline folder> --at30
  (c) two full-match folders compared at 30:00:
      python tools/fun_score.py --dir <folder> --vs <baseline folder> --at30
A 30:00 result has barely seen how the match ends, so read the early-game
ingredients (S4-S9); S1-S3 (how the match ends) say little at 30:00.
fun_score flags a comparison of 30:00 results with full-match results (it is
not meaningful).

HOW IT WORKS:
  1. Read both folders (fun_lib.read_dir; with --at30 / --vs-at30 the
     FUN_JSON30 snapshots) and split the matches into normal runs and --late
     runs (started at 25:00); each kind is scored on its own (--late runs
     only on the parts the research allows for them).
  2. Score each batch (fun_lib.score_batch): per-seed sub-metrics are scored
     per match and averaged, pooled rates are pooled first and scored once,
     the arena numbers come from DUEL_JSON. A sub-metric that can't be
     measured is dropped and listed. With --vs, only sub-metrics BOTH
     batches measured are scored, so the two totals are comparable.
  3. With --vs: the paired bootstrap (fun_lib.paired_bootstrap) redraws the
     matched seeds 2,000 times. The 10th and 5th percentiles of the FUN
     differences are the one-sided 90% and 95% lower bounds (above 0 = the
     first folder is better with that confidence); the 10th to 90th
     percentiles of each ingredient's differences are its 80% interval.
  4. Print a readable table, then one machine-readable line:
     SCORE_JSON {...} (the same numbers, for other tools).

WHO USES IT: the fun experiments (docs/FUN_PLAN.md): screens, fork
combinations against baseline v2, and the council's final check. The
formula, curves and statistics live in tools/fun_lib.py.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fun_lib  # noqa: E402  (the shared parts; see tools/fun_lib.py)


def fmt(x, width=7, digits=1, sign=False):
    """A number as fixed-width text (or "-" for None), for the table."""
    if x is None:
        return "-".rjust(width)
    return f"{x:+.{digits}f}".rjust(width) if sign else f"{x:.{digits}f}".rjust(width)


def fmt_value(x):
    """A raw sub-metric value as short text: 3 significant digits, or "-"."""
    if x is None:
        return "-"
    return f"{x:.3g}" if abs(x) < 1000 else f"{x:.0f}"


def rounded(obj):
    """A copy of `obj` (dicts, lists, numbers) with floats rounded to 3
    decimals, for SCORE_JSON."""
    if isinstance(obj, float):
        return round(obj, 3)
    if isinstance(obj, dict):
        return {k: rounded(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [rounded(v) for v in obj]
    return obj


def load(path, at30=False):
    """Read folder `path`: returns ({"normal": {seed: record}, "late":
    {...}}, the DUEL_JSON dictionary or None, notes). With `at30` the
    records are 30:00 results (see fun_lib.read_dir)."""
    if not os.path.isdir(path):
        sys.exit(f"fun_score: no such folder: {path}")
    records, duel, notes = fun_lib.read_dir(path, at30)
    if not records:
        notes.append(f"no {'FUN_JSON30' if at30 else 'FUN_JSON'} lines in {path}")
    return fun_lib.by_mode_and_seed(records, notes), duel, notes


def kind_at_30(recs, at30):
    """Are the records `recs` (a list) 30:00 results: read with --at30 (or
    --vs-at30), or all made to stop at 30:00 (--secs=1800 runs)? Returns
    "" if not, else a short label for the table."""
    if at30:
        return "30:00 snapshots (FUN_JSON30)"
    if recs and all(fun_lib.is_capped_at_30(r) for r in recs):
        return "30:00 results (runs stopped at 30:00)"
    return ""


def score_group(mode, recs_a, duel_a, recs_b, duel_b, resamples, seed):
    """Score one kind of run ("normal" or "late") of folder A, and compare
    with folder B if `recs_b` is given (else None). A comparison uses only
    the seeds both folders have (a paired comparison); the others are
    listed as unmatched. Returns a result dictionary with everything the
    table and SCORE_JSON need."""
    subset = fun_lib.LATE_SUBSET if mode == "late" else None
    arena_a = duel_a if mode == "normal" else None
    arena_b = duel_b if mode == "normal" else None
    out = {"mode": mode, "dropped_vs": [], "unmatched": [], "no_match": False}
    # Step 1: with a second folder, keep only the seeds both have.
    if recs_b:
        matched = sorted(set(recs_a) & set(recs_b))
        out["unmatched"] = sorted(set(recs_a) ^ set(recs_b))
        if matched:
            recs_a = {s: recs_a[s] for s in matched}
            recs_b = {s: recs_b[s] for s in matched}
        else:
            out["no_match"] = True
            recs_b = None
    out["seeds"] = sorted(recs_a)
    # Step 2: work out each match's pieces once, then score the whole batch
    # to see which sub-metrics can be measured.
    pres_a = {s: fun_lib.precompute(r) for s, r in recs_a.items()}
    full_a = fun_lib.score_batch(list(pres_a.values()), arena_a, subset)
    allowed = fun_lib.measurable(full_a)
    pres_b, full_b = None, None
    # Step 3: with a second batch, keep only what both could measure.
    if recs_b:
        pres_b = {s: fun_lib.precompute(r) for s, r in recs_b.items()}
        full_b = fun_lib.score_batch(list(pres_b.values()), arena_b, subset)
        both = allowed & fun_lib.measurable(full_b)
        out["dropped_vs"] = sorted((allowed | fun_lib.measurable(full_b)) - both)
        allowed = both
        full_a = fun_lib.score_batch(list(pres_a.values()), arena_a, subset, allowed)
        full_b = fun_lib.score_batch(list(pres_b.values()), arena_b, subset, allowed)
    out["a"] = full_a
    out["info"] = fun_lib.batch_info(list(recs_a.values()))
    # The sub-metrics that could not be measured: score_batch leaves out
    # everything outside `allowed`, so name them here.
    all_keys = [k for ing, subs in fun_lib.METRICS.items() for k, *_r in subs if fun_lib.subset_allows(subset, ing, k)]
    out["not_measured"] = sorted(k for k in all_keys if k not in allowed and k not in out["dropped_vs"])
    out["arena_missing"] = mode == "normal" and arena_a is None
    if full_b is None:
        return out
    # Step 4: the comparison: point differences and the paired bootstrap
    # over the matched seeds.
    out["b"] = full_b
    out["info_b"] = fun_lib.batch_info(list(recs_b.values()))
    matched = sorted(pres_a)
    out["matched"] = matched
    out["diff"] = {"fun": None if full_a["fun"] is None or full_b["fun"] is None else full_a["fun"] - full_b["fun"]}
    for ing, _n, _w in fun_lib.INGREDIENTS:
        a, b = full_a["ingredients"][ing]["score"], full_b["ingredients"][ing]["score"]
        out["diff"][ing] = None if a is None or b is None else a - b
    out["boot"] = None
    if len(matched) >= 2:
        diffs = fun_lib.paired_bootstrap(pres_a, pres_b, arena_a, arena_b, subset, allowed,
                                         fun_lib.sub_scores(full_a), fun_lib.sub_scores(full_b), resamples, seed)
        p = fun_lib.percentile
        out["boot"] = {
            "resamples": resamples,
            "lb90": p(diffs["fun"], 0.10),
            "lb95": p(diffs["fun"], 0.05),
            "ci80": {k: [p(v, 0.10), p(v, 0.90)] if v else None for k, v in diffs.items()},
        }
    return out


def print_group(g, dir_a, dir_b):
    """Print the readable table of one scored group `g` (from score_group).
    `g["kind30"]` (set by main) holds the labels of the two sides: "" for
    full matches, else a label for 30:00 results (see kind_at_30)."""
    a, b = g["a"], g.get("b")
    info = g["info"]
    kind_a, kind_b = g.get("kind30", ("", ""))
    bar = "=" * 96
    print(bar)
    print(f"FUN SCORE  ({g['mode']} runs{', started at 25:00' if g['mode'] == 'late' else ''}{', 30:00 results' if kind_a else ''})")
    print(f"  folder : {dir_a}" + (f"   [{kind_a}]" if kind_a else ""))
    print(f"  seeds  : {', '.join(str(s) for s in g['seeds'])}  ({info['matches']} matches, {info['ended']} ended,"
          f" Halcyon won {fmt_value(info['halcyon_win_rate'])} of ended, damage hook {info['damage_hook']}/{info['matches']},"
          f" skill jitter {info['skill_jitter']}/{info['matches']})")
    if b is not None:
        print(f"  vs     : {dir_b}" + (f"   [{kind_b}]" if kind_b else ""))
        print(f"  both folders are scored on the {len(g['matched'])} seeds they share (a paired comparison)"
              + (f"; left out, in one folder only: {', '.join(str(s) for s in g['unmatched'])}" if g["unmatched"] else ""))
    elif g.get("no_match"):
        print("  FLAG: the --vs folder has no seed in common with this one, so this folder is scored alone")
    print("-" * 96)
    head = f"{'':5}{'ingredient / sub-metric':34}{'w':>3} {'n':>3} {'value':>8} {'curve':<22}{'score':>6}"
    if b is not None:
        head += f" {'vs':>6} {'diff':>6}  80% interval"
    print(head)
    # One line per ingredient, then one per sub-metric.
    for ing, name, weight in fun_lib.INGREDIENTS:
        ia = a["ingredients"][ing]
        if not ia["subs"]:
            continue
        line = f"{ing:5}{name:34}{weight:>3} {'':>3} {'':>8} {'':<22}{fmt(ia['score'], 6)}"
        if b is not None:
            ci = (g["boot"] or {}).get("ci80", {}).get(ing) if g.get("boot") else None
            line += f" {fmt(b['ingredients'][ing]['score'], 6)} {fmt(g['diff'][ing], 6, 1, True)}"
            line += f"  [{fmt(ci[0], 6, 1, True)}, {fmt(ci[1], 6, 1, True)}]" if ci else "  -"
        print(line)
        for key, s in ia["subs"].items():
            sub = f"{'':7}{key:32}{s['kind']:>5} {s['n']:>3} {fmt_value(s['value']):>8} {s['curve']:<22}{fmt(s['score'], 6)}"
            if b is not None:
                sb = b["ingredients"][ing]["subs"].get(key, {})
                sub += f" {fmt(sb.get('score'), 6)}   (vs value {fmt_value(sb.get('value'))})"
            print(sub)
    print("-" * 96)
    # The total, and with --vs the bounds.
    line = f"{'FUN':5}{'(weighted total, 0-100)':34}{'':>3} {'':>3} {'':>8} {'':<22}{fmt(a['fun'], 6)}"
    if b is not None:
        line += f" {fmt(b['fun'], 6)} {fmt(g['diff']['fun'], 6, 1, True)}"
        boot = g.get("boot")
        if boot:
            line += f"  LB90 {fmt(boot['lb90'], 5, 1, True)}  LB95 {fmt(boot['lb95'], 5, 1, True)}  ({boot['resamples']} paired resamples)"
        else:
            line += "  (fewer than 2 matched seeds: no bootstrap)"
    print(line)
    # Facts beside the score, and every flag. For 30:00 results the match
    # length (unended = 60 min) means nothing: say how many had ended.
    if kind_a:
        print(f"  30:00 results: {info['ended']} of {info['matches']} matches had already ended; the others were still"
              f" running (the match length facts of full matches do not apply)")
        print("  NOTE: a 30:00 result has barely seen how a match ends, so read the early-game ingredients (S4-S9);"
              " S1-S3 (how the match ends) say little at 30:00")
    else:
        print(f"  match length (unended = 60 min): median {fmt_value(info['minutes_median'])}, IQR"
              f" {fmt_value((info['minutes_iqr'] or [None])[0])}-{fmt_value((info['minutes_iqr'] or [None, None])[1])},"
              f" p90 {fmt_value(info['minutes_p90'])}; ended under 20 min {fmt_value(info['under_20_min'])}")
    if b is not None and bool(kind_a) != bool(kind_b):
        print("  FLAG: one folder holds 30:00 results and the other full matches, which is not a fair comparison;"
              " read the full-match folder at 30:00 with --at30 (or --vs-at30 for the --vs folder)")
    print(f"  AUC of sign(A) for the winner at 15/20/25 min: main {', '.join(fmt_value(info['auc'][m]) for m in ('15', '20', '25'))};"
          f" alt {', '.join(fmt_value(info['auc_alt'][m]) for m in ('15', '20', '25'))}")
    if info["usage"]:
        print(f"  usage (summed): {json.dumps(info['usage'], sort_keys=True)}")
    if g["arena_missing"]:
        print("  FLAG: no DUEL_JSON in the folder: the arena sub-metrics (duel_skill_winrate, arena_small_winrate)"
              " are missing; run tests/arena_matrix.gd for this build and put its log in the folder")
    if g["not_measured"]:
        print(f"  FLAG: not measured in these runs, dropped from their ingredient: {', '.join(g['not_measured'])}")
    if g["dropped_vs"]:
        print(f"  FLAG: measured in only one batch, dropped from both so they compare: {', '.join(g['dropped_vs'])}")
    if 1 in info["probe_versions"]:
        print("  FLAG: some logs are fun probe v1 (no v2 numbers): only the v1 sub-metrics can be scored")
    tw = sum(w for ing, _n, w in fun_lib.INGREDIENTS if a["ingredients"][ing]["score"] is not None)
    if tw and tw < 100 and g["mode"] == "normal":
        print(f"  FLAG: FUN uses ingredients with {tw} of the 100 weight points (the rest could not be scored)")


def main():
    """Read the options, score the folder(s), print the table(s) and the
    SCORE_JSON line."""
    ap = argparse.ArgumentParser(description="FUN score of a folder of fun_probe logs (docs/FUN_RESEARCH.md).")
    ap.add_argument("--dir", required=True, help="folder of logs to score")
    ap.add_argument("--vs", help="folder to compare against (differences are dir minus vs)")
    ap.add_argument("--resamples", type=int, default=2000, help="bootstrap rounds (default 2000)")
    ap.add_argument("--seed", type=int, default=20261015, help="the bootstrap's random seed")
    ap.add_argument("--at30", action="store_true", help="30:00 snapshots: read the FUN_JSON30 lines (both folders)")
    ap.add_argument("--vs-at30", action="store_true", help="30:00 snapshots for the --vs folder only (the baseline)")
    args = ap.parse_args()
    if args.vs_at30 and not args.vs:
        ap.error("--vs-at30 needs --vs")
    at30_a = args.at30
    at30_b = args.at30 or args.vs_at30
    # Step 1: read the folder(s).
    groups_a, duel_a, notes = load(args.dir, at30_a)
    groups_b, duel_b = {"normal": {}, "late": {}}, None
    if args.vs:
        groups_b, duel_b, notes_b = load(args.vs, at30_b)
        notes += [f"(vs) {n}" for n in notes_b]
    for n in notes:
        print(f"note: {n}")
    # Step 2: score each kind of run that folder A has, print its table.
    # Normal runs may be 30:00 results (read with --at30, or stopped at
    # 30:00); --late runs never are.
    out = {"tool": "fun_score", "version": 1, "dir": args.dir, "vs": args.vs, "groups": {}}
    if at30_a or at30_b:
        out["at30"] = {"dir": at30_a, "vs": at30_b if args.vs else False}
    for mode in ("normal", "late"):
        if not groups_a[mode]:
            continue
        recs_b = groups_b[mode] if args.vs else None
        g = score_group(mode, groups_a[mode], duel_a, recs_b, duel_b, args.resamples, args.seed)
        if mode == "normal":
            g["kind30"] = (kind_at_30(list(groups_a[mode].values()), at30_a),
                           kind_at_30(list((recs_b or {}).values()), at30_b) if recs_b else "")
        print_group(g, args.dir, args.vs)
        out["groups"][mode] = summary_json(g)
    # Step 3: the machine-readable line.
    print("SCORE_JSON " + json.dumps(rounded(out), sort_keys=True))


def summary_json(g):
    """The SCORE_JSON part of one scored group `g`: seeds, FUN, every
    ingredient and sub-metric, the flags, and with --vs the comparison."""
    def ings(result):
        return {ing: {"score": v["score"], "weight": v["weight"],
                      "subs": {k: {"value": s["value"], "score": s["score"], "n": s["n"], "kind": s["kind"]} for k, s in v["subs"].items()}}
                for ing, v in result["ingredients"].items() if v["subs"]}
    out = {"seeds": g["seeds"], "fun": g["a"]["fun"], "ingredients": ings(g["a"]), "info": g["info"],
           "not_measured": g["not_measured"], "arena_missing": g["arena_missing"]}
    # Only for 30:00 results, so the SCORE_JSON of full matches is unchanged.
    kind_a, kind_b = g.get("kind30", ("", ""))
    if kind_a or kind_b:
        out["results_at_30"] = {"dir": bool(kind_a), "vs": bool(kind_b)}
    if g.get("b") is not None:
        out["vs"] = {"seeds": g["matched"], "unmatched": g["unmatched"], "fun": g["b"]["fun"], "ingredients": ings(g["b"]),
                     "diff": g["diff"], "dropped_vs": g["dropped_vs"], "bootstrap": g["boot"]}
    return out


if __name__ == "__main__":
    main()
