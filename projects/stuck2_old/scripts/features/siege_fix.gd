class_name SiegeFixFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "siege_fix" rule variant: sieges
## that land (docs/FUN_PLAN.md section 5, endgame_closure fork, idea B1; this
## fork owns the siege AI). REQ-CHANGE: none. It changes how the AI admiral
## times the assault on the enemy mothership and how the fleet arrives, not a
## rule of the game. A human admiral still declares a siege with the
## waypoint.
##
## HOW IT WORKS: the variant has three values besides "off" (the default):
##   "gather3"  the AI admiral launches the assault when min(3, big ships
##              alive) are massed within 3,000 of the staging point (a
##              bomber counts as half a ship), or after 90 s of gathering
##              when 2 or more big ships are there. (Today: 2 ships, or 45 s
##              with whoever is there.) If the stragglers never come, the
##              assault starts anyway after 150 s so there is no limbo. The
##              AdmiralSiege tuned numbers "siege_gather_count" and
##              "siege_gather_time" are set out of reach and this module
##              makes the go decision instead (tick hook, twice a second),
##              then does what AdmiralSiege does at that moment: phase
##              "assault", the assault clock and contact reset, the waypoint
##              moved at the admiral's next think.
##   "full"     gather3 plus
##              formation: during the approach (siege phases "gather" and
##              "assault") a speed cap, 1.1 times the top speed of the
##              slowest siege ship within 6,000 of the lead ship (the one
##              nearest the enemy mothership), is kept per team; PilotFlight
##              asks throttle() and a siege ship more than 2,500 ahead of
##              the group's centre (measured towards the enemy hull) that is
##              faster than the cap stops thrusting, so the capital ships
##              arrive together with the frigates and bombers (not within
##              4,500 of the enemy hull: once in contact it flies free);
##              base race: when our team has NO siege running, 2 or more
##              enemy big ships we can see within 12,000 of our hull that
##              are closing at more than 40 world units a second sound the
##              defend call early (TeamState.defend_point, 12 s, like
##              TeamDefense) so the defenders are home before the usual
##              7,000 radius. It never touches our own siege (the usual
##              TeamDefense rule keeps calling a siege off only for a push at
##              our hull).
##   "stall"    the stall check is judged over the whole siege: the enemy
##              mothership must lose 10% of its hull in 240 s after contact
##              (tuned "siege_stall_time" 240, "siege_stall_frac" 0.10;
##              today 15% in 120 s). 4 of 4 ended sieges in the deep dive
##              were called off at 1.00 hull.
## Usage counters (Game.usage): "assaults_launched" and "assault_gather_ships"
## (big ships massed when an assault was launched; gather3 and full),
## "siege_throttles" (seconds a ship was held back; full), "base_races" (early
## defend calls; full) and "siege_stall_saved" (a siege that the old 15%/120 s
## rule would have called off but lived on; stall). The module draws no random
## numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=siege_fix:gather3,
## full or stall, and runs it through World.tick_hooks. PilotFlight.travel()
## calls throttle() (only when this module is on).

## The variant key this module belongs to.
const KEY := "siege_fix"
## Big ships (or the weighted count) wanted at the staging point at most.
const GATHER_MAX := 3
## Seconds of gathering after which 2+ big ships there go (gather3, full).
const GATHER_TIME := 90.0
## Seconds of gathering after which the assault starts whatever is there.
const GATHER_HARD_CAP := 150.0
## Weight of a bomber in the massed count (0.5 = half a ship).
const BOMBER_WEIGHT := 0.5
## The siege stall check window for "stall" (seconds after first contact).
const STALL_TIME := 240.0
## The hull fraction the enemy mothership must lose in that window for "stall".
const STALL_FRAC := 0.10
## How far (world units) from the lead ship a siege ship still counts as in
## the group for the speed cap.
const GROUP_RADIUS := 6000.0
## The speed cap is this times the slowest group ship's top speed.
const CAP_FACTOR := 1.1
## A siege ship more than this far (world units) ahead of the group's centre
## is throttled.
const AHEAD_DIST := 2500.0
## The throttle stops within this distance (world units) of the enemy hull.
const CONTACT_FREE := 4500.0
## Base race: enemy big ships within this distance (world units) of our hull...
const RACE_RADIUS := 12000.0
## ...closing faster than this (world units per second) count.
const RACE_CLOSING := 40.0
## Seconds the early defend call lasts (as TeamDefense's 12 s).
const RACE_CALL := 12.0
## The old stall rule's numbers (AdmiralSiege.STALL_TIME / STALL_FRAC), used
## to see when "stall" kept a siege alive.
const OLD_STALL_TIME := 120.0
## See OLD_STALL_TIME.
const OLD_STALL_FRAC := 0.15

## The world we belong to.
var world: World
## True for "full" (formation and base race on).
var full := false
## True for gather3 and full (this module decides when the assault starts).
var gather := false
## The speed cap per team while a siege approaches (INF = none).
var cap := [INF, INF]
## The centre of each team's siege group (world position).
var centre := [Vector2.ZERO, Vector2.ZERO]
## Seconds until the next gather check (twice a second).
var _t_gather := 0.0
## Seconds until the next formation and base-race update (once a second).
var _t_sec := 0.0
## Where each enemy big ship was at the last base-race check: uid -> its
## distance to the mothership hull of the team watching, by team.
var _prev_d: Array = [{}, {}]
## Last match time a throttle was counted for a ship (uid -> seconds), so the
## usage counts seconds, not ticks.
var _thr_t := {}
## The siege (by its start time) for which "siege_stall_saved" was counted,
## per team.
var _saved_for := [-1.0, -1.0]


## Switch the siege fix on for match `w`. FeatureRegistry calls this once at
## match start. An unknown value only gets a warning.
func install(w: World) -> void:
	var value := Game.variant(KEY)
	world = w
	match value:
		"gather3":
			gather = true
		"full":
			gather = true
			full = true
		"stall":
			# Judge the stall over the whole siege (both teams' admirals).
			Game.tunables["siege_stall_time"] = STALL_TIME
			Game.tunables["siege_stall_frac"] = STALL_FRAC
		_:
			push_warning("siege_fix: unknown value \"%s\" (use off, gather3, full or stall); nothing changed" % value)
			return
	if gather:
		# AdmiralSiege must never launch by itself: this module decides.
		Game.tunables["siege_gather_count"] = 9999
		Game.tunables["siege_gather_time"] = 1.0e9
	w.tick_hooks.append(_tick)


## One tick of `dt` seconds (World.tick_hooks): the gather decision twice a
## second, the formation and base race once a second, the stall watch.
func _tick(dt: float) -> void:
	if gather:
		_t_gather -= dt
		if _t_gather <= 0.0:
			_t_gather = 0.5
			for t in 2:
				_check_gather(t)
	_t_sec -= dt
	if _t_sec > 0.0:
		return
	_t_sec = 1.0
	if full:
		for t in 2:
			_update_formation(t)
			_check_race(t)
	if not gather:
		for t in 2:
			_watch_stall(t)


# --- gather3: when the assault starts -------------------------------------------------------

## Should team `t`'s siege leave "gather" for "assault" now? If so, do what
## AdmiralSiege does at that moment. Only for a team with an AI admiral.
func _check_gather(t: int) -> void:
	var ai: AdmiralAI = world.admiral_ai[t]
	var ts := world.teams[t]
	if ai == null or ts.siege_lane == "" or ts.siege_phase != "gather":
		return
	# Step 1: count the ships massed at the staging point (a big ship is 1, a
	# bomber 0.5), and the big ships alive.
	var stage := ts.siege_stage_point(ts.siege_lane)
	var radius := float(Rules.tune("siege_gather_radius", AdmiralSiege.GATHER_RADIUS))
	var bigs := 0
	var big_massed := 0
	var massed := 0.0
	for s: Ship in world.ships:
		if s.team != t or not s.alive:
			continue
		var is_big := s.size_class >= Rules.SIZE_LARGE
		if is_big:
			bigs += 1
		if not is_big and s.hull_id != "bomber":
			continue
		if s.global_position.distance_to(stage) < radius:
			if is_big:
				big_massed += 1
				massed += 1.0
			else:
				massed += BOMBER_WEIGHT
	# Step 2: go when min(3, big ships alive) are there, or after 90 s with 2+,
	# or after the hard cap whatever is there.
	var waited := world.time - ts.siege_t
	var go := massed >= float(mini(GATHER_MAX, bigs)) and bigs > 0
	go = go or (waited > GATHER_TIME and big_massed >= 2) or waited > GATHER_HARD_CAP
	if not go:
		return
	# Step 3: launch, as AdmiralSiege does (the waypoint moves at the next think).
	var ems := world.mothership(1 - t)
	ts.siege_phase = "assault"
	ts.siege_t = world.time
	ai.siege.contact_t = 0.0
	ai.siege.contact_ms_hp = ems.hull_frac() if ems != null else 1.0
	ai.waypoint_t = 0.0
	Game.count_usage("assaults_launched")
	Game.count_usage("assault_gather_ships", big_massed)


# --- full: formation -----------------------------------------------------------------------

## Is `s` one of its team's siege ships (a big ship or a bomber)?
static func _is_siege_ship(s: Ship) -> bool:
	return s.alive and (s.size_class >= Rules.SIZE_LARGE or s.hull_id == "bomber")


## Work out team `t`'s speed cap and group centre (see the header). INF means
## no cap now.
func _update_formation(t: int) -> void:
	cap[t] = INF
	var ts := world.teams[t]
	var ems := world.mothership(1 - t)
	if ts.siege_lane == "" or ts.siege_phase == "" or ems == null or not ems.alive:
		return
	# Step 1: the lead ship is the siege ship nearest the enemy hull.
	var lead: Ship = null
	var lead_d := INF
	for s: Ship in world.ships:
		if s.team == t and _is_siege_ship(s):
			var d := ems.hull_dist(s.global_position)
			if d < lead_d:
				lead_d = d
				lead = s
	if lead == null:
		return
	# Step 2: the group around the lead: its centre and its slowest top speed.
	var sum := Vector2.ZERO
	var n := 0
	var slowest := INF
	for s: Ship in world.ships:
		if s.team == t and _is_siege_ship(s) and s.global_position.distance_to(lead.global_position) < GROUP_RADIUS:
			sum += s.global_position
			n += 1
			slowest = minf(slowest, s.f_max)
	centre[t] = sum / float(n)
	cap[t] = CAP_FACTOR * slowest


## Called by PilotFlight.travel() for every flying AI ship: hold a siege ship
## back that is far ahead of its group (see "formation" in the header).
## Changes the ship's controls, nothing else.
func throttle(ship: Ship) -> void:
	if not full or float(cap[ship.team]) == INF or not _is_siege_ship(ship):
		return
	var ems := world.mothership(1 - ship.team)
	if ems == null:
		return
	# Step 1: only on the approach, and only for a ship well ahead of the group.
	var d := ems.hull_dist(ship.global_position)
	if d < CONTACT_FREE or ems.hull_dist(centre[ship.team]) - d < AHEAD_DIST:
		return
	# Step 2: too fast: stop thrusting (and boosting) until the group catches up.
	if ship.velocity.length() <= float(cap[ship.team]):
		return
	ship.controls.forward = minf(ship.controls.forward, 0.0)
	ship.controls.boost = false
	if world.time - float(_thr_t.get(ship.uid, -9.0)) >= 1.0:
		_thr_t[ship.uid] = world.time
		Game.count_usage("siege_throttles")


# --- full: base race -----------------------------------------------------------------------

## Team `t`'s early defend call (see "base race" in the header): 2 or more
## visible enemy big ships within 12,000 of our hull, closing at more than 40
## world units a second, while we run no siege of our own.
func _check_race(t: int) -> void:
	var ms := world.mothership(t)
	var ts := world.teams[t]
	var prev: Dictionary = _prev_d[t]
	var now := {}
	var seen: Array[Vector2] = []
	if ms != null and ms.alive:
		for s: Ship in world.ships:
			if s.team == t or not s.alive or s.size_class < Rules.SIZE_LARGE or not s.visible_to(t):
				continue
			var d := ms.hull_dist(s.global_position)
			if d >= RACE_RADIUS:
				continue
			now[s.uid] = d
			# Closing: its distance fell by more than 40 in the last second.
			if prev.has(s.uid) and float(prev[s.uid]) - d > RACE_CLOSING:
				seen.append(s.global_position)
	_prev_d[t] = now
	if ms == null or not ms.alive or seen.size() < 2 or ts.siege_lane != "":
		return
	# Step: meet them 1,500 towards our mothership from the middle of the push
	# (the same spot rule as TeamDefense) and keep the call on for 12 s.
	var centre_push := Vector2.ZERO
	for p in seen:
		centre_push += p
	centre_push /= float(seen.size())
	if not ts.defending(world.time):
		Events.feed.emit("%s capital ships are racing for the %s base: all pilots defend!" % [Rules.TEAM_NAMES[1 - t], Rules.TEAM_NAMES[t]], "team", t)
		Game.count_usage("base_races")
	ts.defend_point = centre_push.move_toward(ms.global_position, 1500.0)
	ts.defend_until = world.time + RACE_CALL


# --- stall: a siege that lived on ----------------------------------------------------------

## Once per second for "stall": count a siege that the old rule (15% in 120 s)
## would already have called off but the new one (10% in 240 s) kept alive.
func _watch_stall(t: int) -> void:
	var ai: AdmiralAI = world.admiral_ai[t]
	var ts := world.teams[t]
	if ai == null or ts.siege_phase != "assault" or ai.siege.contact_t <= 0.0:
		return
	var ems := world.mothership(1 - t)
	if ems == null or _saved_for[t] == ts.siege_t:
		return
	var since := world.time - ai.siege.contact_t
	if since > OLD_STALL_TIME and ems.hull_frac() > ai.siege.contact_ms_hp - OLD_STALL_FRAC:
		_saved_for[t] = ts.siege_t
		Game.count_usage("siege_stall_saved")
