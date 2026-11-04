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
## during a siege. For every stuck ship it also notes who it was, whether it
## sat on or next to a rock, and when it got free; and it finds "traps":
## ships that stay in one small area for a whole minute while they scrape a
## rock, which the 8-second stuck rule cuts into pieces or misses.
##
## HOW IT WORKS: every tick it counts rock contacts (the ship's last move
## slid along something that isn't a unit; and, apart, a mothership hull).
## Every 0.5 game seconds it looks
## at each flying AI pilot (its brain: state, goal, target, path) and adds
## to the counters below; every 2 s it remembers each ship's position, so a
## ship that moved less than 150 in 8 s while far from its goal counts as
## stuck (an "episode": it ends when the ship moves on, dies or docks). The
## same positions feed the trap rule: a ship that never goes farther than
## TRAP_RADIUS from where a 60-second window began, and scrapes a rock for at
## least 2 seconds of it, is trapped until it gets TRAP_LEAVE_MARGIN farther
## out. A path that is empty while an escape flies (PilotEscape) is counted
## apart from a path that is really missing. Deaths come from
## Events.unit_killed. Every 60 s it prints one
## "AUDIT" line; at the end one "AUDIT_JSON {...}" line with every counter
## and the first examples of each problem, plus the lists of every pilot
## death ("deaths"), every stuck episode ("stucks") and every trap ("traps").
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

## The trap rule looks at this many position samples (2 s apart, so 60 s).
const TRAP_WINDOW := 30
## A pilot is trapped when it never went farther than this (world units) from
## where the window began.
const TRAP_RADIUS := 400.0
## ...and its ship scraped a rock for at least this many ticks in the window
## (120 ticks = 2 s).
const TRAP_ROCK_TICKS := 120
## A trap ends once the ship is more than TRAP_RADIUS plus this (world units)
## from the place where the trap was found.
const TRAP_LEAVE_MARGIN := 150.0
## The most traps the "traps" list keeps.
const MAX_TRAPS := 300
## A stuck ship counts as touching a rock when the gap between the ship's
## circle and the nearest rock's solid circle is at most this (world units).
const ROCK_CONTACT_GAP := 8.0
## ...and as next to a rock when that gap is at most this (world units).
const ROCK_NEAR_GAP := 60.0
## The names of the rock classes of a stuck episode, by number (0 = in the
## open, 1 = next to a rock, 2 = touching one); they end the counter names
## "stuck_class_..." and "stuck_seconds_...".
const ROCK_CLASSES := ["open", "near", "contact"]

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
## Per pilot (key = callsign), made by _h(): last positions (every 2 s), last
## state, last target id, whether a stuck episode is running ("stuck", "row"
## = its place in `stucks`, "cls" = its rock class, "rock_ep" = ticks of rock
## contact in it), the trap window ("tpos" positions and "trock" rock ticks
## per sample, "trap" = the running trap or null), the rock ticks since the
## last position sample ("rock_cur") and when the pilot's ship last died
## ("dead_t").
var _hist := {}
## Every pilot death: [time, team, hull, state, cause, source, x, y, life s,
## health 0.5 s before, retreat age s, source x, source y].
var deaths := []
## Every stuck episode (the first 600): [time, team, hull, state, x, y, goal
## x, goal y, goal distance, own mothership hull distance, rocks near, in
## open lane, seconds since launch, speed, angle to the goal (rad), route
## length, route index, forward x100, unstick timer, stuck timer, what the
## last move slid along, solid things within 450, the pilot's callsign, the
## rock class (2 = the ship touched a rock or was within ROCK_CONTACT_GAP of
## one, 1 = within ROCK_NEAR_GAP, 0 = in the open), the time the episode ended
## (-1 = never logged), why it ended ("moved", "died", "docked" or "end") and
## the seconds of rock contact during it].
var stucks := []
## Every trap (the first MAX_TRAPS): [time found minus 60, time it ended, team,
## callsign, hull, state when found, x and y where it was found, seconds of
## rock contact, share of the time spent fighting, share with an empty path,
## share with an escape flying, why it ended ("left", "died", "docked" or
## "end")]. A trap that is mostly a fight (a camp being farmed) is counted in
## "traps_farming" as well.
var traps := []


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
			# This pilot's own rock ticks: for its stuck episode and its trap.
			var hr := _h(b.profile.callsign)
			hr["rock_cur"] += 1
			if hr["row"] >= 0:
				hr["rock_ep"] += 1
			if hr["trap"] != null:
				(hr["trap"] as Dictionary)["rock_ticks"] += 1
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
		print("AUDIT t=%d stuck=%d rock_s=%.0f occl=%d/%d home_nofire=%d hold_far=%d/%d noroute=%d deaths=%d crash_deaths=%d traps=%d" % [int(world.time),
			int(c.get("stuck_episodes", 0)), float(c.get("rock_contact_ticks", 0)) / 60.0, int(c.get("occluded", 0)), int(c.get("fight_samples", 0)),
			int(c.get("home_target_in_reach", 0)), int(c.get("hold_far_not_approaching", 0)), int(c.get("hold_far", 0)),
			int(c.get("no_route_far", 0)), int(c.get("pilot_deaths", 0)), int(c.get("death_crash", 0)), int(c.get("traps", 0))])
	if world.time >= secs or world.phase != "play":
		# Episodes and traps still running end here.
		for key in _hist.keys():
			_episode_end(_hist[key], "end")
			_trap_end(_hist[key], "end")
		print("AUDIT_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "counters": c, "examples": ex, "deaths": deaths, "stucks": stucks, "traps": traps}))
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
		var h := _h(key)
		seen[key] = true
		_add("samples")
		_add("state_" + b.state)
		_add("samples_" + s.hull_id)
		# Time spent in an escape (PilotEscape) by hull.
		if b.flight.escape.is_active():
			_add("escape_samples")
			_add("escape_samples_" + s.hull_id)
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
		# A running trap: how this sample was spent.
		if h["trap"] != null:
			var tp: Dictionary = h["trap"]
			tp["n"] += 1
			if fighting:
				tp["fight"] += 1
			if b.path.is_empty():
				tp["path_empty"] += 1
			if b.flight.escape.is_active():
				tp["esc"] += 1
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
		# 4. Far from the goal with no route planned. The path is also empty
		# while an escape flies; that is counted apart ("no_route_escape"), and
		# "no_route_plain" is an empty path with no escape on.
		var gd := s.global_position.distance_to(b.goal)
		if not fighting and gd > 2500.0 and b.path.is_empty():
			_add("no_route_far")
			_add("no_route_escape" if b.flight.escape.is_active() else "no_route_plain")
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
## last 8 s while more than 800 from its goal, and not fighting, is stuck. The
## same positions feed the trap rule (_trap_check). A pilot that is no longer
## flying (it died or docked) ends its episode and its trap.
func _positions() -> void:
	var seen := {}
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var b := s.controller as PilotAI
		var h := _h(b.profile.callsign)
		seen[b.profile.callsign] = true
		var ps: Array = h["pos"]
		ps.append(s.global_position)
		if ps.size() > 5:
			ps.pop_front()
		_trap_check(s, b, h)
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
			_episode_start(s, b, h)
		elif h["stuck"] and not stuck:
			_episode_end(h, "moved")
		if stuck:
			_add("stuck_seconds", 2.0)
			_add("stuck_seconds_" + s.hull_id, 2.0)
			_add("stuck_seconds_" + ROCK_CLASSES[int(h["cls"])], 2.0)
		h["stuck"] = stuck
	# Pilots no longer in the sky: their episode and trap are over.
	for key in _hist.keys():
		if seen.has(key):
			continue
		var gone: Dictionary = _hist[key]
		var why := "died" if world.time - float(gone["dead_t"]) < 4.0 else "docked"
		_episode_end(gone, why)
		_trap_end(gone, why)
		gone["stuck"] = false
		(gone["tpos"] as Array).clear()
		(gone["trock"] as Array).clear()


## The history of the pilot called `key`: it is made the first time it is
## asked for (see `_hist` for what it holds).
func _h(key: String) -> Dictionary:
	if not _hist.has(key):
		_hist[key] = {"pos": [], "state": "", "target": 0, "stuck": false, "row": -1, "cls": 0, "rock_ep": 0,
			"tpos": [], "trock": [], "trap": null, "rock_cur": 0, "dead_t": -999.0}
	return _hist[key]


## How near the nearest rock is to a circle at `p` with radius `r`: the gap
## (world units) between the circle and the rock's solid circle (95% of its
## radius), negative when they overlap.
func _rock_gap(p: Vector2, r: float) -> float:
	var near := PackedInt32Array()
	world.asteroids.nearby(p, r + 400.0, near)
	var best := 9999.0
	for i in near:
		best = minf(best, p.distance_to(world.asteroids.pos[i]) - 0.95 * world.asteroids.rad[i] - r)
	return best


## A stuck episode begins (ship `s`, brain `b`, history `h`): count it by
## state, rock class and team, keep an example and, for the first 600, a row
## in `stucks`.
func _episode_start(s: Ship, b: PilotAI, h: Dictionary) -> void:
	_add("stuck_episodes")
	_add("stuck_" + b.state)
	_example("stuck", {"who": b.profile.callsign, "hull": s.hull_id, "state": b.state, "pos": _v(s.global_position), "goal": _v(b.goal),
		"goal_d": roundi(s.global_position.distance_to(b.goal)), "open": world.map.in_open_lane(s.global_position),
		"rocks_near": not world.asteroids.clear_at(s.global_position, s.radius + 60.0), "path": b.path.size(), "path_i": b.path_i})
	# Its rock class: on a rock (2), next to one (1) or in the open (0).
	var slid := _colliders(s).contains("rock")
	var gap := _rock_gap(s.global_position, s.radius)
	var cls := 2 if (slid or gap <= ROCK_CONTACT_GAP) else (1 if gap <= ROCK_NEAR_GAP else 0)
	h["cls"] = cls
	_add("stuck_class_" + ROCK_CLASSES[cls])
	_add("stuck_team_%d" % s.team)
	if cls > 0:
		_add("stuck_rock_team_%d" % s.team)
	h["row"] = -1
	h["rock_ep"] = 0
	if stucks.size() < 600:
		var oms := world.mothership(s.team)
		stucks.append([roundi(world.time), s.team, s.hull_id, b.state, roundi(s.global_position.x), roundi(s.global_position.y),
			roundi(b.goal.x), roundi(b.goal.y), roundi(s.global_position.distance_to(b.goal)),
			roundi(oms.hull_dist(s.global_position)) if oms != null else -1,
			not world.asteroids.clear_at(s.global_position, s.radius + 60.0), world.map.in_open_lane(s.global_position),
			roundi(world.time - b.launched_at), roundi(s.velocity.length()), snappedf(absf(Util.ang_diff(s.rotation, (b.goal - s.global_position).angle())), 0.01),
			b.path.size(), b.path_i, roundi(s.controls.forward * 100.0), snappedf(b.flight._unstick_t, 0.1), snappedf(b.flight._stuck_t, 0.1), _colliders(s), _near(s),
			b.profile.callsign, cls, -1, "", 0.0])
		h["row"] = stucks.size() - 1


## The running stuck episode of history `h` ends now, for reason `why`
## ("moved", "died", "docked" or "end"): its row in `stucks` gets the end
## time, the reason and the seconds of rock contact. Does nothing when no
## episode has a row.
func _episode_end(h: Dictionary, why: String) -> void:
	var row: int = h["row"]
	if row < 0:
		return
	var r: Array = stucks[row]
	r[24] = roundi(world.time)
	r[25] = why
	r[26] = snappedf(float(h["rock_ep"]) / 60.0, 0.1)
	h["row"] = -1


## Every 2 s for each flying pilot: add the position and the rock ticks since
## the last sample to the 60-second window, look for a new trap, and end a
## trap that the ship has left.
func _trap_check(s: Ship, b: PilotAI, h: Dictionary) -> void:
	var tpos: Array = h["tpos"]
	tpos.append(s.global_position)
	if tpos.size() > TRAP_WINDOW:
		tpos.pop_front()
	var trock: Array = h["trock"]
	trock.append(h["rock_cur"])
	if trock.size() > TRAP_WINDOW:
		trock.pop_front()
	h["rock_cur"] = 0
	if tpos.size() < TRAP_WINDOW:
		return
	var trap: Variant = h["trap"]
	if trap != null:
		if s.global_position.distance_to((trap as Dictionary)["center"]) > TRAP_RADIUS + TRAP_LEAVE_MARGIN:
			_trap_end(h, "left")
		return
	# The ship stayed within TRAP_RADIUS of where the window began, scraping rock.
	var farthest := 0.0
	for p: Vector2 in tpos:
		farthest = maxf(farthest, p.distance_to(tpos[0]))
	var rock_ticks := 0
	for v in trock:
		rock_ticks += int(v)
	if farthest < TRAP_RADIUS and rock_ticks >= TRAP_ROCK_TICKS:
		h["trap"] = {"t0": world.time - 2.0 * float(TRAP_WINDOW), "team": s.team, "who": b.profile.callsign, "hull": s.hull_id, "state0": b.state,
			"center": s.global_position, "rock_ticks": rock_ticks, "n": 0, "fight": 0, "path_empty": 0, "esc": 0}


## The running trap of history `h` (if any) ends now, for reason `why`
## ("left", "died", "docked" or "end"): count it and keep its row in `traps`.
func _trap_end(h: Dictionary, why: String) -> void:
	var trap: Variant = h["trap"]
	if trap == null:
		return
	h["trap"] = null
	var tp: Dictionary = trap
	var samples := maxf(1.0, float(tp["n"]))
	var secs_in := world.time - float(tp["t0"])
	var fight_share := float(tp["fight"]) / samples
	_add("traps")
	_add("trap_seconds", secs_in)
	_add("trap_rock_seconds", float(tp["rock_ticks"]) / 60.0)
	_add("traps_team_%d" % int(tp["team"]))
	# A pilot that fought for most of the time is farming a camp, not stuck.
	if fight_share >= 0.5:
		_add("traps_farming")
		_add("trap_seconds_farming", secs_in)
	if traps.size() < MAX_TRAPS:
		var centre: Vector2 = tp["center"]
		traps.append([roundi(tp["t0"]), roundi(world.time), tp["team"], tp["who"], tp["hull"], tp["state0"], roundi(centre.x), roundi(centre.y),
			snappedf(float(tp["rock_ticks"]) / 60.0, 0.1), snappedf(fight_share, 0.01), snappedf(float(tp["path_empty"]) / samples, 0.01),
			snappedf(float(tp["esc"]) / samples, 0.01), why])


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
	var h := _h(b.profile.callsign)
	h["dead_t"] = world.time
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
