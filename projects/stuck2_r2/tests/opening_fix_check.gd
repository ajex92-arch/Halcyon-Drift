extends Node
## WHAT THIS IS: a check of the third-round rules of the AI opening
## (DESIGN.md A14 and C25), in an all-AI match:
##   1. The AI admiral's own waypoint (it goes up at 60 s) does not pull the
##      rally seats (4, 5, 6 and the flex pilot) off their Crossings in the
##      opening: their goal stays the opening spot.
##   2. A waypoint a human admiral places (AdmiralCommand.set_waypoint with
##      by_human) does: the rally seats of that team leave for it, and the
##      other team's seats stay put.
##   3. The opening cannot start a second time: once our first wave has
##      reached a lane's Crossing, a pilot that was away (its opening_done is
##      put back to false by hand) and finds the wave dead is done at once.
##   4. The admiral's first Crossing turret: while a team holds no Crossing,
##      the order AdmiralBuilder tries them in starts with the allowed one
##      that has the most of the team's own pilots and minions within 1,500
##      (counted here by looking at every ship and minion, not through the
##      spatial hash), the earlier node on a tie, and the map order when none
##      is near; once the team holds a Crossing, it is the map order.
## Prints PASS / FAIL lines.
##
## HOW IT WORKS: _physics_process() runs numbered steps (`step`) by the match
## clock. Every 0.25 s the rally seats are sampled (_sample_rally()): a seat
## counts only when it has been doing the plain opening job (flying, lane
## state, opening on, no fall-back, no turret evasion, no hold point) for the
## last CLEAN_FOR seconds, so a goal that is a moment old does not count.
## Step 0 runs until 70 s with only the AI admirals' waypoints up (check 1's
## samples), puts a human waypoint up for Aurelian, and step 1 samples from
## 72.5 s to 88 s (check 2's samples; the earliest first wave reaches a
## Crossing at about 91 s) and then judges checks 1 and 2. Step 2 does check 3
## at 135 s (it removes the middle-lane minions of both teams once). Step 3
## runs until 520 s and prints the total. Check 4 runs every 5 s from 20 s on,
## beside the steps. The match goes on as it is while the checks run.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --test=opening_fix_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or
## "FAIL <what> <detail>". The last line is "opening_fix_check: N failures"; 0
## means all four rules hold.
##
## WHO USES IT: main.gd loads it for --test=opening_fix_check. It reads the
## AI pilots' brains (PilotAI), the teams (TeamState) and the admiral's
## builder; it changes the match only in the two ways above.

## Seconds of match time from which check 1 samples the rally seats (the AI
## admirals place their first waypoints at 60.5 to 61.5 s).
const T_AI_FROM := 63.0
## Seconds at which a human waypoint goes up for Aurelian.
const T_HUMAN_AT := 70.0
## Seconds from which check 2 samples (the pilots have had time to react).
const T_HUMAN_FROM := 72.5
## Seconds at which the rally samples end and checks 1 and 2 are judged.
const T_RALLY_TO := 88.0
## Seconds at which check 3 runs.
const T_SECOND_OPENING := 135.0
## Seconds at which the test ends.
const T_END := 520.0
## How long (seconds) a rally seat must have been doing the plain opening job
## to count in a sample.
const CLEAN_FOR := 0.6
## How many samples a rally check needs at least.
const MIN_SAMPLES := 8
## The share of a rally check's samples that must be right.
const SHARE := 0.9
## How far (world units) a pilot's goal may be from its opening spot and still
## count as "at the opening spot".
const SAME_SPOT := 1.0
## How far (world units) away from the opening spot a rally goal has to be to
## count as "pulled away".
const PULLED_AWAY := 300.0
## The disc (world units) around a Crossing in which own ships count for the
## admiral's first Crossing turret (AdmiralBuilder.CROSSING_PRESENCE_R).
const CROSSING_R := 1500.0
## A unit this close (world units) to the edge of that disc is "on the edge":
## the spatial hash can be a few units behind, so such a sample is skipped.
const EDGE_BAND := 60.0

## The running match (set by setup()).
var world: World
## Which step of the test we are on (0-3, then 4 = done).
var step := 0
## How many checks failed so far.
var fails := 0
## The match time of the next rally sample.
var _next_rally := 0.0
## The match time of the next check-4 sample.
var _next_sample := 20.0
## Per brain (key: its instance id): the match time at which it was last NOT
## plainly doing the opening job.
var _unclean := {}
## Rally samples, key "a0", "a1" (AI waypoint only, team 0 / 1) and "h0", "h1"
## (after the human waypoint): [seat samples, samples that were right]. Right
## means "goal on the opening spot", except for "h0": "goal pulled away".
var _rally := {"a0": [0, 0], "a1": [0, 0], "h0": [0, 0], "h1": [0, 0]}
## Per team: was the AI admiral's waypoint up (and not a human's) when the
## human waypoint was placed?
var _ai_waypoint_up := [false, false]
## How many check-4 samples compared the builder's order with the count.
var _compared := 0
## How many of those had a team with no Crossing yet and an allowed Crossing
## with some of its ships near.
var _active := 0
## How many of those put a Crossing other than the first in map order first.
var _moved := 0
## How many check-4 samples were skipped (a unit on the edge of a disc).
var _skipped := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w


## Every tick: the rally sample and the check-4 sample when due, then the step
## whose time has come.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time >= _next_rally and world.time < T_RALLY_TO:
		_next_rally = world.time + 0.25
		_sample_rally()
	if world.time >= _next_sample and step < 4:
		_next_sample += 5.0
		_sample_crossings()
	match step:
		0:
			if world.time >= T_HUMAN_AT:
				# Both AI waypoints should be up by now. A human admiral for
				# Aurelian then places a waypoint on the middle lane (the spot
				# the AI picks), the way the command overlay does.
				for t in 2:
					_ai_waypoint_up[t] = world.teams[t].has_waypoint() and not world.teams[t].waypoint_by_human
				var ai: AdmiralAI = world.admiral_ai[0]
				world.command.set_waypoint(0, ai.lanes.lane_point("mid", 0.55), true, true)
				step = 1
		1:
			if world.time >= T_RALLY_TO:
				_judge_rally()
				step = 2
		2:
			if world.time >= T_SECOND_OPENING:
				_check_second_opening_blocked()
				step = 3
		3:
			if world.time >= T_END:
				_check("first Crossing turret: rule compared with the count", _compared >= 20 and _active >= 1, "%d compared, %d with a team still without a Crossing and ships near (%d put a later node first), %d skipped" % [_compared, _active, _moved, _skipped])
				print("opening_fix_check: %d failures" % fails)
				step = 4
				get_tree().quit()


## Record one check.
func _check(what: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])


## One rally sample: note which rally seats are not plainly doing the opening
## job, and, for the ones that are (for CLEAN_FOR seconds), count whether their
## goal is on their opening spot (before the human waypoint and for Vhorr) or
## pulled away from it (Aurelian, after the human waypoint).
func _sample_rally() -> void:
	for p: PilotProfile in world.profiles:
		var brain: PilotAI = world.pilot_ai.get(p)
		if p.is_human or brain == null or not (p.slot in [4, 5, 6] or p.role == "flex"):
			continue
		var ship := p.ship
		var id := brain.get_instance_id()
		var flying := ship != null and is_instance_valid(ship) and ship.alive
		if not flying or brain.state != "lane" or brain.opening_done or brain.fallback_t > 0.0 or brain.evade_t > 0.0 or brain.hold_point != Vector2.INF:
			_unclean[id] = world.time
			continue
		if world.time - float(_unclean.get(id, -99.0)) < CLEAN_FOR:
			continue
		var gap := brain.goal.distance_to(brain.goals.opening_goal(ship))
		var key := ""
		var right := gap <= SAME_SPOT
		if world.time >= T_HUMAN_FROM:
			key = "h%d" % p.team
			right = gap > PULLED_AWAY if p.team == 0 else gap <= SAME_SPOT
		elif world.time >= T_AI_FROM and world.time < T_HUMAN_AT:
			key = "a%d" % p.team
		if key != "":
			var r: Array = _rally[key]
			r[0] = int(r[0]) + 1
			if right:
				r[1] = int(r[1]) + 1


## Checks 1 and 2, from the rally samples (check 1 over both teams together).
func _judge_rally() -> void:
	# Check 1 counts both teams together (a team whose rally seats were all
	# away or fighting in the window has too few clean samples on its own).
	var a0: Array = _rally["a0"]
	var a1: Array = _rally["a1"]
	var a_all := int(a0[0]) + int(a1[0])
	var a_right := int(a0[1]) + int(a1[1])
	_check("AI waypoints ignored in the opening", _ai_waypoint_up[0] and _ai_waypoint_up[1] and a_all >= MIN_SAMPLES and float(a_right) >= SHARE * float(a_all),
			"AI waypoints up: %s and %s, %d of %d rally-seat samples on the opening spot (Aurelian %d of %d, Vhorr %d of %d)" % [_ai_waypoint_up[0], _ai_waypoint_up[1], a_right, a_all, int(a0[1]), int(a0[0]), int(a1[1]), int(a1[0])])
	var h0: Array = _rally["h0"]
	_check("human waypoint obeyed in the opening (Aurelian)", world.teams[0].has_waypoint() and world.teams[0].waypoint_by_human and int(h0[0]) >= MIN_SAMPLES and float(h0[1]) >= SHARE * float(h0[0]),
			"by a human: %s, %d of %d rally-seat samples more than %d from the opening spot" % [world.teams[0].waypoint_by_human, int(h0[1]), int(h0[0]), int(PULLED_AWAY)])
	var h1: Array = _rally["h1"]
	_check("AI waypoint still ignored (Vhorr)", world.teams[1].has_waypoint() and not world.teams[1].waypoint_by_human and int(h1[0]) >= MIN_SAMPLES and float(h1[1]) >= SHARE * float(h1[0]),
			"%d of %d rally-seat samples on the opening spot" % [int(h1[1]), int(h1[0])])


## Check 3: the first wave has reached the middle Crossing (noted in
## TeamState.first_wave_at); a pilot of the middle lane whose opening_done is
## put back to false, with the middle-lane wave dead, is done at once.
func _check_second_opening_blocked() -> void:
	for team in 2:
		var ts := world.teams[team]
		var noted := ts.first_wave_at.has("mid")
		var victim: PilotAI = null
		for p: PilotProfile in world.profiles:
			var brain: PilotAI = world.pilot_ai.get(p)
			if not p.is_human and brain != null and p.team == team and brain.goals.opening_lane() == "mid":
				victim = brain
				break
		if victim == null:
			_check("no second opening (team %d)" % team, false, "no pilot with the middle lane")
			continue
		# The pilot was away when the wave arrived; the wave has died since.
		victim.opening_done = false
		var dead := []
		for m in world.minions:
			if m.team == team and m.alive and m.lane == "mid":
				dead.append(m)
		for m in dead:
			world.combat.kill_silently(m)
		var front := victim.goals.wave_front_s("mid", team)
		var active := victim.goals.opening_active()
		_check("no second opening (team %d)" % team, noted and front < 0.0 and not active and victim.opening_done,
				"first mid wave noted: %s, front after the kills: %.0f, opening active again: %s" % [ts.first_wave_at.get("mid", "no"), front, active])


## Check 4: one sample (see the top of this file).
func _sample_crossings() -> void:
	for team in 2:
		var ai: AdmiralAI = world.admiral_ai[team]
		if ai == null:
			continue
		var holding := false
		for n in world.nodes:
			if n.node_kind == "middle" and n.turret_count(team) >= 1:
				holding = true
		var order: Array = ai.builder._crossings_in_order()
		# The order always holds every node once.
		if order.size() != world.nodes.size():
			_check("first Crossing turret: order complete (team %d)" % team, false, "%d nodes in the order, %d on the map" % [order.size(), world.nodes.size()])
			continue
		# What the order should start with.
		var expect: ResourceNode = world.nodes[0]
		var best := 0
		var edge := false
		if not holding:
			for n in world.nodes:
				if n.node_kind != "middle" or world.command.turret_blocker(team, n.node_id, "pd") != "":
					continue
				var inside := _count_near(team, n.global_position, CROSSING_R)
				if inside != _count_near(team, n.global_position, CROSSING_R + EDGE_BAND) or inside != _count_near(team, n.global_position, CROSSING_R - EDGE_BAND):
					edge = true
				if inside > best:
					best = inside
					expect = n
		if edge:
			_skipped += 1
			continue
		_compared += 1
		if not holding and best > 0:
			_active += 1
			if expect != world.nodes[0]:
				_moved += 1
		if order[0] != expect:
			_check("first Crossing turret: order (team %d, t=%.0f)" % [team, world.time], false, "starts with %s, the count says %s (%d ships near), holding a Crossing: %s" % [order[0].node_id, expect.node_id, best, holding])


## How many live ships and minions of `team` are within `r` of point `p`,
## counted by looking at every one of them.
func _count_near(team: int, p: Vector2, r: float) -> int:
	var count := 0
	for s in world.ships:
		if s.team == team and s.alive and s.global_position.distance_to(p) < r:
			count += 1
	for m in world.minions:
		if m.team == team and m.alive and m.global_position.distance_to(p) < r:
			count += 1
	return count
