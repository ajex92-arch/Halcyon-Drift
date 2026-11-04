class_name PilotGoals
extends RefCounted
## WHAT THIS IS: the part of an AI pilot's brain (PilotAI) that decides
## WHERE to fly. Each think it sets the brain's `goal` for the current
## state and, on a lane or in the jungle, which target to go for.
##
## HOW IT WORKS:
##   - think_lane(): find our "station" on the lane (a spot just behind our
##     minion wave, spread sideways by seat), and move it for special jobs:
##     the admiral's rally waypoint, defending a turret, a siege, defending
##     the mothership, or a test's hold point. Never park under an enemy
##     turret that our minions aren't tanking, and never on top of one of our
##     own turrets. Then choose what to attack: the enemy mothership during
##     an assault, a structure to push, an enemy pilot to hunt, and, with
##     nothing else to do, an enemy minion near our wave's front minion to
##     farm (fly out to gun reach of it and shoot, last hits first).
##   - the opening (opening_active(), opening_goal()): at the start of the
##     match the station is somewhere else. For the first
##     Rules.AI_OPENING_HOLD (10) seconds every AI pilot waits near its own
##     mothership, so a human player can get their bearings. Then it flies
##     to its lane's Crossing node (the ore node on the centre line) and
##     contests it, even before any minion has launched. The opening ends
##     when our first minion wave reaches that Crossing (or at
##     Rules.AI_OPENING_MAX seconds), and the pilot goes back to the
##     normal station behind the wave. Junglers count as "mid" for this:
##     they contest The Crossing in the middle. The flex pilot contests the
##     Crossing of the lane its rotation starts on, the top lane (see
##     rotation_lane() and FLEX_ROTATION_SHIFT), and keeps that one for the
##     whole opening.
##   - think_jungle(): small ships pick the nearest derelict camp (camps on
##     our half of the map first) and clear it. A jungler joins the opening
##     first and goes to its camp when the opening ends.
##   - think_home(): retreating, or going home to shop: fly to a repair bay
##     or to the mothership, and ask to dock when close to it.
##
## WHO USES IT: PilotAI._think() calls think_lane, think_jungle or
## think_home, depending on PilotAI.state. It asks PilotTargeting what to
## shoot and PilotSenses about turrets and allies, and reads the admiral's
## orders from TeamState (waypoint, siege, defend).
##
## Words used here:
##   lane     one of the three wide flight paths ("top", "mid", "bot") that
##            run from one mothership to the other. Each team walks a lane
##            from its own mothership's end, so "how far along the lane"
##            (`s`, in world units) is 0 at our end.
##   station  the spot on the lane where we park while waiting for fights.
##   siege    the admiral's order to attack the enemy mothership along one
##            lane: first "gather" at a staging point, then "assault".
##   tanking  our minions stand in an enemy turret's range, so it shoots
##            them instead of us.
##   farm     to fly out to an enemy minion near our wave's front minion and
##            shoot it, hoping for the last hit (the one that pays), instead
##            of waiting at the station for a target to come into range.
##   opening  the first minutes of a match, before our first minion wave
##            gets to the middle of the map (see the list above).
##   Crossing one of the three ore nodes on the centre line, x = 20000: the
##            Top Crossing, The Crossing and the Bottom Crossing (kind
##            "middle" in MapLayout.NODES).

## How far (world units) short of the point level with a Crossing node on
## the lane our wave's front minion may still be and count as "arrived".
## (A little early, so the pilots there turn to escort the wave as it comes
## up instead of waiting for it to pass.)
const OPENING_ARRIVE := 300.0
## In the opening, how far (world units) from the Crossing node's centre we
## stand, on our side of it, in the first row. It clears the node's ore
## rocks (radius 560) and the turret spots just outside them.
const OPENING_STAND_OFF := 800.0
## The gap (world units) between neighbouring pilots' spots, at the
## Crossing and at the hold spot by the mothership.
const OPENING_SPACING := 350.0
## In the first seconds, how far (world units) past the mothership's bow
## the nearest row of hold spots lies.
const OPENING_HOLD_OUT := 600.0
## When we fall back during the opening, how far (world units) we back off
## toward our side.
const OPENING_FALLBACK := 2200.0
## Moves where the flex pilot's lane rotation starts (user decision,
## 2026-10-17: "Start rotation on a side lane"). The lane is picked from
## MapLayout.LANE_ORDER (top, mid, bot) by (seat number + this + the number
## of 90-second periods so far) modulo 3. With 0 the flex pilot (seat 7)
## started on the middle lane; with 2 it starts on the top lane and goes on
## to the middle, then the bottom, then the top again, for the whole match.
## Both teams use the same number, so the two flex pilots start on the same
## lane (top stays top when the map is mirrored left to right, so the two
## sides stay symmetric).
const FLEX_ROTATION_SHIFT := 2

## The pilot brain this part belongs to (we read its profile and timers,
## and set its goal, target, state and camp). It is reached through a weak
## link: see `_ai_ref`.
## Speed: every use of `ai` goes through the weak link (a small lookup), so each function below looks it up once into a local, `brain`, and uses that.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain. The brain holds this part with a normal
## (strong) link. If the part held the brain strongly too, each would keep
## the other alive forever and Godot could never free them (a memory leak).
## A weak link points at the brain without keeping it alive.
var _ai_ref: WeakRef


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


# --- lane -----------------------------------------------------------------------------------

## Our lane: our role if it is "top", "mid" or "bot", otherwise "mid".
func lane_id() -> String:
	var brain := ai
	return brain.profile.role if brain.profile.role in ["top", "mid", "bot"] else "mid"


## The furthest point our minions hold on a lane (how far our wave has
## pushed toward the enemy). Only minions within 2,500 of the lane line
## count. With no wave out, we hold near our inner node on this lane (the
## resource node near our mothership, where turrets get built): 80% of the
## way from the node to the lane line. With no such node, a quarter of the
## way along the lane.
func lane_front(lane: String, team: int) -> Vector2:
	var brain := ai
	var world := brain.world
	var pts := MapLayout.lane_points(lane, team)
	# Step 1: the furthest-along live minion of ours on this lane.
	var best_s := wave_front_s(lane, team)
	# Step 2: no wave out: hold near our inner node on this lane.
	if best_s < 0.0:
		for n in world.nodes:
			if n.lane == lane and n.node_kind == "inner" and n.side == team:
				return n.global_position + (Util.project_on_polyline(n.global_position, pts)["point"] - n.global_position) * 0.8
		best_s = Util.polyline_length(pts) * 0.25
	return Util.polyline_at(pts, best_s)


## How far along `lane` (`s`, in world units from `team`'s end) the front of
## that team's live minion wave has got, or -1 with no wave out. Only
## minions within 2,500 of the lane line count.
func wave_front_s(lane: String, team: int) -> float:
	var pts := MapLayout.lane_points(lane, team)
	var best_s := -1.0
	for m in ai.world.minions:
		if m.team != team or not m.alive or m.lane != lane:
			continue
		var pr := Util.project_on_polyline(m.global_position, pts)
		if float(pr["dist"]) < 2500.0 and float(pr["s"]) > best_s:
			best_s = pr["s"]
	return best_s


## The front minion of `team`'s live wave on `lane`: the minion that
## wave_front_s() measures (the furthest along the lane, among those within
## 2,500 of the lane line), or null with no wave out.
func front_minion(lane: String, team: int) -> Minion:
	var pts := MapLayout.lane_points(lane, team)
	var best: Minion = null
	var best_s := -1.0
	for m in ai.world.minions:
		if m.team != team or not m.alive or m.lane != lane:
			continue
		var pr := Util.project_on_polyline(m.global_position, pts)
		if float(pr["dist"]) < 2500.0 and float(pr["s"]) > best_s:
			best_s = pr["s"]
			best = m
	return best


## The lane the flex pilot works at match time `t` (seconds): it moves to the
## next lane (top, mid, bot, in MapLayout.LANE_ORDER) every 90 seconds, and
## its seat number plus FLEX_ROTATION_SHIFT sets where it starts (seat 7
## starts on the top lane).
func rotation_lane_at(t: float) -> String:
	return MapLayout.LANE_ORDER[(int(t / 90.0) + ai.profile.slot + FLEX_ROTATION_SHIFT) % 3]


## The lane the flex pilot works right now (rotation_lane_at() for the
## world's clock).
func rotation_lane() -> String:
	return rotation_lane_at(ai.world.time)


## The lane whose Crossing this pilot contests in the opening: our own lane
## (lane_id()), which is the middle for junglers; for the flex pilot the lane
## its rotation starts on, kept for the whole opening (so it does not leave a
## Crossing at 90 s, just before its wave gets there).
func opening_lane() -> String:
	return rotation_lane_at(0.0) if ai.profile.role == "flex" else lane_id()


## The Crossing node of `lane` (the "middle" ore node on it), or null.
func crossing_node(lane: String) -> ResourceNode:
	for n in ai.world.nodes:
		if n.node_kind == "middle" and n.lane == lane:
			return n
	return null


## Is this pilot in the opening? True for the first Rules.AI_OPENING_HOLD
## seconds, and after that until our first minion wave has reached our lane's
## Crossing node (the wave's front is level with the node, less
## OPENING_ARRIVE), or until Rules.AI_OPENING_MAX seconds of match time.
## The arrival is a fact about the team and the lane, not about this pilot:
## it is noted once in TeamState.first_wave_at (_note_first_waves()), by
## whichever pilot of the team looks first, and every pilot's opening ends by
## it, also a pilot that was dead, docked, retreating or flying home when the
## wave got there (it used to start a second opening when that wave died
## before the next one came). When the opening ends it ends for good:
## PilotAI.opening_done is set and this stays false from then on. The lane is
## opening_lane(): our own lane, the middle for junglers, and for the flex
## pilot the lane its rotation starts on.
func opening_active() -> bool:
	var brain := ai
	if brain.opening_done:
		return false
	var world := brain.world
	if world.time >= Rules.AI_OPENING_MAX:
		brain.opening_done = true
		return false
	if world.time < Rules.AI_OPENING_HOLD:
		return true
	var lane := opening_lane()
	if crossing_node(lane) == null:
		brain.opening_done = true
		return false
	var ts: TeamState = world.teams[brain.profile.team]
	_note_first_waves(ts)
	if ts.first_wave_at.has(lane):
		brain.opening_done = true
		return false
	return true


## Note, in TeamState.first_wave_at, every lane of team `ts` whose first
## minion wave has now reached that lane's Crossing node (its front is level
## with the node, less OPENING_ARRIVE) and is not noted yet. It looks at all
## three lanes, whichever lane the asking pilot flies, so the arrival is
## noted even when no pilot of that lane is flying at that moment. A lane
## stays noted for the whole match.
func _note_first_waves(ts: TeamState) -> void:
	var now := ai.world.time
	for lane: String in MapLayout.LANE_ORDER:
		if ts.first_wave_at.has(lane):
			continue
		var node := crossing_node(lane)
		if node == null:
			continue
		var s_node: float = Util.project_on_polyline(node.global_position, MapLayout.lane_points(lane, ts.team))["s"]
		if wave_front_s(lane, ts.team) >= s_node - OPENING_ARRIVE:
			ts.first_wave_at[lane] = now


## Where to fly during the opening: a spot by our mothership's bow for the
## first Rules.AI_OPENING_HOLD seconds, then our spot at our lane's
## Crossing node. The Crossing spot is on our side of the node (toward our
## mothership), OPENING_STAND_OFF from its centre in the first row and
## OPENING_SPACING further back in the second row, and spread toward the
## lane line by seat so pilots do not stack (seat / 2 gives each pilot of a
## lane its own place, six of them at the middle). While falling back we
## back off OPENING_FALLBACK toward our side.
func opening_goal(ship: Ship) -> Vector2:
	var brain := ai
	var lane := opening_lane()
	var node := crossing_node(lane)
	if brain.world.time < Rules.AI_OPENING_HOLD or node == null:
		return _opening_hold_spot(ship)
	var toward := Vector2(-1.0 if ship.team == Rules.HALCYON else 1.0, 0.0)
	var pts := MapLayout.lane_points(lane, ship.team)
	var inward := (Vector2(Util.project_on_polyline(node.global_position, pts)["point"]) - node.global_position).normalized()
	var idx := brain.profile.slot >> 1
	var col := idx % 3
	var row := 1 if idx >= 3 else 0
	var spot := node.global_position + toward * (OPENING_STAND_OFF + OPENING_SPACING * float(row)) + inward * (OPENING_SPACING * float(col))
	if brain.fallback_t > 0.0:
		spot += toward * OPENING_FALLBACK
	return spot


## The pilot's own spot for the opening hold: past our mothership's bow, in
## a grid of 3 rows (deeper out) by 4 columns (side to side) picked by seat,
## so all 12 seats of a team get a different spot.
func _opening_hold_spot(ship: Ship) -> Vector2:
	var ms := ai.world.mothership(ship.team)
	if ms == null:
		return ship.global_position
	var slot := ai.profile.slot
	var ahead := Vector2.from_angle(ms.rotation)
	var side := Util.starboard_of(ms.rotation)
	return ms.global_position + ahead * (ms.half_len + OPENING_HOLD_OUT + OPENING_SPACING * float(slot % 3)) + side * (float(slot % 4) - 1.5) * OPENING_SPACING


## Lane state: choose our station, keep out from under enemy turrets, then
## choose what to attack (assault, push, prey or farm). Sets the brain's goal,
## target, lock_target and intent.
func think_lane(ship: Ship) -> void:
	var brain := ai
	var world := brain.world
	var ts := world.teams[ship.team]
	# Step 1: where we'd like to park (this sets ai.goal). `free_lane` is the
	# lane of a plain station behind our wave, or "" when the opening or an
	# order (rally, defend, siege, hold point) put the goal somewhere else.
	var free_lane := _pick_station(ship, ts)
	var station := brain.goal
	# Step 2: don't park under an enemy turret unless our minions are
	# tanking it: move to 350 outside its range instead. Large and capital
	# ships ignore PD turrets (they shrug off their fire).
	for t in world.turrets:
		if t.team == ship.team or not t.alive or not t.is_built():
			continue
		var shrugs := ship.size_class >= Rules.SIZE_LARGE and t.ttype == "pd"
		if brain.goal.distance_to(t.global_position) < t.range_r + 250.0 and not brain.senses.minions_tanking(t, ship.team) and not shrugs:
			brain.goal = t.global_position + (brain.goal - t.global_position).normalized() * (t.range_r + 350.0)
	# Step 3: the best target near us. While falling back, that's all.
	brain.target = brain.targeting.pick_target(ship, PilotTargeting.engage_range(ship))
	brain.intent = ""
	if brain.fallback_t > 0.0:
		return
	# Step 4: assault. Once the enemy mothership is in reach, big ships put
	# their main guns on it; their point defense and flak deal with the
	# defenders (who respawn right there and would otherwise soak every
	# shot).
	if ts.siege_phase == "assault" and not ship.is_small():
		var ems := world.mothership(1 - ship.team)
		if ems != null and ems.alive and ems.hull_dist(ship.global_position) < PilotTargeting.main_reach(ship) * 1.05:
			brain.target = ems
			brain.lock_target = ems
			brain.intent = "push"
			brain.goal = PilotTargeting.standoff(ship, ems, station)
			return
	# Step 5: push. A structure our minions are tanking near our front (or
	# one a big ship can take on its own). It beats farming minions, but we
	# don't drop a pilot we're already fighting for it.
	var push := brain.targeting.push_target(ship, station)
	if push != null and (brain.target == null or brain.target.kind == Unit.K_MINION or brain.target == push):
		brain.target = push
		brain.lock_target = push
		brain.intent = "push"
		brain.goal = PilotTargeting.standoff(ship, push, station)
		return
	# Step 6: skirmish. Hunt an enemy pilot near our station when it's a
	# fair fight (unless we're already shooting a pilot).
	if brain.target == null or brain.target.kind != Unit.K_SHIP:
		var prey := brain.targeting.prey(ship, station)
		if prey != null:
			brain.target = prey
			brain.lock_target = prey
			brain.intent = "prey"
	# Step 7: farm. Nothing to shoot, no structure to push, no pilot to hunt,
	# and the goal is a plain station behind our wave (no order): fly out to
	# the best enemy minion near our wave's front minion, to gun reach of it
	# on our side of it, and shoot it (PilotTargeting.farm_target()).
	if brain.target == null and free_lane != "":
		var front := front_minion(free_lane, ship.team)
		if front != null:
			var farm := brain.targeting.farm_target(ship, front)
			if farm != null:
				brain.target = farm
				brain.lock_target = farm
				brain.intent = "farm"
				brain.goal = PilotTargeting.standoff(ship, farm, station)


## Set the brain's goal to our station on the lane: behind our wave front
## by a distance that grows with our size, spread sideways by seat (and
## kept off our own turrets), then moved for the admiral's orders, a turret
## in trouble, or a hold point. Each later step wins over the earlier ones.
## In the opening (see opening_active()) the first station is
## opening_goal() instead, unless a human admiral's waypoint rally applies
## to this seat (the AI admiral's waypoint does not count in the opening);
## the orders in the later steps (turret in trouble, siege, defend, hold
## point) still win. Returns the lane of the station when it is the plain
## station behind our wave, or "" when the opening or an order moved it.
func _pick_station(ship: Ship, ts: TeamState) -> String:
	var brain := ai
	var world := brain.world
	var profile := brain.profile
	# Step 1: which lane. Laners use their own; the flex pilot moves to the
	# next lane every 90 seconds.
	var lane := lane_id()
	if profile.role == "flex":
		lane = rotation_lane()
	# Late game (after 10:00): one laner from each lane (the middle seats 4,
	# 5 and 6) and the flex gather on the admiral's waypoint while it is up.
	# (Playtest: the odd seats are the whole mid trio, 1, 5 and 9, so mid
	# stood empty for up to a third of the time.) In the opening the same
	# seats obey a waypoint too, whatever the time, but only one a HUMAN
	# admiral placed (TeamState.waypoint_by_human): a human admiral's order
	# wins over the opening. The AI admiral's own waypoint, which goes up at
	# 60 s in every match, does not: it would pull those seats off their
	# Crossings while the waves are still on their way (DESIGN.md C25).
	var opening := opening_active()
	var rally := ts.has_waypoint() and (world.time > 600.0 or (opening and ts.waypoint_by_human)) and (profile.slot in [4, 5, 6] or profile.role == "flex")
	# Feature hook (the group_late variant, GroupLateFeature): after 25:00 it
	# replaces this rally with its own grouping on the push lane. `grouped`
	# is empty (nothing changes) unless the feature is on, active for our
	# team, and wants this seat to move.
	var grouped := {}
	if not world.features.is_empty() and world.features.has("group_late"):
		var grp: Object = world.features["group_late"]
		if grp.call("active", ship.team):
			rally = false
			grouped = grp.call("plan_for", ship, profile)
	if rally:
		lane = world.map.lane_for(ts.waypoint)
	elif not grouped.is_empty():
		lane = grouped["lane"]
	# Is the goal going to be the plain station behind our wave? (False in the
	# opening, under a rally or a feature's grouping, and, below, whenever an
	# order sets the goal.)
	var plain := not opening and not rally and grouped.is_empty()
	# The opening (no admiral order, no feature grouping): our own lane
	# (the middle for junglers and the flex pilot), and the station is the
	# one opening_goal() gives instead of a spot behind the wave.
	var pts: PackedVector2Array
	if opening and not rally and grouped.is_empty():
		lane = opening_lane()
		pts = MapLayout.lane_points(lane, ship.team)
		brain.goal = opening_goal(ship)
	else:
		# Step 2: stand back from our wave front: 500 (small), 750 (medium),
		# 900 (large) or 1,100 (capital), plus 2,200 more while falling back.
		pts = MapLayout.lane_points(lane, ship.team)
		var front := lane_front(lane, ship.team)
		var pr := Util.project_on_polyline(front, pts)
		var back := float([500.0, 750.0, 900.0, 1100.0][Rules.size_index(ship.size_class)])
		if brain.fallback_t > 0.0:
			back += 2200.0
		var s_goal := maxf(0.0, float(pr["s"]) - back)
		if not grouped.is_empty():
			s_goal = maxf(0.0, float(grouped["s_goal"]) - (2200.0 if brain.fallback_t > 0.0 else 0.0))
		if rally:
			# Hold at the waypoint unless the wave front is further on: move up
			# to 600 short of it, unless our station is already closer or past.
			var s_wp: float = Util.project_on_polyline(ts.waypoint, pts)["s"]
			s_goal = maxf(minf(s_goal, s_wp), s_wp - 600.0) if s_goal < s_wp else s_goal
		brain.goal = Util.polyline_at(pts, s_goal)
		# Step 3: spread pilots across the lane so they don't stack on one spot
		# (450 to one side, the middle, or 450 to the other side, by seat; a very big
		# hull, whose radius times 2.2 is more than 450, spreads by that instead, so
		# neighbours do not overlap).
		var side := Util.port_of((Util.polyline_at(pts, s_goal + 50.0) - Util.polyline_at(pts, s_goal)).angle())
		brain.goal += side * float((profile.slot % 3) - 1) * maxf(450.0, ship.radius * 2.2)
		# Step 3b: keep the station off our own turrets. A ship cannot fly into
		# one (they are solid), and a pilot counts as arrived once it is within
		# 160 of its goal (PilotCombat.steer), so a station nearer a turret
		# than its hull plus our radius plus 160 moves out along the line from
		# the turret's centre to that distance. (A turret slot lies 500 off the
		# lane line at the outer Crossings, so the 450 spread alone would put a
		# station on it.)
		for t in world.turrets:
			if t.team != ship.team or not t.alive:
				continue
			var clear: float = t.radius + ship.radius + 160.0
			var away: Vector2 = brain.goal - t.global_position
			if away.length() < clear:
				brain.goal = t.global_position + (away.normalized() if away.length() > 0.0 else side) * clear
	# Step 4: defend our turrets on this lane when enemy pilots are hitting
	# them (if within 9,000 of us, and not while falling back): park 300
	# from the turret, toward our end of the lane.
	var threatened := brain.senses.turret_under_attack(ship.team, lane)
	if threatened != null and brain.fallback_t <= 0.0 and threatened.global_position.distance_to(ship.global_position) < 9000.0:
		brain.goal = threatened.global_position + (Util.polyline_at(pts, 0.0) - threatened.global_position).normalized() * 300.0
		plain = false
	# Step 5: siege. When our admiral declares one (TeamState.siege_lane),
	# big ships and bombers converge on that lane and close on the enemy
	# mothership - the only win condition (playtest: 17 turrets fell in a
	# match but no mothership was ever touched while big ships held separate
	# stations).
	if brain.fallback_t <= 0.0 and ts.siege_lane != "" and (not ship.is_small() or ship.hull_id == "bomber"):
		plain = false
		if ts.siege_phase == "gather":
			# Mass at the staging point (spread 400 around it by seat) so the
			# slow capitals arrive together.
			brain.goal = ts.siege_stage_point(ts.siege_lane) + Vector2.from_angle(float(profile.slot) * 1.3) * 400.0
		else:
			brain.goal = siege_point(ts.siege_lane, ship)
	# Step 6: defend the mothership. Corvettes and bigger come back from far
	# (18,000), strike craft only from nearby (12,000), so the lanes keep
	# their pressure elsewhere. We ring the defend point 300 to 750 out
	# (bigger ships further), placed around it by seat.
	var answer_r := 18000.0 if not ship.is_small() else 12000.0
	if ts.defending(world.time) and ship.global_position.distance_to(ts.defend_point) < answer_r:
		brain.goal = ts.defend_point + Vector2.from_angle(float(profile.slot) * 0.9) * (300.0 + 150.0 * float(Rules.size_index(ship.size_class)))
		plain = false
	# Step 7: a test (or an order) pinned us to a point.
	if brain.hold_point != Vector2.INF:
		brain.goal = brain.hold_point
		plain = false
	return lane if plain else ""


## The point on our siege lane just inside our weapon reach (80% of our
## main reach) of the enemy mothership's hull. We walk back along the lane
## from where the mothership is now (it may have moved up the lane).
func siege_point(lane: String, ship: Ship) -> Vector2:
	var brain := ai
	var world := brain.world
	var ems := world.mothership(1 - ship.team)
	var pts := MapLayout.lane_points(lane, ship.team)
	var want := PilotTargeting.main_reach(ship) * 0.8
	var on := world.teams[ship.team].enemy_ms_on_lane(lane)
	if float(on["dist"]) > 4000.0:
		# The mothership is more than 4,000 off this lane (the admiral
		# re-targets the siege): close on it straight from here.
		return ems.global_position + (ship.global_position - ems.global_position).normalized() * (want + ems.half_len)
	# Binary search along the 15,000 of lane before it (the hull distance
	# shrinks as the lane closes on the mothership). Like guessing a number
	# by halving the range each time: 12 halvings narrow 15,000 down to
	# about 4 world units.
	var hi: float = on["s"]
	var lo := maxf(0.0, hi - 15000.0)
	for _i in 12:
		var mid := (lo + hi) * 0.5
		if ems.hull_dist(Util.polyline_at(pts, mid)) >= want:
			lo = mid
		else:
			hi = mid
	return Util.polyline_at(pts, lo)


# --- jungle and home ------------------------------------------------------------------------

## Jungle state. Big ships can't fly the jungle, so they go back to the
## lane. Small ships pick a derelict camp (the nearest, with camps on the
## enemy's half counting 6,000 further), fly to 450 from it, and shoot it
## once within 1,200 if nothing better is in range. With no camp, back to
## the lane.
func think_jungle(ship: Ship) -> void:
	var brain := ai
	if not ship.is_small():
		brain.state = "lane"
		return
	# Step 0: the opening. A jungler goes out with the lane pilots first (to
	# the middle Crossing: lane_id() is "mid" for it) and does everything a
	# lane pilot does there, including obeying the orders that win over the
	# opening (defend, hold point). Its camps wait until our first wave
	# reaches the Crossing; the state stays "jungle", so the camp choice
	# below simply starts then.
	if opening_active():
		think_lane(ship)
		return
	# Step 1: our camp is gone (or we have none): choose a new one.
	if brain.camp == null or not is_instance_valid(brain.camp) or not brain.camp.alive:
		brain.camp = null
		# Start a camp only with most of our hull (shields regenerate on the
		# way).
		if ship.hull_frac() < 0.6:
			brain.state = "retreat"
			return
		var bd := INF
		var lone := brain.senses.allies_near(ship, 2200.0) == 0
		for d: Unit in brain.world.jungle_director.live_camps():
			# Carriers (they launch snub fighters) are a two-pilot job, or a
			# Lance's.
			if lone and (d as Derelict).ctype == "carrier" and ship.hull_id != "lance":
				continue
			# Feature hook: a feature module may rule a camp out (see
			# _feature_allows_camp()); none is on by default.
			if not brain.world.features.is_empty() and not _feature_allows_camp(ship, d as Derelict):
				continue
			# Our side's quadrants first.
			var mine := (d.global_position.x < MapLayout.CX) == (ship.team == Rules.HALCYON)
			var dist := d.global_position.distance_to(ship.global_position) + (0.0 if mine else 6000.0)
			if dist < bd:
				bd = dist
				brain.camp = d
	# Step 2: shoot the best target near us, and fly to the camp.
	brain.target = brain.targeting.pick_target(ship, PilotTargeting.engage_range(ship))
	if brain.camp != null:
		brain.goal = brain.camp.global_position + (ship.global_position - brain.camp.global_position).normalized() * 450.0
		# Close to the camp with nothing else to shoot: take the camp itself,
		# unless we just gave it up because it was hidden behind rocks.
		if brain.target == null and ship.global_position.distance_to(brain.camp.global_position) < 1200.0 \
				and not (brain.skip_id != 0 and brain.camp.get_instance_id() == brain.skip_id and brain.world.time < brain.skip_until):
			brain.target = brain.camp
	else:
		brain.state = "lane"


## Feature hook: may jungler `ship` clear camp `d`? Asks every feature in
## World.features that has allow_camp(brain, ship, d) -> bool; one "false" is
## enough to rule the camp out. (GroupLateFeature keeps junglers near the
## push lane; SalvageCoreFeature keeps a lone jungler off the Battleship.)
func _feature_allows_camp(ship: Ship, d: Derelict) -> bool:
	var brain := ai
	for f: Object in brain.world.features.values():
		if f.has_method("allow_camp") and not f.call("allow_camp", brain, ship, d):
			return false
	return true


## Retreat and home states: shoot only what is within 900 while we leave,
## and fly to a repair bay (only when retreating, and only when the bay is
## less than 60% as far as the mothership) or else to 200 past the
## mothership's bow (its front end), asking to dock once close to its hull.
func think_home(ship: Ship, ms: Mothership) -> void:
	var brain := ai
	var c := ship.controls
	# Feature hooks: Recall (channel a recall far from home, and hold still
	# while it runs) and Bay shop (shop at a forward bay) may take over.
	for f in brain.world.features.values():
		if f.has_method("ai_think_home") and f.ai_think_home(brain, ship, ms):
			return
	brain.target = brain.targeting.pick_target(ship, 900.0)
	var bay := brain.world.best_bay(ship.team, ship.global_position)
	# Big ships can't fly into the jungle: a bay anchored there is out of
	# their reach (they'd pin themselves on the rocks).
	if bay != null and not ship.is_small() and not brain.world.map.in_open_lane(bay.global_position):
		bay = null
	if brain.state == "retreat" and bay != null and bay.global_position.distance_to(ship.global_position) < ms.global_position.distance_to(ship.global_position) * 0.6:
		brain.goal = bay.global_position
	else:
		brain.goal = ms.global_position + Vector2.from_angle(ms.rotation) * (ms.half_len + 200.0)
		# Close to the hull (90% of the docking radius): ask to dock.
		if ms.hull_dist(ship.global_position) < ms.dock_radius() * 0.9:
			c.dock = true
