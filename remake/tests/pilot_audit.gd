extends Node
## WHAT THIS IS: a bug hunt for the AI pilots. It watches every computer
## pilot through an all-AI match and counts the things that look wrong:
## ships stuck far from where they want to go, ships grinding on rocks,
## shooting at targets hidden behind asteroids, big ships that can't reach
## the spot they want to hold, pilots who don't shoot back on the way home,
## missing routes, flip-flopping, and how pilots die. It also keeps
## books on the damage pilots deal and take (what a ship took and how long it
## scraped rocks are also counted per hull), on retreats (how much health
## a ship had when it turned back and how the retreat ended), on ships
## pressed against a mothership hull, and on what each big ship aims at
## during a siege.
##
## HOW IT WORKS: every tick it counts rock contacts (the ship's last move
## slid along something that isn't a unit; and, apart, a mothership hull).
## Every 0.5 game seconds it looks
## at each flying AI pilot (its brain: state, goal, target, path) and adds
## to the counters below; every 2 s it remembers each ship's position, so a
## ship that moved less than 150 in 8 s while far from its goal counts as
## stuck. Deaths come from Events.unit_killed. Every 60 s it prints one
## "AUDIT" line; at the end one "AUDIT_JSON {...}" line with every counter
## and the first examples of each problem, plus the lists of every pilot
## death ("deaths") and every stuck episode ("stucks").
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=7 --test=pilot_audit --secs=1500
## --late starts at 25:00 fully teched (LateGame.apply) and --secs then
## counts from there.
##
## WHO USES IT: main.gd loads it for --test=pilot_audit. It only reads the
## game (it connects to Events.unit_killed and Events.damage_applied, and
## switches on Combat.emit_damage_events so that the second one is sent); it
## changes nothing in the match.

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
## Every pilot death: [time, team, hull, state, cause, source, x, y, life s,
## health 0.5 s before, retreat age s, source x, source y].
var deaths := []
## Every stuck episode (the first 600): [time, team, hull, state, x, y, goal
## x, goal y, goal distance, own mothership hull distance, rocks near, in
## open lane, seconds since launch, speed, angle to the goal (rad), route
## length, route index, forward x100, unstick timer, stuck timer, what the
## last move slid along, solid things within 450].
var stucks := []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1500.0))
	if Game.opt("late", false):
		LateGame.apply(world)
		secs += LateGame.START
		_report_t = LateGame.START + 60.0
	Events.unit_killed.connect(_on_killed)
	# Damage dealt and taken by AI pilots (measurement only: the signal
	# changes nothing in the match).
	world.combat.emit_damage_events = true
	Events.damage_applied.connect(_on_damage)


## What a unit is, as a short word (for the damage counters).
func _kind_name(u: Unit) -> String:
	if u == null:
		return "env"
	match u.kind:
		Unit.K_SHIP: return "ship"
		Unit.K_MINION: return "minion"
		Unit.K_TURRET: return "turret"
		Unit.K_MOTHERSHIP: return "ms"
		Unit.K_BAY: return "bay"
		Unit.K_MONSTER, Unit.K_SNUB: return "monster"
	return "other"


## Damage dealt by AI pilots (by target kind and by hull) and taken by them
## (by attacker kind). `amount` is before the shields, `hull_dmg` after.
func _on_damage(target: Node, info: RefCounted, amount: float, hull_dmg: float) -> void:
	var t := target as Unit
	var di := info as DamageInfo
	if t == null or di == null:
		return
	var src: Unit = di.source if (di.source != null and is_instance_valid(di.source)) else null
	if src is Ship and (src as Ship).controller is PilotAI:
		var tk := _kind_name(t)
		_add("dmg_out_" + tk, amount)
		_add("dmg_out_hull_" + tk, hull_dmg)
		_add("dmgh_%s_%s" % [(src as Ship).hull_id, tk], amount)
	if t is Ship and (t as Ship).controller is PilotAI:
		_add("dmg_in", amount)
		_add("dmg_in_hull", hull_dmg)
		_add("dmg_in_from_" + _kind_name(src), amount)
		# The same, counted per hull of the ship that was hit.
		_add("dmgin_" + (t as Ship).hull_id, amount)
		_add("dmgin_hull_" + (t as Ship).hull_id, hull_dmg)


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
		var ms_hit := false
		for i in s.get_slide_collision_count():
			var col := s.get_slide_collision(i).get_collider()
			if not (col is Unit):
				rock = true
			elif (col as Unit).kind == Unit.K_MOTHERSHIP:
				ms_hit = true
		# Ships scraping a mothership hull (their own or the enemy's).
		if ms_hit:
			_add("ms_contact_ticks")
			_add("ms_contact_ticks_" + s.hull_id)
			if s.velocity.length() < 40.0:
				_add("ms_pinned_ticks")
				_add("ms_pinned_ticks_" + s.hull_id)
		if rock:
			var b := s.controller as PilotAI
			_add("rock_contact_ticks")
			_add("rock_ticks_hull_" + s.hull_id)
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
		print("AUDIT_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "counters": c, "examples": ex, "deaths": deaths, "stucks": stucks}))
		get_tree().quit()


## The 0.5 s checks for every flying AI pilot.
func _sample() -> void:
	var seen := {}
	for p: PilotProfile in world.profiles:
		_add("prof_" + p.state)
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var b := s.controller as PilotAI
		var key := b.profile.callsign
		var h: Dictionary = _hist.get(key, {"pos": [], "state": "", "target": 0, "stuck": false})
		_hist[key] = h
		seen[key] = true
		_add("samples")
		_add("state_" + b.state)
		_add("samples_" + s.hull_id)
		# State flips and target switches.
		if h["state"] != "" and h["state"] != b.state:
			_add("state_flips")
			_add("flip_%s_to_%s" % [h["state"], b.state])
		# Retreat episodes: how much health we had when we turned back, and
		# how each one ended (back to the lane, docked, or dead: _on_killed).
		var tf := s.total_frac()
		if b.state == "retreat" and h["state"] != "retreat":
			h["ret_t"] = world.time
			_add("ret_entries")
			_add("ret_entries_" + _size_name(s))
			_add("ret_total_frac_sum", tf)
			_add("ret_hull_frac_sum", s.hull_frac())
			_add("ret_shield_frac_sum", s.shield_total() / maxf(1.0, s.shields.max_total) if s.shields != null else 0.0)
			if s.hull_frac() >= 0.35:
				_add("ret_entries_nonhull")
		elif b.state != "retreat" and h.get("ret_t", 0.0) > 0.0:
			_add("ret_back_to_lane")
			_add("ret_back_age_sum", world.time - float(h["ret_t"]))
			h["ret_t"] = 0.0
		h["hull"] = s.hull_frac()
		h["total"] = tf
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
		# 7. The siege (big ships and bombers join it): what each hull aims at.
		var ts: TeamState = world.teams[s.team]
		if ts.siege_lane != "" and (not s.is_small() or s.hull_id == "bomber"):
			var ph: String = ts.siege_phase
			_add("sg_%s_%s" % [ph, s.hull_id])
			if ph == "assault":
				var tk := _kind_name(b.target) if has_t else "none"
				_add("sga_tgt_%s_%s" % [s.hull_id, tk])
				if has_t and s.controls.fire:
					_add("sga_fire_%s_%s" % [s.hull_id, tk])
				if b.state == "retreat" or b.state == "home":
					_add("sga_away_" + s.hull_id)
				# How close to the enemy mothership's hull, in units of our
				# main reach (<0.8 = inside the standoff point).
				var ems := world.mothership(1 - s.team)
				if ems != null and ems.alive:
					var rr := ems.hull_dist(s.global_position) / PilotTargeting.main_reach(s)
					var bk := "lt08" if rr < 0.8 else ("lt105" if rr < 1.05 else ("lt15" if rr < 1.5 else ("lt3" if rr < 3.0 else "ge3")))
					_add("sga_d_%s_%s" % [s.hull_id, bk])
					if has_t and b.target is Mothership:
						_add("sga_dt_%s_%s" % [s.hull_id, bk])
						if s.controls.fire:
							_add("sga_dtf_%s_%s" % [s.hull_id, bk])
	# Pilots that were retreating and are gone from the sky docked (a death is
	# counted in _on_killed, which clears the timer).
	for k in _hist.keys():
		var hh: Dictionary = _hist[k]
		if not seen.has(k) and float(hh.get("ret_t", 0.0)) > 0.0:
			_add("ret_docked")
			_add("ret_docked_age_sum", world.time - float(hh["ret_t"]))
			hh["ret_t"] = 0.0


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
			if stucks.size() < 600:
				var oms := world.mothership(s.team)
				stucks.append([roundi(world.time), s.team, s.hull_id, b.state, roundi(s.global_position.x), roundi(s.global_position.y),
					roundi(b.goal.x), roundi(b.goal.y), roundi(s.global_position.distance_to(b.goal)),
					roundi(oms.hull_dist(s.global_position)) if oms != null else -1,
					not world.asteroids.clear_at(s.global_position, s.radius + 60.0), world.map.in_open_lane(s.global_position),
					roundi(world.time - b.launched_at), roundi(s.velocity.length()), snappedf(absf(Util.ang_diff(s.rotation, (b.goal - s.global_position).angle())), 0.01),
					b.path.size(), b.path_i, roundi(s.controls.forward * 100.0), snappedf(b.flight._unstick_t, 0.1), snappedf(b.flight._stuck_t, 0.1), _colliders(s), _near(s)])
		if stuck:
			_add("stuck_seconds", 2.0)
			_add("stuck_seconds_" + s.hull_id, 2.0)
		h["stuck"] = stuck


## How a pilot died (Events.unit_killed): crash, turret, minion, pilot,
## monster or mothership; and what its brain was doing.
func _on_killed(u: Node, info: RefCounted) -> void:
	var di := info as DamageInfo
	# Kills by AI pilots (any victim).
	if di != null and di.source != null and is_instance_valid(di.source) and di.source is Ship and (di.source as Ship).controller is PilotAI:
		_add("kills_by_pilots_" + _kind_name(u as Unit))
		_add("kills_by_hull_%s_%s" % [(di.source as Ship).hull_id, _kind_name(u as Unit)])
	if not (u is Ship) or not ((u as Ship).controller is PilotAI):
		return
	var s := u as Ship
	var b := s.controller as PilotAI
	_add("pilot_deaths")
	_add("death_state_" + b.state)
	_add("death_hull_" + s.hull_id)
	_add("death_size_" + _size_name(s))
	var cause := "other"
	var src_id := ""
	var src_pos := Vector2.ZERO
	if di.kind == Rules.W_COLLISION:
		cause = "crash"
		_example("crash_death", {"who": b.profile.callsign, "hull": s.hull_id, "state": b.state, "pos": _v(s.global_position), "speed": roundi(s.velocity.length())})
	elif di.source != null and is_instance_valid(di.source):
		var us := di.source as Unit
		src_pos = us.global_position
		match us.kind:
			Unit.K_TURRET:
				cause = "turret"
				src_id = (us as Turret).ttype
			Unit.K_MINION:
				cause = "minion"
				src_id = (us as Minion).mtype
			Unit.K_SHIP:
				cause = "pilot"
				src_id = (us as Ship).hull_id
			Unit.K_MONSTER, Unit.K_SNUB: cause = "monster"
			Unit.K_MOTHERSHIP: cause = "mothership"
	_add("death_" + cause)
	if src_id != "":
		_add("death_src_%s_%s" % [cause, src_id])
	# How it ended: in retreat (after how long), or never retreated; and what
	# health it had half a second earlier (a burst kill from a healthy ship).
	var h: Dictionary = _hist.get(b.profile.callsign, {})
	var ret_age := -1.0
	if float(h.get("ret_t", 0.0)) > 0.0:
		ret_age = world.time - float(h["ret_t"])
		_add("ret_deaths")
		_add("ret_death_age_sum", ret_age)
		_add("ret_death_age_" + ("lt4" if ret_age < 4.0 else ("lt10" if ret_age < 10.0 else ("lt20" if ret_age < 20.0 else "ge20"))))
		_add("ret_death_" + cause)
		h["ret_t"] = 0.0
	var pre := float(h.get("total", 1.0))
	_add("death_prehealth_" + ("gt60" if pre > 0.6 else ("gt30" if pre > 0.3 else "le30")))
	var life := world.time - b.launched_at
	_add("death_life_sum", life)
	if life < 60.0:
		_add("death_life_lt60")
	if deaths.size() < 1500:
		deaths.append([roundi(world.time), s.team, s.hull_id, b.state, cause, src_id, roundi(s.global_position.x), roundi(s.global_position.y),
			roundi(life), snappedf(pre, 0.01), snappedf(ret_age, 0.1), roundi(src_pos.x), roundi(src_pos.y)])


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


## Solid things around a ship (everything but minions and ships within 450):
## kind, team, distance, radius.
func _near(s: Ship) -> String:
	var out := []
	var tmp: Array = []
	for u: Unit in world.unit_hash.query(s.global_position, 450.0, tmp):
		if u == s or u.kind == Unit.K_MINION or u.kind == Unit.K_SHIP:
			continue
		out.append("k%d t%d d%d r%d" % [u.kind, u.team, roundi(u.global_position.distance_to(s.global_position)), roundi(u.radius)])
	if world.mothership(s.team) != null:
		var ms := world.mothership(s.team)
		out.append("ms%d hd%d rot%.2f at %d,%d" % [s.team, roundi(ms.hull_dist(s.global_position)), ms.rotation, roundi(ms.global_position.x), roundi(ms.global_position.y)])
	return "; ".join(out)


## What the ship's last move slid along: unit kinds and rock, as text.
func _colliders(s: Ship) -> String:
	var out := []
	for i in s.get_slide_collision_count():
		var col := s.get_slide_collision(i).get_collider()
		if col is Unit:
			out.append("u%d@%d,%d" % [(col as Unit).kind, roundi((col as Node2D).global_position.x), roundi((col as Node2D).global_position.y)])
		else:
			out.append("rock")
	return ";".join(out)


## A position as a short [x, y] list of whole numbers.
func _v(p: Vector2) -> Array:
	return [roundi(p.x), roundi(p.y)]
