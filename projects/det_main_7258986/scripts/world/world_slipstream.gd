class_name WorldSlipstream
extends Node2D
## WHAT THIS IS: the "Lane Slipstream" part of the world (feature A1 of the
## pacing_downtime fork). A pilot ship that is far BEHIND its own team's
## front line on a lane flies much faster along that lane, so the long
## trip back to the fight after every launch is shorter. It also draws a
## faint glowing band on each lane from the base up to the front.
##
## HOW IT WORKS: SlipstreamFeature makes one of these when the match starts
## and asks World to call tick() every game tick. Every 0.25 s evaluate()
## does this:
##   1. For each team and lane it finds the FRONT: how far along the lane
##      (arc length "s", measured from that team's own mothership) the
##      team's furthest live minion has got, or its furthest live finished
##      turret on that lane's ore nodes plus 1,500.
##   2. For each pilot ship it asks "is it slipping?". Yes when ALL are true:
##      it is within 1,600 of a lane line and in open space (never in the
##      jungle); on that lane it is at least 1,500 behind the front; it has
##      neither taken nor dealt damage for 4 s; no enemy pilot ship that
##      its team can see is within 2,500; and (for computer pilots) it is not
##      on a jungle job. A slipping ship has Ship.slip = true.
##   3. ShipStats calls apply() when it works out the ship's numbers: top
##      speed becomes twice the normal one but at most 1,000 (variant "on")
##      or exactly 1,100 for every hull (variant "flat"), the engine push is
##      raised so the ship really gets there (80% of the new top speed per
##      second) and boost is switched off.
## Every game tick (not only every 0.25 s) tick() also checks the ships that
## are slipping: a hit taken or dealt ends the slipstream at once (the
## ship's normal soft speed cap then bleeds the extra speed away in about a
## second). It adds up the pilot-seconds spent slipping, by hull size, into
## Game.usage ("slip_seconds", "slip_seconds_small", ... "_capital").
##
## WHO USES IT: SlipstreamFeature (scripts/features/slipstream.gd) makes it
## and hooks tick() into World.tick_hooks. ShipStats calls the static
## apply(). ShipStatus shows the SLIPSTREAM tag from Ship.slip.
##
## Words used here: the "front" of a lane is the furthest point along it
## that a team's minions or turrets hold; "arc length" is the distance
## walked along a lane line from its start (Util.project_on_polyline).

## Seconds between two evaluations of who is slipping.
const EVAL_EVERY := 0.25
## A ship must be at least this far (world units along the lane) behind the
## front to slip.
const BEHIND_FRONT := 1500.0
## A ship must be within this distance (world units) of a lane line to slip.
const LANE_REACH := 1600.0
## A finished turret holds the front this much (world units) further up the
## lane than its own spot.
const TURRET_BONUS := 1500.0
## Seconds without taking or dealing damage that a ship needs before it can
## start slipping.
const QUIET_TIME := 4.0
## A visible enemy pilot ship closer than this (world units) stops the
## slipstream.
const ENEMY_BLOCK := 2500.0
## Minions count for the front only when they are within this distance
## (world units) of the lane line.
const MINION_REACH := 2500.0
## Variant "on": the slipping top speed is this multiple of the normal one.
const SPEED_MULT := 2.0
## Variant "on": the slipping top speed never goes above this (world units
## per second).
const SPEED_CAP := 1000.0
## Variant "flat": the slipping top speed of every hull (world units per
## second).
const FLAT_SPEED := 1100.0
## While slipping the engine push is at least this share of the new top
## speed, per second (0.8 means it can reach top speed in 1.25 s).
const ACCEL_SHARE := 0.8
## A big ship has "arrived" when it is this close (world units) to the goal
## its brain flies to.
const ARRIVE_RADIUS := 2500.0
## Colour of the faint lane bands (alpha is set where they are drawn).
const BAND_COLOR := Color(0.55, 0.9, 1.0)

## The running match.
var world: World
## True for the "flat" variant (every hull slips at the same speed).
var flat := false
## True for the "probe" value: nobody slips, only the arrival times of big
## ships are measured (so the same measure can be taken on the normal game).
var probe := false
## The big ships whose arrival has already been measured: Ship -> true.
var _arrived := {}
## Seconds until the next evaluation.
var _eval_t := 0.0
## Lane lines as each team walks them: team -> lane id -> points. Made once.
var _lines: Array = [{}, {}]
## The front of each team's lane: team -> lane id -> arc length (world
## units), or -1 when the team holds nothing on that lane.
var fronts: Array = [{}, {}]
## The ships slipping right now.
var slipping: Array[Ship] = []
## Match time (seconds) at which each slipping ship started: Ship -> time.
var _since := {}
## The damage total of each slipping ship's pilot when it started: Ship ->
## PilotProfile.damage_done. A rise means the ship dealt damage.
var _dealt_at_start := {}
## For every pilot: [damage_done last seen, match time it last changed].
## Used to know "has not dealt damage for 4 s": PilotProfile -> Array.
var _dealt_seen := {}
## Pilot-seconds slipping that are not yet counted in Game.usage, by hull
## size name ("small" ... "capital").
var _pending := {"small": 0.0, "medium": 0.0, "large": 0.0, "capital": 0.0}


## Remember the world and the variant value ("flat" and "probe" flags), make
## the lane lines and draw under the units. SlipstreamFeature calls this
## once.
func setup(w: World, is_flat: bool, is_probe: bool) -> void:
	world = w
	flat = is_flat
	probe = is_probe
	z_index = -3
	for t in 2:
		for lane: String in MapLayout.LANE_ORDER:
			_lines[t][lane] = MapLayout.lane_points(lane, t)
			fronts[t][lane] = -1.0


## The tick hook (World.tick_hooks): end the slipstream of any ship that was
## hit or fired, count the slipping time, and every EVAL_EVERY seconds work
## out who slips (evaluate()). `dt` is the tick length in seconds.
func tick(dt: float) -> void:
	# Step 1: ships already slipping: stop at once on a hit taken or dealt.
	if not slipping.is_empty():
		for s in slipping.duplicate():
			if not is_instance_valid(s) or not s.alive or s.last_damage_time >= float(_since[s]) \
					or s.profile.damage_done > float(_dealt_at_start[s]) + 0.001:
				_stop(s)
		# Step 2: count the pilot-seconds that are left, by hull size.
		for s in slipping:
			var tier: String = Tech.TIERS[s.size_class]
			_pending[tier] = float(_pending[tier]) + dt
		_flush_usage()
	# Step 3: the 0.25 s evaluation.
	_eval_t -= dt
	if _eval_t <= 0.0:
		_eval_t = EVAL_EVERY
		evaluate()


## Work out the fronts, then switch each pilot ship's slipstream on or off
## (see HOW IT WORKS, steps 1 and 2).
func evaluate() -> void:
	_measure_arrivals()
	if probe:
		return
	_update_fronts()
	for s: Ship in world.ships:
		if not s.alive or s.profile == null:
			continue
		var ok := _qualifies(s)
		if ok and not s.slip:
			_start(s)
		elif not ok and s.slip:
			_stop(s)
	queue_redraw()


## Measure how long big ships (frigates and capital ships flown by the AI)
## take from launch to arrive (within ARRIVE_RADIUS of the goal their brain
## flies to, in lane state). Each trip is added once to Game.usage:
## "big_arrivals" (how many), "big_arrival_s_sum" (seconds added up) and
## "big_arrival_s_sq" (squared seconds added up), so the mean is sum / n and
## the spread (standard deviation) is sqrt(sq / n - mean^2). It is the
## "big-ship arrival spread" the A1b report needs; it only reads the game,
## never changes it.
func _measure_arrivals() -> void:
	# Step 1: forget ships that are gone.
	for key in _arrived.keys():
		if not is_instance_valid(key) or not (key as Ship).alive:
			_arrived.erase(key)
	# Step 2: each big AI ship that has not arrived yet.
	for s: Ship in world.ships:
		if not s.alive or s.size_class < Rules.SIZE_LARGE or _arrived.has(s) or not (s.controller is PilotAI):
			continue
		var brain := s.controller as PilotAI
		var trip := world.time - s.launched_at
		if brain.state == "lane" and trip > 1.0 and s.global_position.distance_to(brain.goal) < ARRIVE_RADIUS:
			_arrived[s] = true
			Game.count_usage("big_arrivals")
			Game.count_usage("big_arrival_s_sum", int(round(trip)))
			Game.count_usage("big_arrival_s_sq", int(round(trip * trip)))


## Recompute fronts[team][lane] from the live minions and finished turrets.
func _update_fronts() -> void:
	# Step 1: start from "nothing held".
	for t in 2:
		for lane: String in MapLayout.LANE_ORDER:
			fronts[t][lane] = -1.0
	# Step 2: each live minion near its lane line pushes its team's front on.
	for m in world.minions:
		if not m.alive or m.team > 1 or not _lines[m.team].has(m.lane):
			continue
		var pr := Util.project_on_polyline(m.global_position, _lines[m.team][m.lane])
		if float(pr["dist"]) < MINION_REACH and float(pr["s"]) > float(fronts[m.team][m.lane]):
			fronts[m.team][m.lane] = float(pr["s"])
	# Step 3: each live finished turret holds the front 1,500 further on.
	for tu in world.turrets:
		if not tu.alive or not tu.is_built() or tu.team > 1 or tu.node == null or not _lines[tu.team].has(tu.node.lane):
			continue
		var pr2 := Util.project_on_polyline(tu.global_position, _lines[tu.team][tu.node.lane])
		var s_turret := float(pr2["s"]) + TURRET_BONUS
		if s_turret > float(fronts[tu.team][tu.node.lane]):
			fronts[tu.team][tu.node.lane] = s_turret


## Does ship `s` slip right now? (All the conditions of HOW IT WORKS, step 2.)
func _qualifies(s: Ship) -> bool:
	var now := world.time
	# Step 1: quiet for 4 s: nothing hit it, it dealt no damage (the profile's
	# damage total did not change) and it did not hurt an enemy ship.
	var p := s.profile
	var seen: Array = _dealt_seen.get(p, [p.damage_done, -999.0])
	if p.damage_done != float(seen[0]):
		seen = [p.damage_done, now]
	_dealt_seen[p] = seen
	if now - s.last_damage_time < QUIET_TIME or now - s.aggro_time < QUIET_TIME or now - float(seen[1]) < QUIET_TIME:
		return false
	# Step 2: computer pilots on a jungle job do not slip (their route leaves
	# the lane through narrow gates and they brake for them by top speed).
	if s.controller is PilotAI and (s.controller as PilotAI).state == "jungle":
		return false
	# Step 3: open space only (never inside the jungle).
	if not world.map.in_open_lane(s.global_position):
		return false
	# Step 4: a lane within 1,600 whose front is at least 1,500 ahead of us.
	var behind := false
	for lane: String in MapLayout.LANE_ORDER:
		var front := float(fronts[s.team][lane])
		if front < 0.0:
			continue
		var pr := Util.project_on_polyline(s.global_position, _lines[s.team][lane])
		if float(pr["dist"]) <= LANE_REACH and float(pr["s"]) <= front - BEHIND_FRONT:
			behind = true
			break
	if not behind:
		return false
	# Step 5: no enemy pilot ship that we can see within 2,500.
	for e: Ship in world.ships:
		if e.team != s.team and e.alive and e.visible_to(s.team) and e.global_position.distance_to(s.global_position) < ENEMY_BLOCK:
			return false
	return true


## Switch the slipstream on for ship `s` and remember when and how much
## damage its pilot had dealt (so a later hit or shot can end it at once).
func _start(s: Ship) -> void:
	s.slip = true
	s.stats_dirty = true
	slipping.append(s)
	_since[s] = world.time
	_dealt_at_start[s] = s.profile.damage_done


## Switch the slipstream off for ship `s` (its stats are worked out again on
## its next turn; the soft speed cap then slows it down).
func _stop(s: Ship) -> void:
	slipping.erase(s)
	_since.erase(s)
	_dealt_at_start.erase(s)
	if is_instance_valid(s):
		s.slip = false
		s.stats_dirty = true


## Move whole seconds of slipping time from _pending into Game.usage:
## "slip_seconds" (all hulls) and "slip_seconds_<size>".
func _flush_usage() -> void:
	for tier: String in _pending:
		var whole := int(floor(float(_pending[tier])))
		if whole > 0:
			_pending[tier] = float(_pending[tier]) - float(whole)
			Game.count_usage("slip_seconds", whole)
			Game.count_usage("slip_seconds_" + tier, whole)


## Raise the numbers of slipping ship `ship` (ShipStats.recompute calls this
## at its very end, only while Ship.slip is true): the top speed, the engine
## push, and no boost. An EMP'd ship is left alone.
static func apply(ship: Ship) -> void:
	if ship.emp_t > 0.0:
		return
	var is_flat := Game.variant("slipstream") == "flat"
	var top := FLAT_SPEED if is_flat else minf(SPEED_CAP, ship.f_max * SPEED_MULT)
	ship.f_max = top
	ship.f_accel = maxf(ship.f_accel, ACCEL_SHARE * top)
	ship.can_boost = false


## Draw the faint glowing band of each shown team's lanes from the base up to
## the front. A spectator sees both teams' bands, a player only their own.
func _draw() -> void:
	if world == null:
		return
	for t in 2:
		if world.viewer_team >= 0 and world.viewer_team != t:
			continue
		for lane: String in MapLayout.LANE_ORDER:
			var front := float(fronts[t][lane])
			if front <= 0.0:
				continue
			# The lane line from the base to the front, cut into short pieces.
			var pts := PackedVector2Array()
			var step := 400.0
			var s := 0.0
			while s < front:
				pts.append(Util.polyline_at(_lines[t][lane], s))
				s += step
			pts.append(Util.polyline_at(_lines[t][lane], front))
			if pts.size() < 2:
				continue
			var col := BAND_COLOR.lerp(Palette.team(t), 0.5)
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.07), 280.0, true)
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.16), 90.0, true)
