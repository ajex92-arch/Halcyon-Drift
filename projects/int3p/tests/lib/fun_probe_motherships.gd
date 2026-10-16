extends RefCounted
## WHAT THIS IS: the fun probe's mothership watcher. It measures the
## endgame: when the motherships first come under pressure, how long the
## final push takes, whether a crippled mothership hangs on for ages ("limbo"),
## whether sieges actually bite, and who does the hull damage
## (docs/FUN_RESEARCH.md, fun model ingredient 2).
##
## HOW IT WORKS:
##   - sample_first_hit(), every second (v1, unchanged): the first moment
##     each mothership's hull (not shields) took damage.
##   - sample_hull(), every 5 s: both motherships' hull fractions (0..1).
##     From these: pressure onset (the first sample where either is below
##     0.95), final push (the match end minus the last sample where the
##     LOSER was at 0.75 or more), and limbo (the longest run of samples
##     where a mothership is at 0.70 or less AND lost under 0.02 in the 120 s
##     before; each sample counts as 5 s).
##   - sample_siege(), every second: each team's TeamState.siege_phase.
##     An "assault" runs from TeamState.siege_t (when its phase began) until
##     the phase leaves "assault" (or a new assault replaces it: siege_t
##     changes). Only assaults of 20 s or more count (shorter ones are the
##     accidental 1-second "assaults" of the old waypoint bug). An assault
##     BITES when the target mothership's hull fell by 0.10 or more between
##     its start and its end. An assault still running when the probe stops
##     is counted only if it has already bitten (hull never grows back, so
##     that can't change); otherwise its result is unknown and it is
##     dropped ("undecided").
##   - on_damage(), every hit from the per-hit event Events.damage_applied
##     (only in builds that have it; the probe turns it on): a mothership's
##     HULL damage, split by who dealt it: big pilot ships (large and
##     capital), medium and small pilot ships, minions, or anything else
##     (turrets, motherships). ms_big_damage_share = the big pilot ships'
##     share of the LOSING mothership's hull damage.
##
## WHO USES IT: tests/fun_probe.gd makes one, calls the sample functions on
## its timers and on_damage() from the hit event, calls finish() once at
## the end, and merges results() into FUN_JSON.

## Helper maths (ratio, rounding).
const FunStats := preload("res://tests/lib/fun_stats.gd")
## Hull fraction below which a mothership is "under pressure".
const ONSET_FRAC := 0.95
## The final push starts when the loser was last at this fraction or more.
const PUSH_FRAC := 0.75
## Limbo: at or below this hull fraction...
const LIMBO_FRAC := 0.70
## ...and losing less than this fraction...
const LIMBO_LOSS := 0.02
## ...over the last this many seconds.
const LIMBO_LOOKBACK := 120.0
## How often sample_hull() runs (seconds).
const HULL_STEP := 5.0
## Assaults shorter than this (seconds) don't count.
const ASSAULT_MIN := 20.0
## An assault "bites" when the target lost this much hull fraction.
const BITE := 0.10

## First moment (seconds) each mothership's hull took damage; -1 = never.
var first_hull_hit := [-1.0, -1.0]
## The match times (seconds) of the 5-s hull samples.
var hull_t: Array = []
## The hull fractions at those samples: [Halcyon's list, Cinder's list].
var hull_f: Array = [[], []]
## Match time (seconds) when either hull first fell below 0.95; -1 = never.
var onset_t := -1.0
## The assault being watched, per team: {} for none, else {"t0": start
## (seconds), "f0": the target's hull fraction then, "st": siege_t then}.
var _open: Array = [{}, {}]
## Assaults that lasted 20 s or more (and whose result is known).
var assaults := 0
## Of those, how many bit (target lost 0.10+ hull fraction).
var bites := 0
## Assaults shorter than 20 s (not counted).
var short_assaults := 0
## Assaults still running at the end without a bite yet (dropped).
var undecided := 0
## Hull damage taken by each mothership, by who dealt it:
## [Halcyon's, Cinder's], each "big_pilot"/"medium_pilot"/"small_pilot"/
## "minion"/"other" -> hull points.
var dmg_by: Array = [{}, {}]


## Every second (v1): remember the first moment each mothership's hull
## took damage (more than 1 hull point below full).
func sample_first_hit(world: World) -> void:
	for t in 2:
		var ms := world.mothership(t)
		if ms != null and first_hull_hit[t] < 0.0 and ms.hull < ms.hull_max - 1.0:
			first_hull_hit[t] = world.time


## Mothership `t`'s hull fraction now (0 once destroyed).
func _frac(world: World, t: int) -> float:
	var ms := world.mothership(t)
	return ms.hull_frac() if ms != null and ms.alive else 0.0


## Every 5 s: both hull fractions, and the pressure onset.
func sample_hull(world: World) -> void:
	hull_t.append(world.time)
	for t in 2:
		(hull_f[t] as Array).append(_frac(world, t))
	if onset_t < 0.0 and minf(_frac(world, 0), _frac(world, 1)) < ONSET_FRAC:
		onset_t = world.time


## Every second: follow both teams' assaults (see HOW IT WORKS).
func sample_siege(world: World) -> void:
	for t in 2:
		var ts := world.teams[t]
		var cur: Dictionary = _open[t]
		var in_assault := ts.siege_phase == "assault"
		# Step 1: the assault we watched is over, or was replaced by a new
		# one (siege_t moved): close it.
		if not cur.is_empty() and (not in_assault or float(cur["st"]) != ts.siege_t):
			_close(world, t, cur, true)
			cur = {}
		# Step 2: a new assault: note its start and the target's hull.
		if in_assault and cur.is_empty():
			cur = {"t0": ts.siege_t, "f0": _frac(world, 1 - t), "st": ts.siege_t}
		_open[t] = cur


## Close team `t`'s assault `a` now and count it (see HOW IT WORKS).
## `finished` = the assault really ended; false = the probe is stopping
## while it still runs.
func _close(world: World, t: int, a: Dictionary, finished: bool) -> void:
	var dur := world.time - float(a["t0"])
	var drop := float(a["f0"]) - _frac(world, 1 - t)
	if dur < ASSAULT_MIN:
		short_assaults += 1
	elif finished or drop >= BITE:
		assaults += 1
		if drop >= BITE:
			bites += 1
	else:
		undecided += 1


## A hit from Events.damage_applied: add mothership HULL damage to the
## right "who dealt it" box. `target` is the unit hit, `info` its
## DamageInfo, `hull_dmg` the hull points it took.
func on_damage(target: Node, info: RefCounted, hull_dmg: float) -> void:
	var u := target as Unit
	if u == null or u.kind != Unit.K_MOTHERSHIP or hull_dmg <= 0.0 or u.team > 1:
		return
	var d := info as DamageInfo
	var who := "other"
	if d != null and d.source_profile != null:
		if d.source_size >= Rules.SIZE_LARGE:
			who = "big_pilot"
		elif d.source_size == Rules.SIZE_MEDIUM:
			who = "medium_pilot"
		else:
			who = "small_pilot"
	elif d != null and d.source_is_minion:
		who = "minion"
	var by: Dictionary = dmg_by[u.team]
	by[who] = float(by.get(who, 0.0)) + hull_dmg


## Once, when the probe stops: close the assaults still running. `ended` =
## a mothership died (the assaults really ended with the match).
func finish(world: World, ended: bool) -> void:
	for t in 2:
		var cur: Dictionary = _open[t]
		if not cur.is_empty():
			_close(world, t, cur, ended)
			_open[t] = {}


## The longest limbo stretch (seconds) of mothership `t` (see HOW IT WORKS).
func _limbo(t: int) -> float:
	var f: Array = hull_f[t]
	var back := int(round(LIMBO_LOOKBACK / HULL_STEP))
	var best := 0
	var run := 0
	for i in f.size():
		# A sample is "in limbo" when the hull is low and barely moved over
		# the last 120 s (we need a sample from 120 s before to know).
		var limbo := i >= back and float(f[i]) <= LIMBO_FRAC and float(f[i - back]) - float(f[i]) < LIMBO_LOSS
		run = run + 1 if limbo else 0
		best = maxi(best, run)
	return float(best) * HULL_STEP


## Everything this part measured, for FUN_JSON. `winner` = the winning team
## (-1 = none), `ended` = a mothership died, `start_t` / `end_t` = when the
## probe started and stopped watching (seconds).
func results(winner: int, ended: bool, start_t: float, end_t: float) -> Dictionary:
	# Step 1 (v1): seconds from the loser's first hull damage to its death.
	var close_out := -1.0
	if winner >= 0 and first_hull_hit[1 - winner] >= 0.0:
		close_out = end_t - first_hull_hit[1 - winner]
	# Step 2: the final push (ended matches only).
	var push := -1.0
	if ended and winner >= 0:
		var loser: Array = hull_f[1 - winner]
		var last_ok := start_t
		for i in loser.size():
			if float(loser[i]) >= PUSH_FRAC:
				last_ok = float(hull_t[i])
		push = end_t - last_ok
	# Step 3: who damaged the loser's hull (needs the per-hit event).
	var loser_total := 0.0
	var loser_big := 0.0
	if winner >= 0:
		var by: Dictionary = dmg_by[1 - winner]
		for k in by:
			loser_total += float(by[k])
		loser_big = float(by.get("big_pilot", 0.0))
	# Step 4: the hull every 60 s, [time, Halcyon, Cinder], for plotting.
	var every := int(round(60.0 / HULL_STEP))
	var hull_minutes: Array = []
	for i in range(every - 1, hull_t.size(), every):
		hull_minutes.append([int(hull_t[i]), snappedf(float(hull_f[0][i]), 0.001), snappedf(float(hull_f[1][i]), 0.001)])
	var dmg_out: Array = []
	for t in 2:
		var d := {}
		for k in dmg_by[t]:
			d[k] = int(dmg_by[t][k])
		dmg_out.append(d)
	return {
		"ms_first_hull_hit_min": [_min_or_never(first_hull_hit[0]), _min_or_never(first_hull_hit[1])],
		"close_out_secs": int(close_out),
		"ms_pressure_onset_min": _min_or_never(onset_t),
		"final_push_secs": int(push),
		"ms_limbo_secs": int(maxf(_limbo(0), _limbo(1))),
		"siege_assaults": assaults,
		"siege_bites": bites,
		"siege_bite_rate": FunStats.snap(FunStats.ratio(float(bites), float(assaults)), 0.001),
		"siege_assaults_short": short_assaults,
		"siege_undecided": undecided,
		"ms_hull_dmg": dmg_out,
		"ms_loser_hull_dmg": int(loser_total),
		"ms_loser_big_dmg": int(loser_big),
		"ms_big_damage_share": FunStats.snap(FunStats.ratio(loser_big, loser_total), 0.001) if ended else null,
		"ms_hull": hull_minutes,
	}


## A match time in minutes (2 decimals), or -1 for "never happened".
func _min_or_never(t: float) -> float:
	return snappedf(t / 60.0, 0.01) if t >= 0.0 else -1.0
