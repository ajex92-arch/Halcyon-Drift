"""The shared parts of tools/fun_score.py: reading the logs, the score
curves, the small statistics, and the FUN formula itself.

WHAT THIS IS: everything fun_score.py needs to turn FUN_JSON lines (printed
by tests/fun_probe.gd, one per match) and a DUEL_JSON line (printed by
tests/arena_matrix.gd, once per build) into the FUN score of
docs/FUN_RESEARCH.md ("Fun score formula"): eleven "ingredient" scores from
0 to 100 and their weighted total, FUN, also 0 to 100.

HOW IT WORKS:
  1. read_dir() finds every FUN_JSON and DUEL_JSON line in the files of a
     folder and turns each into a Python dictionary (a "record"). With
     at30=True it reads the FUN_JSON30 lines instead (the snapshot that
     tests/fun_probe.gd prints when a normal match reaches 30:00), so a
     full 60-minute baseline can be compared with matches capped at 30:00
     (--secs=1800). A log without a FUN_JSON30 line still counts as a 30:00
     result when its final FUN_JSON is one: the match ended before 30:00, or
     the run was capped at 30:00 (made before the snapshot existed).
  2. Each ingredient is made of "sub-metrics". A sub-metric is one of:
       seed   measured per match (per seed), scored per match with its
              curve, and the scores averaged over the matches;
       pool   a rate or ratio pooled over all matches first (for example
              all siege bites / all sieges), then scored once;
       arena  read from the DUEL_JSON line (one number per build).
     METRICS (below) lists every sub-metric with its curve, exactly as the
     research's formula gives them.
  3. A curve turns a raw number into 0..100 points:
       T(a, b, c, d)  a trapezoid: 0 at or below a, rising in a straight
                      line to 100 at b, 100 from b to c, falling to 0 at d;
       low(c, d)      lower is better: 100 at or below c, 0 at or above d;
       high(a, b)     higher is better: 0 at or below a, 100 at or above b.
  4. An ingredient's score is the mean of its sub-metric scores (ingredient
     4 uses fixed weights 0.4 / 0.2 / 0.2 / 0.2). FUN = sum(weight x
     ingredient score) / sum(weights); the weights add up to 100. A
     sub-metric that can't be measured (no data, such as no big-ship deaths)
     is dropped from its ingredient's mean and reported. Runs started at
     25:00 ("--late") are scored on their own, with only the parts that can
     be measured from 25:00 on (LATE_SUBSET: S1, S2, S5-late, S6-late and S10).
  5. paired_bootstrap() compares two batches: it draws the matched seed
     numbers again and again at random (with repeats), scores both batches
     on each draw, and keeps the differences. The low end of those
     differences gives "lower bounds": a 90% lower bound above 0 means we
     are about 90% sure the first batch really scores higher.
Every function has a docstring; the comments walk through the steps.

WHO USES IT: tools/fun_score.py (import fun_lib). It needs nothing but
Python's standard library.
"""
import json
import math
import os
import random
import re

# --- the formula's weights and names ----------------------------------------

# The eleven scored ingredients: key, name, weight (they add up to 100).
INGREDIENTS = [
    ("S1", "Decisive match arc", 12),
    ("S2", "Endgame arc", 10),
    ("S3", "Suspense and comebacks", 13),
    ("S4", "Low downtime", 12),
    ("S5", "Skirmish ramps into battle", 11),
    ("S6", "Pilots decide fights", 10),
    ("S7", "Skill and readable TTK", 9),
    ("S8", "Both sizes needed", 8),
    ("S9", "Economy reflects play", 6),
    ("S10", "Admiral matters", 5),
    ("S11", "Teamwork", 4),
]

# The parts that a --late run (starting at 25:00) is scored on
# (FUN_RESEARCH.md protocol: "only S1-from-25:00, S2, S5-late and S6-late
# apply", plus S10, added because the admiral fork screens its ideas with
# late runs). None = every sub-metric of that ingredient; a list = only
# those. S1 uses the full match clock (it starts at 25:00); S5-late and
# S6-late are read as their late-only sub-metrics. S10 keeps all three of its
# sub-metrics, because none of them needs the opening: late_spend_ratio and
# admiral_decisions_per_min_late are counted from 30:00 on (so they are
# missing, and dropped, in a run that stops before 30:00), and
# asset_kill_share is the share of the pilot kills in the watch, which in a
# late run are all after 25:00.
LATE_SUBSET = {
    "S1": None,
    "S2": None,
    "S5": ["fight_p90_late"],
    "S6": ["pilot_kill_share_late"],
    "S10": ["late_spend_ratio", "admiral_decisions_per_min_late", "asset_kill_share"],
}


# --- reading the logs ---------------------------------------------------------

# The match time (minutes) of the snapshot line FUN_JSON30, and how far from
# it a final FUN_JSON may be and still count as a 30:00 result (the probe's
# last tick can end a hair after the cap).
SNAPSHOT_MIN = 30.0
SNAPSHOT_TOL = 0.1


def is_result_at_30(rec):
    """Is the final FUN_JSON `rec` already a 30:00 result? True for a normal
    (not --late) match that ended at or before 30:00 (nothing more happens
    after it), or that was stopped at 30:00 (a --secs=1800 run). Used by
    read_dir(at30=True) for logs without a FUN_JSON30 line."""
    if rec.get("late_start"):
        return False
    m = num(rec.get("minutes"))
    if m is None:
        return False
    if rec.get("ended"):
        return m <= SNAPSHOT_MIN + SNAPSHOT_TOL
    return abs(m - SNAPSHOT_MIN) <= SNAPSHOT_TOL


def is_capped_at_30(rec):
    """Was `rec` (a FUN_JSON or FUN_JSON30 record) made to stop at 30:00, as
    in a --secs=1800 run or a FUN_JSON30 snapshot (its "secs_cap" is 1800)?
    Never true for a --late run."""
    return not rec.get("late_start") and rec.get("secs_cap") == int(SNAPSHOT_MIN * 60)


def read_dir(path, at30=False):
    """Read every file in folder `path` (not its sub-folders) and return
    (records, duel, notes): `records` is a list of FUN_JSON dictionaries
    (each gets "_file", the file it came from), `duel` the last DUEL_JSON
    dictionary found (or None), and `notes` a list of warnings.
    With `at30` the records are 30:00 results instead: the FUN_JSON30 lines
    of each file; a file with none gives its final FUN_JSON if that already
    is a 30:00 result (see is_result_at_30), else it is skipped with a note
    (for example a full baseline match made before the snapshot existed).
    One note counts where the records came from."""
    records, duel, notes = [], None, []
    from_snap, from_final, skipped = 0, 0, []
    tags = ("FUN_JSON30 ", "FUN_JSON ", "DUEL_JSON ") if at30 else ("FUN_JSON ", "DUEL_JSON ")
    for name in sorted(os.listdir(path)):
        full = os.path.join(path, name)
        if not os.path.isfile(full):
            continue
        snaps, finals = [], []
        # Godot's output may be in any encoding; bad bytes are replaced.
        with open(full, encoding="utf-8", errors="replace") as f:
            for line in f:
                for tag in tags:
                    i = line.find(tag)
                    if i < 0:
                        continue
                    try:
                        data = json.loads(line[i + len(tag):])
                    except ValueError:
                        notes.append(f"{name}: a {tag.strip()} line is not valid JSON (skipped)")
                        continue
                    if tag == "DUEL_JSON ":
                        duel = data
                    else:
                        data["_file"] = name
                        (snaps if tag == "FUN_JSON30 " else finals).append(data)
        # Without --at30 every FUN_JSON line is a record; with it, the
        # snapshots are, or else a final result that already is one.
        if not at30:
            records += finals
        elif snaps:
            records += snaps
            from_snap += len(snaps)
        else:
            usable = [r for r in finals if is_result_at_30(r)]
            records += usable
            from_final += len(usable)
            if finals and not usable:
                skipped.append(name)
    if at30:
        notes.append(f"--at30: {from_snap + from_final} logs read as 30:00 results ({from_snap} from FUN_JSON30 lines,"
                     f" {from_final} from a final FUN_JSON of a match that ended or was stopped by 30:00)")
        for name in skipped:
            notes.append(f"{name}: no FUN_JSON30 line, and its FUN_JSON is not a 30:00 result (the match neither ended by 30:00"
                         f" nor was stopped at 30:00): skipped; a full match needs the current tests/fun_probe.gd")
    return records, duel, notes


def seed_of(rec, fallback):
    """The seed number of record `rec`: its "seed" field, or the last number
    in its file name (v1 logs such as "seed_12.txt" have no seed field), or
    `fallback`."""
    s = rec.get("seed")
    if isinstance(s, int) and s >= 0:
        return s
    nums = re.findall(r"\d+", rec.get("_file", ""))
    return int(nums[-1]) if nums else fallback


def by_mode_and_seed(records, notes):
    """Split `records` into {"normal": {seed: record}, "late": {seed:
    record}}. A seed seen twice in one mode keeps the later file and adds a
    note to `notes`."""
    out = {"normal": {}, "late": {}}
    for i, rec in enumerate(records):
        mode = "late" if rec.get("late_start") else "normal"
        s = seed_of(rec, -1 - i)
        if s in out[mode]:
            notes.append(f"seed {s} ({mode}) appears twice; using {rec['_file']}")
        out[mode][s] = rec
    return out


# --- curves and small statistics ------------------------------------------------

def trap(x, a, b, c, d):
    """The trapezoid curve T(a, b, c, d) at `x` (see HOW IT WORKS), 0..100."""
    if x <= a or x >= d:
        return 0.0
    if x < b:
        return 100.0 * (x - a) / (b - a)
    if x <= c:
        return 100.0
    return 100.0 * (d - x) / (d - c)


def low(x, c, d):
    """Lower is better: 100 at or below `c`, 0 at or above `d`, a straight
    line between."""
    if x <= c:
        return 100.0
    if x >= d:
        return 0.0
    return 100.0 * (d - x) / (d - c)


def high(x, a, b):
    """Higher is better: 0 at or below `a`, 100 at or above `b`, a straight
    line between."""
    if x <= a:
        return 0.0
    if x >= b:
        return 100.0
    return 100.0 * (x - a) / (b - a)


def curve_text(curve):
    """A curve as short text, such as "T(18,28,42,58)" or "low(0.3,0.45)"."""
    return f"{curve[0]}({','.join(f'{v:g}' for v in curve[1:])})"


def apply_curve(curve, x):
    """Score number `x` with `curve`, a tuple like ("T", a, b, c, d),
    ("low", c, d) or ("high", a, b)."""
    kind = curve[0]
    if kind == "T":
        return trap(x, *curve[1:])
    if kind == "low":
        return low(x, *curve[1:])
    return high(x, *curve[1:])


def mean(xs):
    """The average of `xs`, or None for an empty list."""
    return sum(xs) / len(xs) if xs else None


def percentile(xs, q):
    """The `q`-th percentile of `xs` (q from 0 to 1), with a straight line
    between the two neighbouring values, the same rule as
    tests/lib/fun_stats.gd. None for an empty list."""
    if not xs:
        return None
    s = sorted(xs)
    pos = q * (len(s) - 1)
    lo = int(math.floor(pos))
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)


def ratio(num, den):
    """`num` / `den`, or None when `den` is 0 (nothing to divide by)."""
    return num / den if den else None


def num(x):
    """`x` if it is a real number (not None, not True/False), else None."""
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return None
    return float(x)


def get(rec, *path):
    """Look up a nested value: get(rec, "time_share", "travel") is
    rec["time_share"]["travel"], or None if anything on the way is
    missing."""
    cur = rec
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


# --- the sub-metrics ----------------------------------------------------------------
# Per-seed sub-metrics: fn(record) -> (raw value, score) or None.
# Pooled sub-metrics: parts(record) -> a piece of data or None, and
# combine(list of pieces) -> the pooled value or None.

def seed_metric(path, curve, never_zero=False, ended_only=False, fallback=None):
    """Make the function of a per-seed sub-metric that reads the number at
    `path` (a key or a tuple of keys) and scores it with `curve`.
    `never_zero`: a value below 0 means "never happened" and scores 0.
    `ended_only`: only matches that ended count. `fallback`: another path to
    try when the first is missing (v1 logs)."""
    keys = path if isinstance(path, tuple) else (path,)

    def fn(rec):
        if ended_only and not rec.get("ended"):
            return None
        v = num(get(rec, *keys))
        if v is None and fallback is not None:
            v = num(get(rec, *fallback))
        if v is None:
            return None
        if never_zero and v < 0:
            return (v, 0.0)
        if ended_only and v < 0:
            return None
        return (v, apply_curve(curve, v))
    return fn


def minutes_metric(rec):
    """S1's per-seed match length: T(18, 28, 42, 58) of the minutes, but an
    unended match scores 0."""
    v = num(rec.get("minutes"))
    if v is None:
        return None
    return (v, apply_curve(("T", 18, 28, 42, 58), v) if rec.get("ended") else 0.0)


def sum_ratio(num_key, den_key, only=None):
    """Make the (parts, combine) pair of a pooled ratio: the sum of
    `num_key` over the matches divided by the sum of `den_key`. `only`
    (optional) picks which records take part."""
    def parts(rec):
        if only is not None and not only(rec):
            return None
        n, d = num(rec.get(num_key)), num(rec.get(den_key))
        if n is None or d is None:
            return None
        return (n, d)

    def combine(items):
        return ratio(sum(p[0] for p in items), sum(p[1] for p in items))
    return parts, combine


def flag_share(key, only=None):
    """Make the (parts, combine) pair of a pooled share of matches where the
    true/false field `key` is true (matches where it is null don't count)."""
    def parts(rec):
        v = rec.get(key)
        if not isinstance(v, bool) or (only is not None and not only(rec)):
            return None
        return 1.0 if v else 0.0

    def combine(items):
        return mean(items)
    return parts, combine


def median_of(key):
    """Make the (parts, combine) pair of "the median over seeds" of the
    per-seed number `key` (skill_rho_small)."""
    def parts(rec):
        return num(rec.get(key))

    def combine(items):
        return percentile(items, 0.5)
    return parts, combine


def size_parity_parts(rec):
    """size_parity's piece of one match: (small impact, small minutes, big
    impact, big minutes)."""
    si = num(get(rec, "size_impact", "small", "impact"))
    sm = num(get(rec, "size_impact", "small", "minutes"))
    bi = num(get(rec, "size_impact", "big", "impact"))
    bm = num(get(rec, "size_impact", "big", "minutes"))
    if None in (si, sm, bi, bm):
        return None
    return (si, sm, bi, bm)


def size_parity_combine(items):
    """|log2(I_small / I_big)| with each I = pooled impact per pilot-minute
    of that size; None when either side has no minutes or no impact."""
    rs = ratio(sum(p[0] for p in items), sum(p[1] for p in items))
    rb = ratio(sum(p[2] for p in items), sum(p[3] for p in items))
    if not rs or not rb:
        return None
    return abs(math.log2(rs / rb))


def pos_gap_parts(rec):
    """big_pos_gap's piece of one match: (isolated TTKs, supported TTKs)."""
    iso, sup = rec.get("ttk_big_isolated"), rec.get("ttk_big_supported")
    if not isinstance(iso, list) or not isinstance(sup, list):
        return None
    return (iso, sup)


def pos_gap_combine(items):
    """The median TTK of all isolated big-ship deaths divided by that of all
    supported ones; None if either list is empty."""
    iso = [t for p in items for t in p[0]]
    sup = [t for p in items for t in p[1]]
    mi, ms = percentile(iso, 0.5), percentile(sup, 0.5)
    if mi is None or not ms:
        return None
    return mi / ms


def ended_with_hook(rec):
    """Only ended matches that had the per-hit event (ms_big_damage_share)."""
    return bool(rec.get("ended")) and bool(rec.get("damage_hook"))


def ended(rec):
    """Only matches that ended (a mothership died)."""
    return bool(rec.get("ended"))


# Every sub-metric, by ingredient: (key, kind, curve, how, weight). For
# "seed" `how` is fn(record); for "pool" it is (parts, combine); for
# "arena" it is the DUEL_JSON key. `weight` is only used by S4.
METRICS = {
    "S1": [
        ("minutes", "seed", ("T", 18, 28, 42, 58), minutes_metric, 1),
    ],
    "S2": [
        ("ms_pressure_onset_min", "seed", ("T", 15, 22, 34, 46), None, 1),
        ("final_push_secs", "seed", ("T", 45, 120, 420, 900), None, 1),
        ("ms_limbo_secs", "seed", ("low", 180, 900), None, 1),
        ("siege_bite_rate", "pool", ("T", 0.10, 0.35, 0.70, 0.95), sum_ratio("siege_bites", "siege_assaults"), 1),
        ("ms_big_damage_share", "pool", ("high", 0.30, 0.60), sum_ratio("ms_loser_big_dmg", "ms_loser_hull_dmg", ended_with_hook), 1),
    ],
    "S3": [
        ("adv_lead_changes", "seed", ("T", 0, 2, 5, 9), None, 1),
        ("comeback15", "pool", ("T", 0.05, 0.20, 0.35, 0.50), flag_share("comeback15", ended), 1),
        ("even15", "pool", ("T", 0.10, 0.30, 0.50, 0.75), flag_share("even15"), 1),
        ("decided_to_end_min", "seed", ("low", 8, 20), None, 1),
    ],
    "S4": [
        ("travel", "seed", ("low", 0.30, 0.45), None, 0.4),
        ("dead", "seed", ("T", 0.02, 0.05, 0.13, 0.22), None, 0.2),
        ("dead_late", "seed", ("low", 0.15, 0.30), None, 0.2),
        ("rta_late_s", "seed", ("low", 150, 330), None, 0.2),
    ],
    "S5": [
        ("fight_p90_late", "seed", ("high", 6, 14), None, 1),
        ("fight_ramp", "seed", ("T", 1.0, 1.6, 3.0, 4.5), None, 1),
        ("engaged", "seed", ("T", 0.25, 0.40, 0.60, 0.75), None, 1),
        ("pk_ramp", "seed", ("T", 0.8, 1.3, 3.0, 5.0), None, 1),
    ],
    "S6": [
        ("pilot_kill_share", "seed", ("high", 0.40, 0.65), None, 1),
        ("pilot_kill_share_late", "seed", ("high", 0.30, 0.55), None, 1),
        ("pilot_involved_death_share", "seed", ("high", 0.50, 0.80), None, 1),
        ("unattended_turret_loss_share", "seed", ("low", 0.10, 0.35), None, 1),
    ],
    "S7": [
        ("skill_rho_small", "pool", ("T", 0.10, 0.35, 0.65, 0.85), median_of("skill_rho_small"), 1),
        ("duel_skill_winrate", "arena", ("T", 0.50, 0.70, 0.85, 0.97), "duel_skill_winrate", 1),
        ("ttk_small_med_s", "seed", ("T", 1.5, 4, 10, 20), None, 1),
        ("burst_death_share_small", "seed", ("low", 0.05, 0.25), None, 1),
    ],
    "S8": [
        ("size_parity", "pool", ("low", 0.58, 2.0), (size_parity_parts, size_parity_combine), 1),
        ("arena_small_winrate", "arena", ("T", 0.15, 0.40, 0.60, 0.85), "arena_small_winrate", 1),
        ("big_flak_pd_kill_share", "pool", ("T", 0.05, 0.25, 0.60, 0.85), sum_ratio("big_flak_pd_kills", "big_pilot_kills"), 1),
        ("big_pos_gap", "pool", ("low", 0.5, 1.0), (pos_gap_parts, pos_gap_combine), 1),
        ("small_late_kill_share", "pool", ("T", 0.10, 0.30, 0.60, 0.80), sum_ratio("small_kills_late25", "pilot_kills_late25"), 1),
    ],
    "S9": [
        ("play_income_share", "seed", ("T", 0.20, 0.45, 0.70, 0.90), None, 1),
        ("earn_spread", "seed", ("T", 1.05, 1.3, 2.0, 3.0), None, 1),
        ("pilot_float_30", "seed", ("low", 1200, 3500), None, 1),
        ("treasury_float_late", "seed", ("low", 3000, 20000), None, 1),
    ],
    "S10": [
        ("late_spend_ratio", "seed", ("high", 0.30, 0.75), None, 1),
        ("admiral_decisions_per_min_late", "seed", ("T", 0.1, 0.5, 3, 6), None, 1),
        ("asset_kill_share", "seed", ("T", 0.10, 0.30, 0.70, 0.90), None, 1),
    ],
    "S11": [
        ("assisted_kill_share", "pool", ("T", 0.25, 0.50, 0.80, 0.95), sum_ratio("assisted_kills", "pilot_kills"), 1),
        ("low_kp_pilots", "seed", ("low", 1, 4), None, 1),
        ("late_presence", "seed", ("high", 0.30, 0.75), None, 1),
    ],
}

# Per-seed sub-metrics whose number lives somewhere other than a top-level
# key of the same name, or that need a special rule (see seed_metric()).
SEED_SPECIAL = {
    "ms_pressure_onset_min": dict(never_zero=True),
    "final_push_secs": dict(ended_only=True),
    "travel": dict(path=("time_share", "travel")),
    "dead": dict(path=("time_share", "dead")),
    "engaged": dict(path=("time_share", "engaged")),
    "pilot_float_30": dict(fallback=("money_30", "pilot_credits_avg")),
}


def seed_fn(key, curve, how):
    """The per-record function of per-seed sub-metric `key` (the special
    one when `how` is given, else read the number with seed_metric())."""
    if how is not None:
        return how
    extra = dict(SEED_SPECIAL.get(key, {}))
    path = extra.pop("path", key)
    return seed_metric(path, curve, **extra)


# --- scoring a batch ---------------------------------------------------------------

def precompute(rec):
    """Work out, once per record, every per-seed (value, score) and every
    pooled piece, as {sub-metric key: result or None}. Resampling then only
    has to add these up."""
    out = {}
    for _ing, subs in METRICS.items():
        for key, kind, curve, how, _w in subs:
            if kind == "seed":
                out[key] = seed_fn(key, curve, how)(rec)
            elif kind == "pool":
                out[key] = how[0](rec)
    return out


def subset_allows(subset, ing, key):
    """Is sub-metric `key` of ingredient `ing` scored under `subset` (None =
    everything; else LATE_SUBSET-style)?"""
    if subset is None:
        return True
    if ing not in subset:
        return False
    return subset[ing] is None or key in subset[ing]


def score_batch(pres, arena, subset=None, allowed=None, fallback=None):
    """Score one batch. `pres` = the precompute() results of its records
    (one per seed; repeats allowed, as in a bootstrap draw), `arena` = its
    DUEL_JSON dictionary or None, `subset` = LATE_SUBSET for --late runs,
    `allowed` = the set of sub-metric keys that may be scored (None = any
    that can be measured), `fallback` = {key: score} to use when an allowed
    sub-metric can't be measured on this draw. Returns {"ingredients": {S:
    {"score", "weight", "subs": {key: {"kind", "value", "score", "n",
    "curve"}}}}, "fun": the weighted total or None}."""
    ings = {}
    for ing, name, weight in INGREDIENTS:
        subs, wsum, ssum = {}, 0.0, 0.0
        for key, kind, curve, how, w in METRICS[ing]:
            if not subset_allows(subset, ing, key):
                continue
            if allowed is not None and key not in allowed:
                continue
            value, score, n = None, None, 0
            # A per-seed sub-metric: the mean of the per-seed scores.
            if kind == "seed":
                got = [p[key] for p in pres if p.get(key) is not None]
                n = len(got)
                if got:
                    value = mean([g[0] for g in got])
                    score = mean([g[1] for g in got])
            # A pooled sub-metric: combine every match's piece, score once.
            elif kind == "pool":
                got = [p[key] for p in pres if p.get(key) is not None]
                n = len(got)
                if got:
                    value = how[1](got)
                    if value is not None:
                        score = apply_curve(curve, value)
            # An arena sub-metric: one number per build.
            else:
                value = num(arena.get(how)) if arena else None
                n = 1 if value is not None else 0
                if value is not None:
                    score = apply_curve(curve, value)
            # Not measurable on this draw: use the full batch's score if the
            # sub-metric is part of the fixed set.
            if score is None and fallback is not None and key in fallback:
                score = fallback[key]
            subs[key] = {"kind": kind, "value": value, "score": score, "n": n, "curve": curve_text(curve)}
            if score is not None:
                wsum += w
                ssum += w * score
        ings[ing] = {"name": name, "weight": weight, "score": ssum / wsum if wsum > 0 else None, "subs": subs}
    # FUN: the weighted total over the ingredients that could be scored.
    tw = sum(v["weight"] for v in ings.values() if v["score"] is not None)
    fun = sum(v["weight"] * v["score"] for v in ings.values() if v["score"] is not None) / tw if tw else None
    return {"ingredients": ings, "fun": fun}


def measurable(result):
    """The sub-metric keys that got a score in `result` (from score_batch)."""
    return {k for ing in result["ingredients"].values() for k, s in ing["subs"].items() if s["score"] is not None}


def sub_scores(result):
    """{sub-metric key: score} of every scored sub-metric in `result`."""
    return {k: s["score"] for ing in result["ingredients"].values() for k, s in ing["subs"].items() if s["score"] is not None}


# --- comparing two batches ------------------------------------------------------------

def paired_bootstrap(pres_a, pres_b, arena_a, arena_b, subset, allowed, fb_a, fb_b, resamples=2000, seed=20261015):
    """The paired bootstrap of "batch A minus batch B". `pres_a` / `pres_b`
    map seed number -> precomputed record (only seeds both batches have are
    used). Each of `resamples` rounds draws that many seed numbers at
    random, with repeats, scores both batches on the same draw, and keeps
    the differences. random.Random(`seed`) makes it repeatable. Returns
    {"fun": [differences], "S1": [...], ...}."""
    rng = random.Random(seed)
    seeds = sorted(set(pres_a) & set(pres_b))
    diffs = {"fun": []}
    for ing, _n, _w in INGREDIENTS:
        diffs[ing] = []
    for _ in range(resamples):
        # Step 1: one draw of seed numbers (with repeats).
        draw = [rng.choice(seeds) for _s in seeds]
        ra = score_batch([pres_a[s] for s in draw], arena_a, subset, allowed, fb_a)
        rb = score_batch([pres_b[s] for s in draw], arena_b, subset, allowed, fb_b)
        # Step 2: keep the differences that both sides could score.
        if ra["fun"] is not None and rb["fun"] is not None:
            diffs["fun"].append(ra["fun"] - rb["fun"])
        for ing, _n, _w in INGREDIENTS:
            a, b = ra["ingredients"][ing]["score"], rb["ingredients"][ing]["score"]
            if a is not None and b is not None:
                diffs[ing].append(a - b)
    return diffs


# --- extra facts about a batch -------------------------------------------------------

def auc_sign(recs, key, minute):
    """How well sign(A) at `minute` (from the per-seed dictionary `key`,
    "adv_at" or "adv_alt_at") predicts the winner over ended matches: the
    AUC, the chance that a match Halcyon won shows a higher sign than one
    Cinder won (ties count half). 0.5 = no better than a coin, 1 = perfect.
    None without both kinds of winner."""
    pos, neg = [], []
    for r in recs:
        a = num(get(r, key, str(minute)))
        if not r.get("ended") or a is None:
            continue
        s = (a > 0) - (a < 0)
        (pos if r.get("winner") == 0 else neg).append(s)
    if not pos or not neg:
        return None
    wins = sum((p > q) + 0.5 * (p == q) for p in pos for q in neg)
    return wins / (len(pos) * len(neg))


def batch_info(recs):
    """Facts printed beside the score (not part of FUN): how many matches
    ended, Halcyon's win rate, the match length median / IQR / p90 with
    unended matches counted as 60 minutes, the share under 20 minutes, the
    per-hit event and skill jitter counts, the summed usage counters, and the
    AUC of sign(A) at 15, 20 and 25 minutes (main and alternative index)."""
    n = len(recs)
    ended_recs = [r for r in recs if r.get("ended")]
    mins = [float(r["minutes"]) if r.get("ended") else 60.0 for r in recs if num(r.get("minutes")) is not None]
    usage = {}
    for r in recs:
        for k, v in (r.get("usage") or {}).items():
            if num(v) is not None:
                usage[k] = usage.get(k, 0) + v
    return {
        "matches": n,
        "ended": len(ended_recs),
        "halcyon_win_rate": ratio(sum(1 for r in ended_recs if r.get("winner") == 0), len(ended_recs)),
        "minutes_median": percentile(mins, 0.5),
        "minutes_iqr": [percentile(mins, 0.25), percentile(mins, 0.75)] if mins else None,
        "minutes_p90": percentile(mins, 0.9),
        "under_20_min": ratio(sum(1 for r in ended_recs if float(r["minutes"]) < 20.0), n),
        "damage_hook": sum(1 for r in recs if r.get("damage_hook")),
        "skill_jitter": sum(1 for r in recs if r.get("skill_jitter")),
        "probe_versions": sorted({int(r.get("version", 1)) for r in recs}),
        "usage": usage,
        "auc": {f"{m}": auc_sign(recs, "adv_at", m) for m in (15, 20, 25)},
        "auc_alt": {f"{m}": auc_sign(recs, "adv_alt_at", m) for m in (15, 20, 25)},
    }
