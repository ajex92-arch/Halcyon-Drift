extends RefCounted
## WHAT THIS IS: the fun probe's time-keeper for pilots. Once a second it
## sorts every AI pilot's second into a bucket (dead, docked, fighting, near
## a fight, or travelling) and from that works out the downtime numbers of
## docs/FUN_RESEARCH.md (fun model ingredient 4): travel split into commute
## and idle, dead time after 30:00, and how long pilots take to get back
## into a fight after dying ("return to action").
##
## HOW IT WORKS:
##   - sample_pilots(), every second. The v1 buckets, unchanged: "dead"
##     (dead, waiting for a hyperspace launch, or flying with no live
##     ship), "docked", "engaged" (took or dealt damage in the last 4 s),
##     "near" (an enemy within 2,500 world units, not fighting), else
##     "travel". New: a travel second is "commute" when the ship flies at
##     40% of its top speed (Ship.f_max) or faster, else "idle". After 30:00
##     the dead and all seconds are also counted on their own (dead_late).
##     Flying seconds are added up per size class (small, medium, large,
##     capital), and each pilot's size class is remembered for size_of().
##   - Return to action: note_death() starts a stopwatch for that pilot;
##     the first later second in which that pilot is "engaged" stops it.
##     Stopwatches still running at the end are "dropped" (the pilot never
##     got back into a fight before the probe stopped).
##   - sample_minute(): which hulls are flying (v1 hull_minutes).
##   - sample_strain(): is each team's mothership under respawn strain
##     (TeamState.strain_t above 0)? Gives the strain uptime.
## (A "world unit" is the game's distance unit, about one pixel at normal
## zoom.)
##
## WHO USES IT: tests/fun_probe.gd makes one, calls the sample functions on
## its timers and note_death() on every pilot ship death, and merges
## results() into FUN_JSON. tests/lib/fun_probe_kills.gd asks size_of().

## Helper maths (median).
const FunStats := preload("res://tests/lib/fun_stats.gd")
## Match time (seconds) from which dead time counts as "late": 30:00.
const LATE_T := 1800.0
## A travel second is "commute" at this share of top speed or more.
const COMMUTE_SPEED := 0.4
## Took or dealt damage this recently (seconds) = fighting.
const ENGAGED_SECS := 4.0
## An enemy this close (world units) = near a fight.
const NEAR_RANGE := 2500.0

# --- the v1 buckets, in pilot-seconds (one pilot for one second = 1) ---------

## Time dead, or waiting to launch, or flying with no live ship.
var t_dead := 0.0
## Time docked in the hangar.
var t_docked := 0.0
## Time fighting (hurt or hit something in the last 4 s).
var t_engaged := 0.0
## Time near an enemy (within 2,500) but not fighting.
var t_near := 0.0
## Time flying with no enemy near ("travelling").
var t_travel := 0.0

# --- v2 additions --------------------------------------------------------------

## The travel seconds flown at 40% of top speed or more (pilot-seconds).
var t_commute := 0.0
## The other travel seconds (slow or holding a spot; pilot-seconds).
var t_idle := 0.0
## Dead pilot-seconds after 30:00.
var late_dead := 0.0
## All pilot-seconds after 30:00.
var late_all := 0.0
## Seconds flown per size class index (small, medium, large, capital),
## summed over pilots.
var size_secs: Array = [0.0, 0.0, 0.0, 0.0]
## Each pilot's size class the last time it was seen flying
## (PilotProfile -> Rules.SIZE_*).
var _size := {}
## Running return-to-action stopwatches: PilotProfile -> list of death
## times (seconds) still waiting for the pilot's next fight.
var _pending := {}
## Return-to-action times (seconds), one per resolved death.
var rta_all: Array = []
## The same, only for deaths after 30:00.
var rta_late: Array = []
## Each pilot's damage_done at the last sample (PilotProfile -> damage).
var _last_dmg := {}
## When each pilot's damage_done last went up (PilotProfile -> seconds).
var _last_dealt_t := {}
## Hull use (v1): hull id -> pilot-minutes flown in it.
var hull_minutes := {}
## Seconds each team's mothership spent under respawn strain [H, C].
var strain_secs: Array = [0.0, 0.0]
## Seconds in which strain was checked.
var strain_obs := 0.0
## A reusable list for spatial hash searches (saves making a new one).
var _scratch: Array = []


## One second for every AI pilot: put it in its bucket (see HOW IT WORKS),
## and stop the return-to-action stopwatches of pilots who are fighting.
func sample_pilots(world: World) -> void:
	var now := world.time
	var late := now >= LATE_T
	for p: PilotProfile in world.profiles:
		if p.is_human:
			continue
		# Step 1: did this pilot deal damage since the last sample?
		var dmg: float = p.damage_done
		if dmg > float(_last_dmg.get(p, 0.0)):
			_last_dealt_t[p] = now
		_last_dmg[p] = dmg
		# Step 2: the bucket ("spooling" = waiting for a hyperspace launch,
		# counted as dead time; flying with no live ship counts as dead too).
		var bucket := "dead"
		if p.state == "docked":
			bucket = "docked"
		elif p.state != "dead" and p.state != "spooling":
			var s := p.ship
			if s != null and is_instance_valid(s) and s.alive:
				bucket = _flying_bucket(world, p, s)
		# Step 3: add the second to its bucket.
		match bucket:
			"dead": t_dead += 1.0
			"docked": t_docked += 1.0
			"engaged": t_engaged += 1.0
			"near": t_near += 1.0
			"commute":
				t_travel += 1.0
				t_commute += 1.0
			_:
				t_travel += 1.0
				t_idle += 1.0
		# Step 4: the late counts, and stopping this pilot's stopwatches.
		if late:
			late_all += 1.0
			if bucket == "dead":
				late_dead += 1.0
		if bucket == "engaged" and _pending.has(p):
			for d: float in _pending[p]:
				rta_all.append(now - d)
				if d >= LATE_T:
					rta_late.append(now - d)
			_pending.erase(p)


## The bucket of a flying pilot `p` in live ship `s`: "engaged", "near",
## "commute" or "idle". Also notes the ship's size class and adds the
## second to that size class.
func _flying_bucket(world: World, p: PilotProfile, s: Ship) -> String:
	# Step 1: remember the size class and count the flying second.
	_size[p] = s.size_class
	size_secs[Rules.size_index(s.size_class)] = float(size_secs[Rules.size_index(s.size_class)]) + 1.0
	# Step 2: hurt or hit something in the last 4 s = fighting; else an
	# enemy within 2,500 = near.
	var hurt_recently := world.time - s.last_damage_time < ENGAGED_SECS
	var hit_recently := world.time - float(_last_dealt_t.get(p, -999.0)) < ENGAGED_SECS
	if hurt_recently or hit_recently:
		return "engaged"
	if _enemy_near(world, s, NEAR_RANGE):
		return "near"
	# Step 3: travelling: fast = commuting, slow = idle.
	if s.velocity.length() >= COMMUTE_SPEED * s.f_max:
		return "commute"
	return "idle"


## Is any live enemy unit (not a neutral derelict) within `r` world units
## of ship `s`? (v1, unchanged.) It searches World.unit_hash (a grid that
## finds nearby units quickly, a "spatial hash") with an exact distance
## test, then, if there are big units, World.big_hash out to r + 600
## without one. Motherships are in neither grid, so they never count here.
func _enemy_near(world: World, s: Ship, r: float) -> bool:
	for u: Unit in world.unit_hash.query(s.global_position, r, _scratch):
		if not u.alive or u.team == s.team or u.team == Rules.NEUTRAL:
			continue
		if u.global_position.distance_to(s.global_position) < r:
			return true
	if world.big_count > 0:
		for u: Unit in world.big_hash.query(s.global_position, r + 600.0, _scratch):
			if u.alive and u.team != s.team and u.team != Rules.NEUTRAL:
				return true
	return false


## Pilot `p` just died at time `t` (seconds): start its return-to-action
## stopwatch. Human pilots are not watched.
func note_death(p: PilotProfile, t: float) -> void:
	if p == null or p.is_human:
		return
	if not _pending.has(p):
		_pending[p] = []
	(_pending[p] as Array).append(t)


## The size class pilot `p` flies now (or flew last), as Rules.SIZE_*, or
## -1 if it has never been seen flying.
func size_of(p: PilotProfile) -> int:
	if p.ship != null and is_instance_valid(p.ship) and p.ship.alive:
		return p.ship.size_class
	return int(_size.get(p, -1))


## Once a minute (v1): add a pilot-minute to the hull of every flying ship.
func sample_minute(world: World) -> void:
	for s: Ship in world.ships:
		if s.alive:
			hull_minutes[s.hull_id] = float(hull_minutes.get(s.hull_id, 0.0)) + 1.0


## Once a second: note which motherships are under respawn strain.
func sample_strain(world: World) -> void:
	strain_obs += 1.0
	for t in 2:
		if world.teams[t].strain_t > 0.0:
			strain_secs[t] = float(strain_secs[t]) + 1.0


## How evenly the hulls were flown (v1): the Shannon entropy of the
## hull-minutes divided by the most it could be with every hull type flown
## equally (0 = everyone in one hull, 1 = perfectly varied). (Entropy is a
## measure of how evenly something is spread out.)
func hull_variety() -> float:
	var total := 0.0
	for k in hull_minutes:
		total += float(hull_minutes[k])
	var entropy := 0.0
	for k in hull_minutes:
		var q := float(hull_minutes[k]) / maxf(1.0, total)
		if q > 0.0:
			entropy -= q * log(q)
	return entropy / log(float(Ships.HULLS.size()))


## How many stopwatches are still running: [all, deaths after 30:00].
func dropped() -> Array:
	var n_all := 0
	var n_late := 0
	for p in _pending:
		for d: float in _pending[p]:
			n_all += 1
			if d >= LATE_T:
				n_late += 1
	return [n_all, n_late]


## Everything this part measured, for FUN_JSON (time_share keeps its v1
## meaning: five fractions of all AI pilot time that add up to 1).
func results() -> Dictionary:
	var pilot_secs := maxf(1.0, t_dead + t_docked + t_engaged + t_near + t_travel)
	var drop := dropped()
	return {
		"time_share": {
			"dead": snappedf(t_dead / pilot_secs, 0.001),
			"docked": snappedf(t_docked / pilot_secs, 0.001),
			"engaged": snappedf(t_engaged / pilot_secs, 0.001),
			"near": snappedf(t_near / pilot_secs, 0.001),
			"travel": snappedf(t_travel / pilot_secs, 0.001),
		},
		"travel_split": {
			"commute": snappedf(t_commute / pilot_secs, 0.001),
			"idle": snappedf(t_idle / pilot_secs, 0.001),
		},
		"dead_late": FunStats.snap(FunStats.ratio(late_dead, late_all), 0.001),
		"rta_all_s": FunStats.snap(FunStats.median(rta_all), 0.1),
		"rta_late_s": FunStats.snap(FunStats.median(rta_late), 0.1),
		"rta_n": rta_all.size(),
		"rta_late_n": rta_late.size(),
		"rta_dropped": drop[0],
		"rta_late_dropped": drop[1],
		"hull_variety": snappedf(hull_variety(), 0.001),
		"hull_minutes": hull_minutes,
		"size_minutes": FunStats.snap_all([float(size_secs[0]) / 60.0, float(size_secs[1]) / 60.0, float(size_secs[2]) / 60.0, float(size_secs[3]) / 60.0], 0.01),
		"strain_uptime": [FunStats.snap(FunStats.ratio(float(strain_secs[0]), strain_obs), 0.001), FunStats.snap(FunStats.ratio(float(strain_secs[1]), strain_obs), 0.001)],
	}
