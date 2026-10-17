extends Node
## WHAT THIS IS: a bug hunt for the AI admiral. Once a second it samples
## both teams' admiral-level state and keeps counters and a short timeline:
## treasury, build-plan steps finished, drones (and how many sit idle),
## turrets, repair bays (and their lane), wards, the waypoint's lane, the
## "push lane" (how often it
## flips, and whether it agrees with the lane whose minions are furthest as
## a FRACTION of the lane), sieges (declared, phases, why they ended, hull
## the enemy mothership lost during our assaults), mothership moves and how
## long it stays up a lane, who kills our repair bays, wards, turrets and
## mining drones (killer kind, place, age), credits spent per sink, how far
## apart the motherships are, where our pilots stand per lane, and how the
## match ended.
##
## HOW IT WORKS: setup() connects to the admiral's order results
## (Events.admiral_result), kills (Events.unit_killed) and the end of the
## match. _physics_process() calls _sample() for each computer admiral once a
## second, prints one "ADM" line every 60 game seconds and, at the end, one
## "AUDIT_JSON {...}" line with every counter, the build-plan finish times,
## the event timeline and the structure deaths.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=7 --test=admiral_audit --secs=1800
## --late starts at 25:00 fully teched (LateGame.apply) and --secs then
## counts from there (for example --late --secs=900).
##
## WHO USES IT: main.gd loads it for --test=admiral_audit. It only reads the
## game (and connects to Events); it adds no orders and changes nothing in
## the match.


## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 1800.0
## Seconds until the next once-a-second sample.
var _t := 0.0
## Game time of the next ADM line.
var _report_t := 60.0
## Per team: counters (name -> number).
var c := [{}, {}]
## Per team: match time each build-plan step was finished.
var plan_t := [{}, {}]
## Timeline of events: [time, team, what, detail].
var ev := []
## Our structures that died: [time, team, what, detail] (kept apart so the
## main timeline never fills up).
var deaths := []
## Per team: last values (push lane, siege lane/phase, ms move target...).
var _last := [{}, {}]
## Birth time of each bay / ward / turret we have seen: instance id -> time.
var _born := {}
## Last hull fraction of each mothership (to add up the hull it lost).
var _ms_hp := [1.0, 1.0]
## Why the match ended (from Events.match_over); empty until it does.
var _end_reason := ""
## The winning team (from Events.match_over); -2 until the match ends.
var _end_winner := -2


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1800.0))
	if Game.opt("late", false):
		LateGame.apply(world)
		secs += LateGame.START
		_report_t = LateGame.START + 60.0
	Events.admiral_result.connect(_on_result)
	Events.unit_killed.connect(_on_killed)
	Events.match_over.connect(_on_over)


## The match ended (Events.match_over): remember who won and why.
func _on_over(winner: int, reason: String) -> void:
	_end_winner = winner
	_end_reason = reason


## Every admiral order's result (AdmiralCommand._done): count ok/failed by
## action, and failures by reason (numbers cut off).
func _on_result(team: int, action: String, ok: bool, msg: String) -> void:
	if team < 0 or team > 1:
		return
	_add(team, "cmd_%s_%s" % [action, "ok" if ok else "fail"])
	if not ok:
		# Cut the numbers off ("no building for 12s" -> "no building for s").
		var key := msg.get_slice("(", 0).strip_edges()
		for d in "0123456789":
			key = key.replace(d, "")
		_add(team, "fail_%s: %s" % [action, key])


## Add `n` to counter `k` of team `t`.
func _add(t: int, k: String, n: float = 1.0) -> void:
	c[t][k] = float(c[t].get(k, 0.0)) + n


## Add a line to the timeline (at most 400 lines).
func _event(t: int, what: String, detail: Variant) -> void:
	if ev.size() < 400:
		ev.append([snappedf(world.time, 1.0), t, what, detail])


## Who dealt the killing blow, as a short word.
func _killer(info: DamageInfo) -> String:
	if info == null:
		return "none"
	if info.source_team == Rules.NEUTRAL:
		return "neutral"
	var big := info.source_size >= Rules.SIZE_LARGE
	if info.source_is_pilot:
		return "pilot_big" if big else "pilot_small"
	if info.source_is_minion:
		return "minion"
	var s: Unit = info.source if is_instance_valid(info.source) else null
	if s != null:
		match s.kind:
			Unit.K_TURRET:
				return "turret"
			Unit.K_MOTHERSHIP:
				return "mothership"
			Unit.K_SHIP:
				return "ship_ai_big" if big else "ship_ai_small"
			Unit.K_MINION:
				return "minion"
			Unit.K_MONSTER:
				return "monster"
	return "other"


## Something died (Events.unit_killed). We record deaths of our own
## structures and mining drones: who killed it, where, how old it was.
func _on_killed(unit: Node, info: RefCounted) -> void:
	if world == null or not is_instance_valid(unit):
		return
	var u := unit as Unit
	if u == null or u.team < 0 or u.team > 1:
		return
	var t := u.team
	var di := info as DamageInfo
	var who := _killer(di)
	var age := -1.0
	var uid := u.get_instance_id()
	if _born.has(uid):
		age = world.time - float(_born[uid])
	match u.kind:
		Unit.K_BAY:
			_add(t, "bay_died")
			_add(t, "bay_died_by_" + who)
			if age >= 0.0:
				_add(t, "bay_life_sum", age)
			var b := u as RepairBay
			var lane := world.map.lane_for(u.global_position)
			var pts := MapLayout.lane_points(lane, t)
			var pr := Util.project_on_polyline(u.global_position, pts)
			# Enemy things near it at the time.
			var near_ships := 0
			var near_big := 0
			var near_min := 0
			for s: Ship in world.ships:
				if s.team != t and s.alive and s.global_position.distance_to(u.global_position) < 2500.0:
					if s.size_class >= Rules.SIZE_LARGE:
						near_big += 1
					else:
						near_ships += 1
			for m in world.minions:
				if m.team != t and m.alive and m.global_position.distance_to(u.global_position) < 2500.0:
					near_min += 1
			var own_near := 0
			for m in world.minions:
				if m.team == t and m.alive and m.global_position.distance_to(u.global_position) < 2500.0:
					own_near += 1
			_add(t, "bay_died_" + ("anchored" if b != null and b.is_anchored() else "flying"))
			if deaths.size() < 300:
				deaths.append([snappedf(world.time, 1.0), t, "bay", {"lane": lane, "frac": snappedf(float(pr["s"]) / Util.polyline_length(pts), 0.01),
					"off": roundi(float(pr["dist"])), "age": roundi(age), "by": who, "state": b.state if b != null else "?", "def": b.has_defenses if b != null else false,
					"e_small": near_ships, "e_big": near_big, "e_min": near_min, "own_min": own_near, "x": roundi(u.global_position.x), "y": roundi(u.global_position.y)}])
		Unit.K_WARD:
			_add(t, "ward_died")
			_add(t, "ward_died_by_" + who)
			if age >= 0.0:
				_add(t, "ward_life_sum", age)
		Unit.K_TURRET:
			var tu := u as Turret
			var nk := "?"
			if tu != null and tu.node != null:
				nk = tu.node.node_kind
			_add(t, "turret_died_" + nk)
			_add(t, "turret_died_by_" + who)
			_add(t, "turret_lost_credits", float(TurretData.TURRETS[tu.ttype]["cost"]) if tu != null else 0.0)
		Unit.K_MINING_DRONE:
			_add(t, "drone_died")
			_add(t, "drone_died_by_" + who)
		Unit.K_MOTHERSHIP:
			_event(t, "ms_died", who)


## Every tick: sample both admirals once a second, print the minute lines and,
## when the time is up (or the match is over), print the final JSON line and quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 1.0
		for t in 2:
			if world.admiral_ai[t] != null:
				_sample(t)
	if world.time >= _report_t:
		_report_t += 60.0
		var parts := []
		for t in 2:
			var ts := world.teams[t]
			var ms := world.mothership(t)
			parts.append("T%d tre=%d push=%s wp=%s siege=%s/%s ms_away=%d hull=%.2f bays=%d wards=%d plan=%d" % [t, int(ts.treasury), _last[t].get("push", "-"),
				world.map.lane_for(ts.waypoint) if ts.has_waypoint() else "-", ts.siege_lane, ts.siege_phase,
				roundi(ms.global_position.distance_to(world.map.mothership_pos[t])) if ms != null else -1, ms.hull_frac() if ms != null else 0.0,
				_count(world.bays, t), _count(world.wards, t), (plan_t[t] as Dictionary).size()])
		print("ADM t=%d  %s" % [int(world.time), "  |  ".join(parts)])
	if world.time >= secs or world.phase != "play":
		for t in 2:
			var ms := world.mothership(t)
			c[t]["end_ms_hull"] = ms.hull_frac() if ms != null and ms.alive else 0.0
			c[t]["end_treasury"] = world.teams[t].treasury
			# Credits spent on the plan steps that finished.
			var plan_cost := 0.0
			for s: Array in AdmiralPlan.PLAN:
				if (plan_t[t] as Dictionary).has(s[1]):
					plan_cost += float(Tech.FACILITIES[s[1]]["cost"]) if s[0] == "f" else float(Tech.TECHS[s[1]]["cost"])
			c[t]["spent_plan"] = plan_cost
			c[t]["spent_bays"] = float(c[t].get("cmd_bay_ok", 0.0)) * float(Structures.REPAIR_BAY["cost"])
			c[t]["spent_wards"] = float(c[t].get("cmd_ward_ok", 0.0)) * float(Structures.WARD["cost"])
			c[t]["spent_drones"] = float(c[t].get("cmd_drone_ok", 0.0)) * float(Structures.MINING_DRONE["cost"])
		print("AUDIT_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "phase": world.phase, "winner": _end_winner, "reason": _end_reason,
			"counters": c, "plan_t": plan_t, "events": ev, "deaths": deaths}))
		get_tree().quit()


## Alive things of team t in list `arr` (bays, wards, turrets).
func _count(arr: Array, t: int) -> int:
	var n := 0
	for u in arr:
		if u.team == t and u.alive:
			n += 1
	return n


## The once-a-second look at team `t`'s admiral: treasury, plan, lanes,
## sieges, mothership, structures and fleet (see the file header).
func _sample(t: int) -> void:
	var ts := world.teams[t]
	var ai := world.admiral_ai[t] as AdmiralAI
	var L: Dictionary = _last[t]
	_add(t, "samples")
	# Treasury: average, peak, time above 2k / 5k / 10k.
	_add(t, "tre_sum", ts.treasury)
	c[t]["tre_max"] = maxf(float(c[t].get("tre_max", 0.0)), ts.treasury)
	for lim in [2000, 5000, 10000]:
		if ts.treasury > lim:
			_add(t, "tre_over_%d_s" % lim)
	# Build plan: when each step got finished.
	for s: Array in AdmiralPlan.PLAN:
		var id: String = s[1]
		var fin: bool = ts.facilities.has(id) if s[0] == "f" else ts.done.has(id)
		if fin and not (plan_t[t] as Dictionary).has(id):
			plan_t[t][id] = snappedf(world.time, 1.0)
	if (plan_t[t] as Dictionary).size() == AdmiralPlan.PLAN.size() and not L.has("plan_done"):
		L["plan_done"] = true
		c[t]["plan_done_t"] = world.time
	# Push lane: share per lane, flips, and agreement with the lane whose
	# minions are furthest as a fraction of the lane's length.
	var pl := ai.lanes.push_lane()
	_add(t, "push_" + (pl if pl != "" else "none"))
	if pl != L.get("push", ""):
		_add(t, "push_flips")
	L["push"] = pl
	var best_f := -1.0
	var best_l := ""
	for lane: String in MapLayout.LANE_ORDER:
		var f := ai.lanes.front_frac(lane)
		if f > best_f:
			best_f = f
			best_l = lane
	_add(t, "fracfront_" + best_l)
	if pl != "" and pl != best_l:
		_add(t, "push_ne_fracfront")
	# Waypoint lane.
	if ts.has_waypoint():
		var wl := world.map.lane_for(ts.waypoint)
		_add(t, "wp_" + wl)
		if wl != L.get("wl", wl):
			_add(t, "wp_flips")
		L["wl"] = wl
	# Where our pilots stand (ships within 2,500 of a lane line count for it).
	for s: Ship in world.ships:
		if s.team == t and s.alive:
			var ln := world.map.lane_for(s.global_position)
			if Util.dist_to_polyline(s.global_position, MapLayout.lane_points(ln, t)) < 2500.0:
				_add(t, "pil_" + ln)
			else:
				_add(t, "pil_other")
	# Sieges.
	var ems := world.mothership(1 - t)
	var sl := ts.siege_lane
	var sp := ts.siege_phase
	if sl != L.get("sl", "") or sp != L.get("sp", ""):
		if L.get("sl", "") == "" and sl != "":
			_add(t, "siege_declared")
			L["siege_start"] = world.time
			L["siege_hp0"] = ems.hull_frac() if ems != null else 1.0
			_event(t, "siege", [sl, snappedf(L["siege_hp0"], 0.01)])
		elif sl == "" and L.get("sl", "") != "":
			_add(t, "siege_off")
			var dur := roundi(world.time - float(L.get("siege_start", world.time)))
			# Why it ended: the defend call renewed this second, or the
			# admiral's own call-off (no big ships / stalled).
			var by_def := ts.defend_until - world.time > 10.5
			var why := "defend" if by_def else "admiral"
			var hp1 := ems.hull_frac() if ems != null and ems.alive else 0.0
			_add(t, "siege_off_" + why)
			_add(t, "siege_off_" + L.get("sp", "") + "_" + why)
			_add(t, "siege_dur_sum", dur)
			_event(t, "siege_off", {"phase": L.get("sp", ""), "dur": dur, "why": why, "hp0": snappedf(float(L.get("siege_hp0", 1.0)), 0.01), "hp1": snappedf(hp1, 0.01)})
		elif sl != L.get("sl", ""):
			_event(t, "siege_lane", sl)
		elif sp != L.get("sp", ""):
			_event(t, "siege_phase", sp)
	L["sl"] = sl
	L["sp"] = sp
	if sl != "":
		_add(t, "siege_s_" + sp)
	# Siege readiness: could the admiral start one now? (After 20:00, two
	# healthy big ships, the edge, no cooldown.) Split by the defend call.
	if sl == "" and world.time >= 1200.0 and world.time >= ai.siege.cooldown_until:
		var healthy := 0
		for s: Ship in world.ships:
			if s.team == t and s.alive and s.size_class >= Rules.SIZE_LARGE and s.hull_frac() > 0.5:
				healthy += 1
		var edge := ai.lanes.fleet_power(t) >= ai.lanes.fleet_power(1 - t) * 1.2 or (ems != null and ems.hull_frac() <= 0.6)
		if healthy >= 2 and edge:
			_add(t, "siege_ready_s")
			if ts.defending(world.time):
				_add(t, "siege_ready_blocked_def_s")
	# Enemy mothership hull lost: in total, and while our assault runs.
	if ems != null:
		var hp := ems.hull_frac() if ems.alive else 0.0
		var drop: float = _ms_hp[1 - t] - hp
		if drop > 0.0:
			_add(t, "ems_hull_lost", drop)
			if sp == "assault":
				_add(t, "ems_hull_lost_assault", drop)
		_ms_hp[1 - t] = hp
		# Our bigs near the enemy hull during an assault.
		if sp == "assault":
			var near := 0
			for s: Ship in world.ships:
				if s.team == t and s.alive and s.size_class >= Rules.SIZE_LARGE and ems.hull_dist(s.global_position) < 3000.0:
					near += 1
			_add(t, "assault_bigs_near_sum", near)
			if near > 0:
				_add(t, "assault_contact_s")
	# Our mothership: moves, time away from home, lane while away.
	var ms := world.mothership(t)
	if ms != null and ms.alive:
		var home: Vector2 = world.map.mothership_pos[t]
		if ms.move_target != Vector2.INF and ms.move_target != L.get("mt", Vector2.INF):
			_add(t, "ms_moves")
			var el := world.map.lane_for(ems.global_position) if ems != null else "-"
			_event(t, "ms_move", {"lane": world.map.lane_for(ms.move_target), "from_home": roundi(ms.move_target.distance_to(home)), "hull": snappedf(ms.hull_frac(), 0.01), "enemy_ms_lane": el})
		L["mt"] = ms.move_target
		if ms.move_target != Vector2.INF:
			_add(t, "ms_moving_s")
		if ms.global_position.distance_to(home) > 2500.0:
			_add(t, "ms_away_s")
			_add(t, "ms_lane_" + world.map.lane_for(ms.global_position))
		if ems != null and ems.alive:
			_add(t, "ms_gap_sum", ms.hull_dist(ems.global_position))
	# Structures and economy.
	_add(t, "bays_sum", _count(world.bays, t))
	_add(t, "wards_sum", _count(world.wards, t))
	_add(t, "turrets_sum", _count(world.turrets, t))
	_add(t, "drones_sum", world.mining_drone_count(t))
	# Idle mining drones: ones with no ore node to work, waiting beside the
	# mothership (MiningDrone state "idle"). Drone-seconds spent idle, and the
	# seconds in which at least one drone was idle.
	var idle := 0
	for d: MiningDrone in world.mining_drones:
		if d.team == t and d.alive and d.state == "idle":
			idle += 1
	_add(t, "drones_idle_sum", idle)
	if idle > 0:
		_add(t, "drones_idle_s")
	for b in world.bays:
		if b.team == t and b.alive and not _born.has(b.get_instance_id()):
			_born[b.get_instance_id()] = world.time
			_add(t, "bays_made")
			var bl := world.map.lane_for(b.anchor)
			_add(t, "bays_made_" + bl)
			_event(t, "bay", {"lane": bl, "anchor": [roundi(b.anchor.x), roundi(b.anchor.y)]})
	for w in world.wards:
		if w.team == t and w.alive and not _born.has(w.get_instance_id()):
			_born[w.get_instance_id()] = world.time
			_add(t, "wards_made")
	for tu in world.turrets:
		if tu.team == t and tu.alive and not _born.has(tu.get_instance_id()):
			_born[tu.get_instance_id()] = world.time
			_add(t, "turrets_made")
			_add(t, "spent_turrets", float(TurretData.TURRETS[tu.ttype]["cost"]))
	# Big ships and fleet power.
	var bigs := 0
	for s: Ship in world.ships:
		if s.team == t and s.alive and s.size_class >= Rules.SIZE_LARGE:
			bigs += 1
	_add(t, "bigs_sum", bigs)
	if ts.defending(world.time):
		_add(t, "defending_s")
		if ms != null and ms.global_position.distance_to(world.map.mothership_pos[t]) > 2500.0:
			_add(t, "defending_away_s")
	if ai.lanes.fleet_power(t) >= ai.lanes.fleet_power(1 - t) * 1.2:
		_add(t, "fleet_edge_s")
