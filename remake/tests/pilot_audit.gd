extends Node
## WHAT THIS IS: a bug hunt for the AI pilots. It watches every computer
## pilot through an all-AI match and counts the things that look wrong:
## ships stuck far from where they want to go, ships grinding on rocks,
## shooting at targets hidden behind asteroids, big ships that can't reach
## the spot they want to hold, pilots who don't shoot back on the way home,
## missing routes, flip-flopping, and how pilots die.
##
## HOW IT WORKS: every tick it counts rock contacts (the ship's last move
## slid along something that isn't a unit). Every 0.5 game seconds it looks
## at each flying AI pilot (its brain: state, goal, target, path) and adds
## to the counters below; every 2 s it remembers each ship's position, so a
## ship that moved less than 150 in 8 s while far from its goal counts as
## stuck. Deaths come from Events.unit_killed. Every 60 s it prints one
## "AUDIT" line; at the end one "AUDIT_JSON {...}" line with every counter
## and the first examples of each problem.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=7 --test=pilot_audit --secs=1500
## --late starts at 25:00 fully teched (LateGame.apply) and --secs then
## counts from there.
##
## WHO USES IT: main.gd loads it for --test=pilot_audit. It only reads the
## game (and connects to Events.unit_killed); it changes nothing.

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 1500.0
## Seconds until the next 0.5 s sample.
var _sample_t := 0.0
## Seconds until the next 2 s position sample.
var _pos_t := 0.0
## Game time of the next AUDIT line.
var _report_t := 60.0
## Counters (see _sample() and _on_killed()).
var c := {}
## Examples of each problem: name -> Array of short Dictionaries (capped).
var ex := {}
## Per pilot (key = callsign): last positions (every 2 s), last state,
## last target id, whether a stuck episode is running.
var _hist := {}


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1500.0))
	if Game.opt("late", false):
		LateGame.apply(world)
		secs += LateGame.START
		_report_t = LateGame.START + 60.0
	Events.unit_killed.connect(_on_killed)


## Add `n` to counter `key`.
func _add(key: String, n: float = 1.0) -> void:
	c[key] = float(c.get(key, 0.0)) + n


## Keep an example for problem `key` (at most 12 each).
func _example(key: String, d: Dictionary) -> void:
	if not ex.has(key):
		ex[key] = []
	if (ex[key] as Array).size() < 12:
		d["t"] = snappedf(world.time, 0.1)
		(ex[key] as Array).append(d)


## Every tick: rock contacts; every 0.5 s the pilot checks; every 60 s a
## report; at the end the JSON and quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var rock := false
		for i in s.get_slide_collision_count():
			if not (s.get_slide_collision(i).get_collider() is Unit):
				rock = true
		if rock:
			var b := s.controller as PilotAI
			_add("rock_contact_ticks")
			_add("rock_contact_ticks_" + b.state)
			if b.target != null and is_instance_valid(b.target) and b.state != "home" and not b.combat.target_far(s):
				_add("rock_contact_ticks_fighting")
	_sample_t -= dt
	if _sample_t <= 0.0:
		_sample_t = 0.5
		_sample()
	_pos_t -= dt
	if _pos_t <= 0.0:
		_pos_t = 2.0
		_positions()
	if world.time >= _report_t:
		_report_t += 60.0
		print("AUDIT t=%d stuck=%d rock_s=%.0f occl=%d/%d home_nofire=%d hold_far=%d/%d noroute=%d deaths=%d crash_deaths=%d" % [int(world.time),
			int(c.get("stuck_episodes", 0)), float(c.get("rock_contact_ticks", 0)) / 60.0, int(c.get("occluded", 0)), int(c.get("fight_samples", 0)),
			int(c.get("home_target_in_reach", 0)), int(c.get("hold_far_not_approaching", 0)), int(c.get("hold_far", 0)),
			int(c.get("no_route_far", 0)), int(c.get("pilot_deaths", 0)), int(c.get("death_crash", 0))])
	if world.time >= secs or world.phase != "play":
		print("AUDIT_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "counters": c, "examples": ex}))
		get_tree().quit()


## The 0.5 s checks for every flying AI pilot.
func _sample() -> void:
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var b := s.controller as PilotAI
		var key := b.profile.callsign
		var h: Dictionary = _hist.get(key, {"pos": [], "state": "", "target": 0, "stuck": false})
		_hist[key] = h
		_add("samples")
		_add("state_" + b.state)
		# State flips and target switches.
		if h["state"] != "" and h["state"] != b.state:
			_add("state_flips")
			_add("flip_%s_to_%s" % [h["state"], b.state])
		h["state"] = b.state
		var tid := b.target.get_instance_id() if (b.target != null and is_instance_valid(b.target)) else 0
		if tid != 0 and h["target"] != 0 and tid != h["target"]:
			_add("target_switches")
		h["target"] = tid
		var has_t := tid != 0 and b.target.alive
		var fighting := has_t and b.state != "home" and b.state != "retreat" and not b.combat.target_far(s)
		# 1. Targets behind asteroids while fighting.
		if fighting:
			_add("fight_samples")
			_add("fight_samples_" + _size_name(s))
			if world.asteroids.segment_blocked(s.global_position, b.target.global_position):
				_add("occluded")
				_add("occluded_" + _size_name(s))
				if s.controls.fire:
					_add("occluded_firing")
				_example("occluded", {"who": key, "hull": s.hull_id, "target_kind": b.target.kind, "d": roundi(s.global_position.distance_to(b.target.global_position)), "intent": b.intent, "state": b.state})
		# 2. Flying home with a target in reach: the AI never fires then.
		if b.state == "home" and has_t and s.global_position.distance_to(b.target.global_position) < PilotTargeting.main_reach(s):
			_add("home_target_in_reach")
			if s.last_damage_time > world.time - 2.0:
				_add("home_target_in_reach_while_hit")
		# 3. Big ships fighting: can they reach the spot they want to hold?
		if fighting and s.size_class >= Rules.SIZE_MEDIUM:
			var hold := _hold_point(s, b)
			var to_hold := hold - s.global_position
			if to_hold.length() > 500.0:
				_add("hold_far")
				var approach := s.velocity.dot(to_hold.normalized())
				if approach < 30.0:
					_add("hold_far_not_approaching")
					var face_err := absf(Util.ang_diff(s.rotation, to_hold.angle()))
					if face_err > 1.4:
						_add("hold_far_behind_or_side")
					_example("hold_far", {"who": key, "hull": s.hull_id, "dist": roundi(to_hold.length()), "face_err": snappedf(face_err, 0.01), "approach": roundi(approach), "intent": b.intent})
		# 4. Far from the goal with no route planned.
		var gd := s.global_position.distance_to(b.goal)
		if not fighting and gd > 2500.0 and b.path.is_empty():
			_add("no_route_far")
			_example("no_route_far", {"who": key, "hull": s.hull_id, "state": b.state, "pos": _v(s.global_position), "goal": _v(b.goal)})
		# 5. A lane station (nothing to shoot) on or next to rocks.
		if b.state == "lane" and not has_t and b.intent == "":
			_add("station_samples")
			if not world.asteroids.clear_at(b.goal, s.radius + 10.0):
				_add("station_near_rocks")
				_example("station_near_rocks", {"who": key, "hull": s.hull_id, "goal": _v(b.goal), "open": world.map.in_open_lane(b.goal)})
		# 6. Small and medium ships inside an enemy turret's range that is
		# shooting them.
		if s.size_class < Rules.SIZE_LARGE:
			for t: Turret in world.turrets:
				if t.alive and t.team != s.team and t.target == s:
					_add("turret_targeted_samples")
					_add("turret_targeted_" + b.state)
					break


## Every 2 s: remember positions; a ship that moved less than 150 over the
## last 8 s while more than 800 from its goal, and not fighting, is stuck.
func _positions() -> void:
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var b := s.controller as PilotAI
		var h: Dictionary = _hist.get(b.profile.callsign, {"pos": [], "state": "", "target": 0, "stuck": false})
		_hist[b.profile.callsign] = h
		var ps: Array = h["pos"]
		ps.append(s.global_position)
		if ps.size() > 5:
			ps.pop_front()
		if ps.size() < 5:
			continue
		var moved := 0.0
		for p: Vector2 in ps:
			moved = maxf(moved, p.distance_to(ps[0]))
		var has_t: bool = b.target != null and is_instance_valid(b.target) and b.target.alive
		var fighting: bool = has_t and b.state != "home" and b.state != "retreat" and not b.combat.target_far(s)
		var far := s.global_position.distance_to(b.goal) > 800.0
		var stuck := moved < 150.0 and far and not fighting
		if stuck and not h["stuck"]:
			_add("stuck_episodes")
			_add("stuck_" + b.state)
			_example("stuck", {"who": b.profile.callsign, "hull": s.hull_id, "state": b.state, "pos": _v(s.global_position), "goal": _v(b.goal),
				"goal_d": roundi(s.global_position.distance_to(b.goal)), "open": world.map.in_open_lane(s.global_position),
				"rocks_near": not world.asteroids.clear_at(s.global_position, s.radius + 60.0), "path": b.path.size(), "path_i": b.path_i})
		if stuck:
			_add("stuck_seconds", 2.0)
		h["stuck"] = stuck


## How a pilot died (Events.unit_killed): crash, turret, minion, pilot,
## monster or mothership; and what its brain was doing.
func _on_killed(u: Node, info: RefCounted) -> void:
	if not (u is Ship) or not ((u as Ship).controller is PilotAI):
		return
	var s := u as Ship
	var b := s.controller as PilotAI
	var di := info as DamageInfo
	_add("pilot_deaths")
	_add("death_state_" + b.state)
	var cause := "other"
	if di.kind == Rules.W_COLLISION:
		cause = "crash"
		_example("crash_death", {"who": b.profile.callsign, "hull": s.hull_id, "state": b.state, "pos": _v(s.global_position), "speed": roundi(s.velocity.length())})
	elif di.source != null and is_instance_valid(di.source):
		match (di.source as Unit).kind:
			Unit.K_TURRET: cause = "turret"
			Unit.K_MINION: cause = "minion"
			Unit.K_SHIP: cause = "pilot"
			Unit.K_MONSTER, Unit.K_SNUB: cause = "monster"
			Unit.K_MOTHERSHIP: cause = "mothership"
	_add("death_" + cause)


## The spot a medium or bigger ship wants to hold while fighting (the same
## rule as PilotCombat.fight()).
func _hold_point(s: Ship, b: PilotAI) -> Vector2:
	var t := b.target
	var tp := t.global_position
	if t is Mothership:
		var ms := t as Mothership
		tp = Util.closest_on_segment(s.global_position, ms.global_position + Vector2.from_angle(ms.rotation) * ms.half_len, ms.global_position - Vector2.from_angle(ms.rotation) * ms.half_len)
	var reach := (s.mounts[0].reach * s.range_mult) if not s.mounts.is_empty() else 700.0
	if b.intent == "push" or b.goal.distance_to(tp) > reach * 0.6:
		return b.goal
	return tp + (s.global_position - tp).normalized() * reach * 0.75


## "small", "medium", "large" or "capital".
func _size_name(s: Ship) -> String:
	return ["small", "medium", "large", "capital"][Rules.size_index(s.size_class)]


## A position as a short [x, y] list of whole numbers.
func _v(p: Vector2) -> Array:
	return [roundi(p.x), roundi(p.y)]
