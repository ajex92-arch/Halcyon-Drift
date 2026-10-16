extends RefCounted
## WHAT THIS IS: the fun probe's team-fight spotter. Every 2 seconds it
## looks for crowds of pilot ships from both teams that are really fighting
## each other, and measures whether skirmishes grow into big battles later
## in the match (docs/FUN_RESEARCH.md, fun model ingredients 5 and 11).
##
## HOW IT WORKS: sample() runs every 2 s and does two checks.
##   v1 (unchanged, for comparison with old runs): some pilot has 3+ enemy
##   and 3+ friendly pilots (itself included) within 2,500 world units, and
##   one of them was hurt by anything in the last 4 s. Samples less than
##   20 s apart are one fight.
##   v2 (the research definition): group the live pilot ships into
##   "clusters": two ships 2,500 or closer are linked, and every chain of
##   links is one cluster ("single linkage"). A cluster is a FIGHT when it
##   holds 3+ ships of each team AND, in the last 4 s, a member was hit by a
##   PILOT of the other team who is in the same cluster (so 3 v 3 pilots
##   parked in a minion brawl, or just flying in a clump, don't count). We
##   read that from each member's damage log (Unit.damage_log keeps, per
##   attacker, the time of its last hit and its PilotProfile, if it is a
##   pilot). A fight's size is its ship count. For each sample we keep the
##   biggest fight, filed as early (before 10:00), mid (10:00-25:00) or late
##   (25:00 on). From 25:00 the match is also cut into 5-minute windows;
##   every pilot seen in any fight in a window was "present" in it.
## (A "world unit" is the game's distance unit, about one pixel at normal
## zoom.)
##
## WHO USES IT: tests/fun_probe.gd makes one, calls sample() every 2 s and
## merges results() into FUN_JSON.

## Helper maths (percentile, mean).
const FunStats := preload("res://tests/lib/fun_stats.gd")
## Ships this close (world units) are linked into one cluster.
const LINK := 2500.0
## A hit this recent (seconds) makes a fight "hot".
const HOT := 4.0
## Fight samples closer together than this (seconds) are the same fight.
const SAME_FIGHT := 20.0
## Match time (seconds) where "mid" starts: 10:00.
const MID_T := 600.0
## Match time (seconds) where "late" starts: 25:00.
const LATE_T := 1500.0
## The late "presence" windows are this long (seconds): 5 minutes.
const WINDOW := 300.0
## How often sample() runs (seconds); each sample stands for this much time.
const STEP := 2.0

# --- v1 (unchanged) ------------------------------------------------------------

## How many separate fights so far (v1).
var fights := 0
## The most pilots seen in one team fight (v1).
var fight_max_pilots := 0
## Match time (seconds) of the last v1 sample that found a fight.
var _last_fight_t := -999.0
## How many v1 samples found a fight (each one = 2 s of fighting).
var fight_samples := 0

# --- v2 ------------------------------------------------------------------------

## The biggest v2 fight of each fight sample, by part of the match:
## "early" / "mid" / "late" -> list of sizes (ship counts).
var sizes := {"early": [], "mid": [], "late": []}
## How many 2-s samples were taken in each part of the match.
var samples := {"early": 0, "mid": 0, "late": 0}
## Separate v2 fights (samples less than 20 s apart are one fight).
var fight2_count := 0
## How many samples found a v2 fight.
var fight2_samples := 0
## The biggest v2 fight (ship count).
var fight2_max := 0
## Match time (seconds) of the last sample with a v2 fight.
var _last_fight2_t := -999.0
## Late presence: window number (0 = 25:00-30:00, 1 = 30:00-35:00, ...)
## -> {PilotProfile: true} for every pilot seen in a v2 fight in it.
var present := {}
## Seconds watched in each late window (window number -> seconds).
var window_secs := {}


## Every 2 s: the v1 check, then the v2 clusters.
func sample(world: World) -> void:
	# The live pilot ships (both checks use them).
	var ships: Array = []
	for s: Ship in world.ships:
		if s.alive:
			ships.append(s)
	_sample_v1(world, ships)
	_sample_v2(world, ships)


## The v1 fight check (see HOW IT WORKS), unchanged from fun probe v1.
func _sample_v1(world: World, ships: Array) -> void:
	# Step 1: for each ship, count allies and enemies within 2,500 and see
	# if any of them was hurt lately. Keep the biggest qualifying crowd.
	var best := 0
	for a: Ship in ships:
		var allies := 0
		var enemies := 0
		var hot := false
		for b: Ship in ships:
			if a.global_position.distance_to(b.global_position) > LINK:
				continue
			if b.team == a.team:
				allies += 1
			else:
				enemies += 1
			if world.time - b.last_damage_time < HOT:
				hot = true
		if allies >= 3 and enemies >= 3 and hot:
			best = maxi(best, allies + enemies)
	# Step 2: a fight is on. More than 20 s since the last one = a new fight.
	if best > 0:
		fight_samples += 1
		if world.time - _last_fight_t > SAME_FIGHT:
			fights += 1
		_last_fight_t = world.time
		fight_max_pilots = maxi(fight_max_pilots, best)


## The v2 check: clusters, the pilot-on-pilot hit test, the biggest fight
## by part of the match, and late presence.
func _sample_v2(world: World, ships: Array) -> void:
	var now := world.time
	var part := "early" if now < MID_T else ("mid" if now < LATE_T else "late")
	samples[part] = int(samples[part]) + 1
	# Step 1: the late window this sample belongs to.
	var w := -1
	if now >= LATE_T:
		w = int((now - LATE_T) / WINDOW)
		window_secs[w] = float(window_secs.get(w, 0.0)) + STEP
		if not present.has(w):
			present[w] = {}
	# Step 2: every cluster that is a fight: note its size and, late, its
	# pilots.
	var best := 0
	for group: Array in _clusters(ships):
		if not _is_fight(group, now):
			continue
		best = maxi(best, group.size())
		if w >= 0:
			for s: Ship in group:
				if s.profile != null:
					present[w][s.profile] = true
	# Step 3: the biggest fight of this sample, and the fight count.
	if best > 0:
		(sizes[part] as Array).append(best)
		fight2_samples += 1
		fight2_max = maxi(fight2_max, best)
		if now - _last_fight2_t > SAME_FIGHT:
			fight2_count += 1
		_last_fight2_t = now


## Single-linkage clusters of `ships`: ships 2,500 or closer are linked,
## and every group of ships joined by links is one cluster. Returns a list
## of clusters (each a list of ships). It uses a "union-find" table:
## parent[i] points toward the group's representative ship.
func _clusters(ships: Array) -> Array:
	# Step 1: link every close pair.
	var n := ships.size()
	var parent: Array = range(n)
	for i in n:
		var pos_i: Vector2 = (ships[i] as Ship).global_position
		for j in range(i + 1, n):
			if pos_i.distance_to((ships[j] as Ship).global_position) <= LINK:
				var ra := _find(parent, i)
				var rb := _find(parent, j)
				if ra != rb:
					parent[ra] = rb
	# Step 2: collect each ship under its group's representative.
	var groups := {}
	for i in n:
		var r := _find(parent, i)
		if not groups.has(r):
			groups[r] = []
		(groups[r] as Array).append(ships[i])
	return groups.values()


## The representative of ship number `i`'s group in the union-find table
## `parent` (it also shortens the path on the way, so later look-ups are
## quick).
func _find(parent: Array, i: int) -> int:
	var x := i
	while int(parent[x]) != x:
		parent[x] = parent[int(parent[x])]
		x = int(parent[x])
	return x


## Is cluster `group` a fight at time `now`: 3+ ships of each team, and a
## member hit by a pilot of the other team from inside the cluster in the
## last 4 s?
func _is_fight(group: Array, now: float) -> bool:
	# Step 1: enough ships on both sides? Also note every member's id.
	var per_team := [0, 0]
	var uids := {}
	for s: Ship in group:
		if s.team == 0 or s.team == 1:
			per_team[s.team] = int(per_team[s.team]) + 1
		uids[s.uid] = true
	if int(per_team[0]) < 3 or int(per_team[1]) < 3:
		return false
	# Step 2: a recent hit by an enemy PILOT who is also in the cluster.
	# Damage log entries are attacker id -> [damage, time of its last hit,
	# its PilotProfile or null].
	for s: Ship in group:
		for uid in s.damage_log:
			var e: Array = s.damage_log[uid]
			if e[2] != null and now - float(e[1]) <= HOT and uids.has(uid) and (e[2] as PilotProfile).team != s.team:
				return true
	return false


## Late presence: [the share of (pilot x late window) pairs in which the
## pilot was in a v2 fight (null with no window), the number of windows
## used]. Only windows watched for at least half their length (150 s)
## count. `pilots` is how many AI pilots there are.
func late_presence(pilots: int) -> Array:
	var pairs := 0
	var hit := 0
	var used := 0
	for w in window_secs:
		if float(window_secs[w]) < WINDOW * 0.5:
			continue
		used += 1
		pairs += pilots
		hit += (present.get(w, {}) as Dictionary).size()
	return [FunStats.ratio(float(hit), float(pairs)), used]


## Everything this part measured, for FUN_JSON. `obs_secs` is how long the
## probe watched (seconds); `pilots` the number of AI pilots.
func results(obs_secs: float, pilots: int) -> Dictionary:
	var minutes := obs_secs / 60.0
	# fight_p90_late: needs the late part to have been watched; no fights
	# there gives 0.
	var p90: Variant = null
	if int(samples["late"]) > 0:
		p90 = FunStats.percentile(sizes["late"], 0.9) if not (sizes["late"] as Array).is_empty() else 0.0
	# fight_ramp: mean late fight / mean early fight. Needs early fights;
	# a watched late part with no fights gives 0.
	var ramp: Variant = null
	var early_mean: Variant = FunStats.mean(sizes["early"])
	if typeof(early_mean) != TYPE_NIL and int(samples["late"]) > 0:
		var late_mean: Variant = FunStats.mean(sizes["late"])
		ramp = float(late_mean) / float(early_mean) if typeof(late_mean) != TYPE_NIL else 0.0
	var count := {}
	for k in ["early", "mid", "late"]:
		count[k] = (sizes[k] as Array).size()
	var presence := late_presence(pilots)
	return {
		"fights": fights,
		"fights_per_10min": snappedf(float(fights) / maxf(0.01, minutes) * 10.0, 0.01),
		"fight_time_share": snappedf(float(fight_samples) * STEP / maxf(1.0, obs_secs), 0.001),
		"fight_max_pilots": fight_max_pilots,
		"fight_p90_late": FunStats.snap(p90, 0.1),
		"fight_ramp": FunStats.snap(ramp, 0.001),
		"fight_mean": {"early": FunStats.snap(early_mean, 0.01), "mid": FunStats.snap(FunStats.mean(sizes["mid"]), 0.01), "late": FunStats.snap(FunStats.mean(sizes["late"]), 0.01)},
		"fight_samples": count,
		"fight2": {"count": fight2_count, "time_share": snappedf(float(fight2_samples) * STEP / maxf(1.0, obs_secs), 0.001), "max": fight2_max},
		"late_presence": FunStats.snap(presence[0], 0.001),
		"late_presence_windows": presence[1],
	}
