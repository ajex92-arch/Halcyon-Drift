extends Node
## WHAT THIS IS: a measuring tool for the first minutes of a match. It
## answers one question about the computer pilots of BOTH teams: do they go
## out to contest the three Crossing nodes (the ore nodes on the centre
## line, x = 20000) early, stay there until their first wave comes, and
## leave the opening for good when it does, or do they hang about near their
## own base and fly home to shop first?
##
## HOW IT WORKS: every 0.25 game seconds it looks at every AI pilot and
## notes, per pilot: the distance to its own mothership at 10 s, the first
## time it came within NEAR_R of its lane's Crossing node, when it first
## launched, when it first chose a jungle camp (t_camp, junglers), every
## trip home to SHOP (a trip home because of a retreat does not count), when
## its opening ended (t_done: the first sample with PilotAI.opening_done
## true), how many seconds it flew in the lane or jungle state with its
## opening NOT done more than REOPEN_GRACE seconds after its lane's first
## wave reached the Crossing (reopen_s: a pilot that is dead, docked,
## retreating or flying home when the wave arrives must not start a second
## opening later), how many times it fell back from a fight (fb_total, and
## fb_open of those while its opening was still on), how many seconds it held
## its Crossing in the "held" window (held_s, see below) and how many seconds
## in the opening its goal was somewhere other than its opening spot (goal_off_s:
## a waypoint rally, a turret to defend, a siege, a defend call; not counted
## while it falls back, evades a turret or has a hold point). It also notes, per
## team and lane, when the first minion wave launched and when that wave
## first reached the Crossing (its front minion level with the node, or
## within ARRIVE_SHORT short of it), and how many AI pilots of that lane held
## the Crossing (were within NEAR_R of it) on average between HELD_FROM
## seconds and that arrival ("held"). A few times in the opening it takes a
## snapshot: for each team, how many pilots are flying, how far they are on
## average from their own mothership and from their Crossing, how many are
## within NEAR_R of it, and the same count for each lane ("by_lane": near,
## flying). At the end it prints one "OPENING_JSON {...}" line, one
## "OPENING_FLAG ..." line for every pilot with reopen_s above REOPEN_MIN
## (the JSON holds the same list as "flags"), and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --test=opening_probe --secs=300 --skill-jitter
##
## WHO USES IT: main.gd loads it for --test=opening_probe. It only reads the
## game; it changes nothing in the match (it never calls
## PilotGoals.opening_active(), which records things). The pilot's lane is
## the lane whose Crossing it is sent to in the opening (_lane_of(): the
## brain's opening_lane() when the build has it, else lane_id(); junglers
## count as "mid", and in builds with the flex shift the flex pilot has its
## own lane).

## A pilot counts as "at the Crossing" when it is within this many world
## units of the node's centre.
const NEAR_R := 1500.0
## A wave counts as having reached the Crossing when its front minion is
## within this many world units short of the point on the lane level with
## the node (or past it). Same number as PilotGoals.OPENING_ARRIVE.
const ARRIVE_SHORT := 300.0
## The game times (seconds) at which a snapshot is taken.
const SNAP_TIMES := [10.0, 20.0, 30.0, 44.0, 60.0, 70.0, 80.0, 90.0, 100.0, 110.0, 120.0, 150.0, 200.0, 250.0]
## "Held" is counted from this game time (seconds) on: the AI admiral places
## its first waypoint at 60 s, and the question is whether the pilots stay at
## their Crossings after it.
const HELD_FROM := 60.0
## A pilot's opening should be over this many seconds after its lane's first
## wave reached the Crossing (a pilot that was flying and thinking sees the
## wave within a fraction of a second).
const REOPEN_GRACE := 5.0
## A pilot is flagged when it spent more than this many seconds flying in the
## lane or jungle state with its opening not done after the grace time (a
## pilot that was away and has just launched needs one think, about 0.3 s, to
## see that the opening is over).
const REOPEN_MIN := 1.0

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 300.0
## Seconds until the next 0.25 s sample.
var _sample_t := 0.0
## Game time of the previous sample (to add up real time between samples).
var _last_t := 0.0
## Per pilot record, key "team:slot": role, lane, d10, t_near, t_near_any,
## t_launch, t_camp, t_done, reopen_s, fb_total, fb_open, shop trip times,
## retreat entry times, deaths and kills so far.
var _rec := {}
## Per team and lane, key "team:lane": "spawn" (game time of the first wave
## minion launched, -1 = none yet) and "reach" (game time the wave first
## reached the Crossing, -1 = not yet).
var _wave := {}
## Per team and lane, key "team:lane": "s" (pilot-seconds spent within NEAR_R
## of the lane's Crossing by that lane's AI pilots) and "w" (the seconds of
## the window, from HELD_FROM to the first wave's arrival or Rules.AI_OPENING_MAX,
## whichever comes first, that have been counted). "s" / "w" is the mean number
## of pilots holding the Crossing.
var _held := {}
## The snapshots taken so far (a list of Dictionaries).
var _snaps := []
## Which of SNAP_TIMES comes next.
var _next_snap := 0


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 300.0))
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			_wave["%d:%s" % [team, lane]] = {"spawn": -1.0, "reach": -1.0}
			_held["%d:%s" % [team, lane]] = {"s": 0.0, "w": 0.0}
	Events.minion_launched.connect(_on_minion)


## A free-wave minion launched: remember the first launch time per team and
## lane.
func _on_minion(m: Minion, _next: float) -> void:
	var w: Dictionary = _wave["%d:%s" % [m.team, m.lane]]
	if float(w["spawn"]) < 0.0:
		w["spawn"] = snappedf(world.time, 0.01)


## The Crossing node on `lane` (the middle node of that lane), or null.
func _crossing(lane: String) -> ResourceNode:
	for n in world.nodes:
		if n.node_kind == "middle" and n.lane == lane:
			return n
	return null


## How far along `lane` (from `team`'s end) the front minion of that team
## is, or -1 with none out (only minions within 2,500 of the lane line).
func _wave_s(lane: String, team: int) -> float:
	var pts := MapLayout.lane_points(lane, team)
	var best := -1.0
	for m in world.minions:
		if m.team != team or not m.alive or m.lane != lane:
			continue
		var pr := Util.project_on_polyline(m.global_position, pts)
		if float(pr["dist"]) < 2500.0 and float(pr["s"]) > best:
			best = pr["s"]
	return best


## The lane whose Crossing pilot rain is sent to: PilotGoals.opening_lane()
## when this build has it (the flex pilot has its own lane), else lane_id().
func _lane_of(brain: PilotAI) -> String:
	if brain.goals.has_method("opening_lane"):
		return brain.goals.call("opening_lane")
	return brain.goals.lane_id()


## Every tick: sample every 0.25 s, snapshot at the listed times, and at the
## end print the JSON line (and a line per flagged pilot) and quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	_sample_t -= dt
	if _sample_t <= 0.0:
		_sample_t = 0.25
		_sample()
	if _next_snap < SNAP_TIMES.size() and world.time >= float(SNAP_TIMES[_next_snap]):
		_snapshot(float(SNAP_TIMES[_next_snap]))
		_next_snap += 1
	if world.time >= secs or world.phase != "play":
		var flags := _flags()
		for f: Dictionary in flags:
			print("OPENING_FLAG team=%d slot=%d role=%s lane=%s reach=%.1f t_done=%.1f reopen_s=%.1f" % [f["team"], f["slot"], f["role"], f["lane"], f["reach"], f["t_done"], f["reopen_s"]])
		print("OPENING_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "pilots": _rec.values(), "waves": _wave, "held": _held, "flags": flags, "snaps": _snaps}))
		get_tree().quit()


## The pilots whose opening started again after their lane's first wave had
## reached the Crossing (reopen_s above REOPEN_MIN), with their lane's arrival
## time, the time their opening ended (-1 = never seen) and the seconds.
func _flags() -> Array:
	var out := []
	for r: Dictionary in _rec.values():
		var w: Dictionary = _wave["%d:%s" % [r["team"], r["lane"]]]
		if float(r["reopen_s"]) > REOPEN_MIN:
			out.append({"team": r["team"], "slot": r["slot"], "role": r["role"], "lane": r["lane"], "reach": float(w["reach"]), "t_done": float(r["t_done"]), "reopen_s": snappedf(float(r["reopen_s"]), 0.1)})
	return out


## The 0.25 s checks: wave arrivals, then every AI pilot.
func _sample() -> void:
	var step := world.time - _last_t
	_last_t = world.time
	# Step 1: has a team's wave reached its Crossing yet? And is the "held"
	# window (from HELD_FROM until that arrival) open for the lane?
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			var w: Dictionary = _wave["%d:%s" % [team, lane]]
			if float(w["reach"]) < 0.0 and world.time >= HELD_FROM and world.time < Rules.AI_OPENING_MAX:
				var hw: Dictionary = _held["%d:%s" % [team, lane]]
				hw["w"] = float(hw["w"]) + step
			if float(w["reach"]) >= 0.0 or float(w["spawn"]) < 0.0:
				continue
			var node := _crossing(lane)
			if node == null:
				continue
			var s_node: float = Util.project_on_polyline(node.global_position, MapLayout.lane_points(lane, team))["s"]
			if _wave_s(lane, team) >= s_node - ARRIVE_SHORT:
				w["reach"] = snappedf(world.time, 0.01)
	# Step 2: every AI pilot with a live ship.
	for p: PilotProfile in world.profiles:
		var brain: PilotAI = world.pilot_ai.get(p)
		if p.is_human or brain == null:
			continue
		var key := "%d:%d" % [p.team, p.slot]
		if not _rec.has(key):
			_rec[key] = {"team": p.team, "slot": p.slot, "role": p.role, "lane": _lane_of(brain), "callsign": p.callsign,
					"d10": -1.0, "d10_state": "", "t_near": -1.0, "t_near_any": -1.0, "t_camp": -1.0, "t_launch": -1.0, "t_done": -1.0,
					"reopen_s": 0.0, "held_s": 0.0, "goal_off_s": 0.0, "fb_total": 0, "fb_open": 0, "fb_last": 0.0, "shop": [], "retreat": [], "last_state": "", "deaths": 0, "kills": 0}
		var r: Dictionary = _rec[key]
		r["deaths"] = p.deaths
		r["kills"] = p.kills
		var ship := p.ship
		var flying := ship != null and is_instance_valid(ship) and ship.alive
		var ms := world.mothership(p.team)
		# The distance at 10 s: a docked pilot counts as at the mothership
		# (0); a dead one is noted as such.
		if float(r["d10"]) < 0.0 and world.time >= 10.0:
			r["d10_state"] = "flying" if flying else p.state
			r["d10"] = snappedf(ms.hull_dist(ship.global_position), 1.0) if flying and ms != null else 0.0
		if not flying:
			r["fb_last"] = 0.0
			continue
		# First time in space, and the first time a camp is chosen (junglers).
		if float(r["t_launch"]) < 0.0:
			r["t_launch"] = snappedf(world.time, 0.1)
		if float(r["t_camp"]) < 0.0 and brain.camp != null and is_instance_valid(brain.camp):
			r["t_camp"] = snappedf(world.time, 0.1)
		# Trips home: shopping ones and retreats are counted apart.
		if brain.state != r["last_state"]:
			if brain.state == "home" and brain.home_reason != "":
				(r["shop"] as Array).append(snappedf(world.time, 0.1))
			elif brain.state == "retreat":
				(r["retreat"] as Array).append(snappedf(world.time, 0.1))
			r["last_state"] = brain.state
		# Falling back from a fight (a jump of the fall-back timer), and
		# whether the pilot's opening was still on then.
		var fb := brain.fallback_t
		if fb > float(r["fb_last"]) + 0.5:
			r["fb_total"] = int(r["fb_total"]) + 1
			if not brain.opening_done and world.time >= Rules.AI_OPENING_HOLD:
				r["fb_open"] = int(r["fb_open"]) + 1
		r["fb_last"] = fb
		# The opening's end, and a second opening: flying in the lane or
		# jungle state with the opening not done, REOPEN_GRACE after the wave
		# of the pilot's lane reached the Crossing.
		if float(r["t_done"]) < 0.0 and brain.opening_done:
			r["t_done"] = snappedf(world.time, 0.1)
		var reach := float((_wave["%d:%s" % [p.team, r["lane"]]] as Dictionary)["reach"])
		if reach >= 0.0 and world.time >= reach + REOPEN_GRACE and not brain.opening_done and (brain.state == "lane" or brain.state == "jungle"):
			r["reopen_s"] = float(r["reopen_s"]) + step
		# In the opening, a goal that is not the opening spot (read-only: the
		# call below changes nothing).
		if not brain.opening_done and world.time >= Rules.AI_OPENING_HOLD and (brain.state == "lane" or brain.state == "jungle") and brain.fallback_t <= 0.0 and brain.evade_t <= 0.0 and brain.hold_point == Vector2.INF:
			if brain.goal.distance_to(brain.goals.opening_goal(ship)) > 50.0:
				r["goal_off_s"] = float(r["goal_off_s"]) + step
		# First arrival at the pilot's own lane's Crossing, and at any; and
		# the time spent holding the own Crossing in the "held" window.
		var node := _crossing(str(r["lane"]))
		if float(r["t_near"]) < 0.0 and node != null and ship.global_position.distance_to(node.global_position) <= NEAR_R:
			r["t_near"] = snappedf(world.time, 0.1)
		if node != null and world.time >= HELD_FROM and world.time < Rules.AI_OPENING_MAX and reach < 0.0 and ship.global_position.distance_to(node.global_position) <= NEAR_R:
			var hs: Dictionary = _held["%d:%s" % [p.team, r["lane"]]]
			hs["s"] = float(hs["s"]) + step
			r["held_s"] = float(r["held_s"]) + step
		if float(r["t_near_any"]) < 0.0:
			for lane: String in MapLayout.LANE_ORDER:
				var cn := _crossing(lane)
				if cn != null and ship.global_position.distance_to(cn.global_position) <= NEAR_R:
					r["t_near_any"] = snappedf(world.time, 0.1)
					break


## A snapshot at game time `t`: per team, how many AI pilots fly, their mean
## distance to their own mothership hull and to their lane's Crossing node,
## and how many are within NEAR_R of it; "by_lane" gives, for each lane, the
## pilots of that lane that are within NEAR_R of its Crossing and those that
## fly.
func _snapshot(t: float) -> void:
	var out := {"t": t}
	for team in 2:
		var n := 0
		var dms := 0.0
		var dcr := 0.0
		var near := 0
		var by_lane := {}
		for lane: String in MapLayout.LANE_ORDER:
			by_lane[lane] = [0, 0]
		var ms := world.mothership(team)
		for p: PilotProfile in world.profiles:
			var brain: PilotAI = world.pilot_ai.get(p)
			if p.is_human or brain == null or p.team != team:
				continue
			var ship := p.ship
			if ship == null or not is_instance_valid(ship) or not ship.alive:
				continue
			var lane := _lane_of(brain)
			var node := _crossing(lane)
			if node == null or ms == null:
				continue
			n += 1
			dms += ms.hull_dist(ship.global_position)
			var d := ship.global_position.distance_to(node.global_position)
			dcr += d
			var bl: Array = by_lane[lane]
			bl[1] = int(bl[1]) + 1
			if d <= NEAR_R:
				near += 1
				bl[0] = int(bl[0]) + 1
		out["t%d" % team] = {"flying": n, "mean_d_ms": roundi(dms / maxf(1.0, float(n))), "mean_d_cross": roundi(dcr / maxf(1.0, float(n))), "near": near, "by_lane": by_lane}
	_snaps.append(out)
