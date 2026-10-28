extends Node
## WHAT THIS IS: the "farming probe": a measuring tool for what the lane
## pilots do with their time in an AI-vs-AI match. It answers six plain
## questions: how long lane pilots stand around with nothing to shoot, how
## many last hits on enemy minions they make, how many pilots die, how many
## get stuck, who wins and when, and how far from our wave's front minion the
## enemy minions are at the moments a lane pilot has nothing to do.
##
## HOW IT WORKS: it listens for two events (a unit killed, to count pilot
## deaths and last hits) and, every SAMPLE_EVERY (0.5) game seconds, looks at
## every flying AI pilot. A "lane pilot" is a pilot whose role is top, mid,
## bot or flex (not a jungler), counted only while its brain is in the "lane"
## state and its opening is over. A lane pilot is IDLE at a sample when it
## has no target and flies slower than IDLE_SPEED. A run of idle samples is
## an idle spell; a spell longer than PARKED_AFTER seconds is a PARKED spell,
## and its whole length counts as parked time. Every 2 s it also remembers
## each AI pilot's position, to count stuck ships the way tests/pilot_audit.gd
## does (moved under 150 in 8 s, more than 800 from the goal, not fighting).
## For the farm radius it keeps three histograms (bucket width BUCKET, the
## last bucket holds everything further): the distance from each lane's front
## minion to the nearest enemy minion, the same distance at the samples where
## a lane pilot of that lane is idle, and the distance from the idle pilot
## itself to the nearest enemy minion. It only reads the game and draws no
## random numbers, so the match plays exactly as without it. At the end (--secs,
## or when a mothership dies) it prints one "FARMING_PROBE_JSON {...}" line and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --skill-jitter --sim-only --test=farming_probe --secs=1800
## --secs is how many game seconds to watch (default 1800). With --late the
## match starts at 25:00 with both sides fully teched (LateGame.apply) and
## --secs counts from 25:00.
##
## HOW TO READ THE OUTPUT: FARMING_PROBE_JSON holds
##   "time", "ended", "winner"  the match clock at the end, whether a mothership
##                died, and the winning team (0 Aurelian, 1 Vhorr, -1 none);
##   "tot"        the counters summed over both teams, "team" the same per team;
##                a counter ending in _s is in seconds:
##                  lane_s        lane-pilot seconds sampled
##                  idle_s        seconds idle (no target, slower than IDLE_SPEED)
##                  parked_s      seconds inside idle spells longer than PARKED_AFTER
##                  parked_spells how many such spells
##                  intent_<x>_s  lane-pilot seconds by the brain's intent
##                                (none, push, prey, and farm when the build has it)
##                  stn_in_turret_s    seconds a station-seeking pilot's goal lay
##                                inside the hull of a live turret of its own team
##                  stn_near_turret_s  the same within 150 of that turret's centre
##                  stuck_episodes, stuck_s  stuck ships, all AI pilots, and
##                                stuck_lane_episodes, stuck_lane_s for lane pilots
##                  deaths, deaths_lane  AI pilot ships destroyed; deaths_by_<x>
##                                the killer (minion, pilot, turret, rock, other)
##                  lh_all, lh_lane  last hits on enemy minions by AI pilots, and
##                                by lane pilots only (from the kill events)
##                  minions_died  minions destroyed by anything (by the victim's team)
##   "front_enemy"       histogram: front minion to nearest visible enemy minion;
##   "idle_front_enemy"  the same at samples with an idle lane pilot on that lane
##                       (the counters idle_no_front and idle_no_enemy count the
##                       idle samples with no wave out, or no enemy minion at all);
##   "idle_pilot_enemy"  histogram: the idle pilot to the nearest visible enemy minion;
##   "parked_by_5min"    parked seconds per 300 s of match time (by spell end);
##   "station_notes"     up to STATION_NOTES cases of a station goal inside our own
##                       turret: [time, team, seat, hull, goal x, y, turret x, y, type,
##                       node, distance, brain state, falling back, evading, siege lane,
##                       defend call, hold point, ship x, y, speed, distance to the
##                       nearest enemy turret, its reach, a turret of ours on the lane
##                       under attack, the pilot's lane];
##   "pilots"     one row per lane pilot: team, slot, role, callsign, last hits
##                (lh), pilot kills, deaths, credits earned, and its own seconds
##                as a sampled lane pilot (lane_s), idle (idle_s) and parked
##                (parked_s).
##
## WHO USES IT: main.gd loads it for --test=farming_probe. A small script
## outside the game turns the FARMING_PROBE_JSON lines of two builds into the
## before/after table.

## Seconds of game time between two samples of the pilots.
const SAMPLE_EVERY := 0.5
## Seconds of game time between two position samples (for stuck ships).
const POSITION_EVERY := 2.0
## A pilot flying slower than this (world units per second) counts as still.
const IDLE_SPEED := 40.0
## An idle spell longer than this many seconds counts as parked.
const PARKED_AFTER := 5.0
## How many cases of a station goal inside our own turret are written down.
const STATION_NOTES := 40
## Width (world units) of one histogram bucket.
const BUCKET := 250.0
## How many buckets a histogram has before its last, open-ended bucket.
const BUCKETS := 16

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 1800.0
## Game time of the next pilot sample.
var _next_sample := 0.0
## Game time of the next position sample.
var _next_pos := 0.0
## Counters summed over both teams: name -> number.
var _tot := {}
## The same counters per team: [Aurelian's dictionary, Vhorr's dictionary].
var _team: Array = [{}, {}]
## Parked seconds per 300 s of match time.
var _parked_by_5min: Array = []
## Histogram: front minion to the nearest visible enemy minion.
var _front_enemy: Array = []
## Histogram: the same, at samples with an idle lane pilot on that lane.
var _idle_front_enemy: Array = []
## Histogram: an idle lane pilot to the nearest visible enemy minion.
var _idle_pilot_enemy: Array = []
## Per pilot key "team:slot": the length (seconds) of the idle spell going on.
var _run := {}
## Per pilot key "team:slot": its last positions (every POSITION_EVERY seconds).
var _pos := {}
## Per pilot key "team:slot": is a stuck episode going on?
var _stuck := {}
## Per pilot key "team:slot": seconds as a sampled lane pilot ("lane"), idle
## ("idle") and inside parked spells ("parked").
var _own := {}
## The cases of a station goal inside our own turret that were written down
## (see _note_station()).
var _station_notes: Array = []
## Per pilot key "team:slot": the match time of its last written-down case.
var _note_t := {}


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1800.0))
	# --late: the late-game setup (tests/lib/late_game.gd); --secs then counts
	# from 25:00.
	if Game.opt("late", false):
		LateGame.apply(world)
		secs += LateGame.START
	_next_sample = world.time
	_next_pos = world.time
	_front_enemy = _new_hist()
	_idle_front_enemy = _new_hist()
	_idle_pilot_enemy = _new_hist()
	Events.unit_killed.connect(_on_killed)


## A fresh histogram: BUCKETS + 1 zeros.
func _new_hist() -> Array:
	var h: Array = []
	for _i in BUCKETS + 1:
		h.append(0)
	return h


## Add one sample at distance `d` (world units) to histogram `h`.
func _hist_add(h: Array, d: float) -> void:
	var i := mini(int(d / BUCKET), BUCKETS)
	h[i] = int(h[i]) + 1


## Add `n` to counter `key`, for the total and for `team`'s own counters.
func _add(team: int, key: String, n: float = 1.0) -> void:
	_tot[key] = float(_tot.get(key, 0.0)) + n
	var d: Dictionary = _team[team]
	d[key] = float(d.get(key, 0.0)) + n


## Add `n` seconds to pilot `pkey`'s own counter `key` (see `_own`).
func _add_own(pkey: String, key: String, n: float) -> void:
	var d: Dictionary = _own.get(pkey, {})
	_own[pkey] = d
	d[key] = float(d.get(key, 0.0)) + n


## Is `p` one of the lane pilots (top, mid, bot or flex, not a jungler)?
func _is_lane(p: PilotProfile) -> bool:
	return p.role != "jungle"


## Does the brain have a live target? (A target can be freed, so test it
## before reading it.)
func _has_target(ai: PilotAI) -> bool:
	return ai.target != null and is_instance_valid(ai.target) and ai.target.alive


## Something died. For a pilot ship of the AI: count the death (and who
## killed it). For a minion killed by an enemy pilot: count the last hit.
func _on_killed(u: Node, info: RefCounted) -> void:
	var d := info as DamageInfo
	if u is Ship:
		var s := u as Ship
		if not (s.controller is PilotAI) or s.profile == null:
			return
		var team := s.profile.team
		_add(team, "deaths")
		var lane := _is_lane(s.profile)
		if lane:
			_add(team, "deaths_lane")
		# The killer: a minion, another pilot, a turret, a rock (collision), or
		# something else (the mothership, a derelict, a drone).
		var by := "other"
		if d != null:
			if d.kind == Rules.W_COLLISION:
				by = "rock"
			elif d.source_is_minion:
				by = "minion"
			elif d.source_is_pilot:
				by = "pilot"
			elif d.source != null and is_instance_valid(d.source) and d.source.kind == Unit.K_TURRET:
				by = "turret"
		_add(team, "deaths_by_" + by)
		if lane:
			_add(team, "deaths_lane_by_" + by)
	elif u is Minion:
		var m := u as Minion
		_add(m.team, "minions_died")
		var killer: PilotProfile = null
		if d != null:
			killer = d.source_profile as PilotProfile
		if killer != null and killer.team != m.team:
			_add(killer.team, "lh_all")
			if _is_lane(killer):
				_add(killer.team, "lh_lane")


## Every tick: take the samples that are due, and at the end print the JSON
## line and quit.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time >= _next_sample:
		_next_sample += SAMPLE_EVERY
		_sample()
	if world.time >= _next_pos:
		_next_pos += POSITION_EVERY
		_positions()
	if world.time >= secs or world.phase != "play":
		_finish()


## The live minion of `team` furthest along `lane` (only minions within 2,500
## of the lane line count, as PilotGoals.wave_front_s() counts them), or null
## with no wave out.
func _front_minion(team: int, lane: String) -> Minion:
	var pts := MapLayout.lane_points(lane, team)
	var best: Minion = null
	var best_s := -1.0
	for m: Minion in world.minions:
		if m.team != team or not m.alive or m.lane != lane:
			continue
		var pr := Util.project_on_polyline(m.global_position, pts)
		if float(pr["dist"]) < 2500.0 and float(pr["s"]) > best_s:
			best_s = pr["s"]
			best = m
	return best


## The distance from point `p` to the nearest live minion that is not of team
## `team` and that `team` can see, or -1.0 when there is none.
func _nearest_enemy_minion(p: Vector2, team: int) -> float:
	var best := -1.0
	for m: Minion in world.minions:
		if m.team == team or not m.alive or not m.visible_to(team):
			continue
		var d := p.distance_to(m.global_position)
		if best < 0.0 or d < best:
			best = d
	return best


## One sample: the fronts, then every flying AI pilot.
func _sample() -> void:
	var dt := SAMPLE_EVERY
	# Step 1: each team's front minion on each lane, and how far the nearest
	# enemy minion is from it.
	var fronts := {}
	var front_dist := {}
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			var key := "%d:%s" % [team, lane]
			var fm := _front_minion(team, lane)
			fronts[key] = fm
			var fd := -1.0
			if fm != null:
				fd = _nearest_enemy_minion(fm.global_position, team)
				if fd >= 0.0:
					_hist_add(_front_enemy, fd)
			front_dist[key] = fd
	# Step 2: every pilot. A pilot that is not a flying lane pilot ends its
	# idle spell.
	for p: PilotProfile in world.profiles:
		var ai: PilotAI = world.pilot_ai.get(p)
		var pkey := "%d:%d" % [p.team, p.slot]
		var ship: Ship = null
		if ai != null and p.state == "flying" and p.ship != null and is_instance_valid(p.ship) and p.ship.alive:
			ship = p.ship
		if ship == null or not _is_lane(p) or ai.state != "lane" or not ai.opening_done:
			_close_spell(pkey, p.team)
			continue
		_add(p.team, "lane_s", dt)
		_add_own(pkey, "lane", dt)
		var intent := ai.intent if ai.intent != "" else "none"
		_add(p.team, "intent_" + intent + "_s", dt)
		var has_t := _has_target(ai)
		var idle := not has_t and ship.velocity.length() < IDLE_SPEED
		# Step 3: a station goal inside one of our own turrets.
		if not has_t and ai.intent == "":
			for t: Turret in world.turrets:
				if t.team != p.team or not t.alive:
					continue
				var gd := ai.goal.distance_to(t.global_position)
				if gd < t.radius + ship.radius:
					_add(p.team, "stn_in_turret_s", dt)
					_note_station(p, ai, ship, t, gd)
				if gd < 150.0:
					_add(p.team, "stn_near_turret_s", dt)
		if not idle:
			_close_spell(pkey, p.team)
			continue
		# Step 4: an idle sample. Count the spell, and note how far the nearest
		# enemy minion is from the lane's front minion and from the pilot.
		_add(p.team, "idle_s", dt)
		_add_own(pkey, "idle", dt)
		_run[pkey] = float(_run.get(pkey, 0.0)) + dt
		var lane_id: String = ai.goals.rotation_lane() if p.role == "flex" else ai.goals.lane_id()
		var fkey := "%d:%s" % [p.team, lane_id]
		if fronts[fkey] == null:
			_add(p.team, "idle_no_front")
		elif float(front_dist[fkey]) < 0.0:
			_add(p.team, "idle_no_enemy")
		else:
			_hist_add(_idle_front_enemy, float(front_dist[fkey]))
		var pd := _nearest_enemy_minion(ship.global_position, p.team)
		if pd >= 0.0:
			_hist_add(_idle_pilot_enemy, pd)


## Write down one case of a station goal inside our own turret `t` (at most
## STATION_NOTES in a match, and a pilot only once in 5 seconds): the time,
## the pilot (team, seat, hull), its goal, the turret (place, type, node),
## the distance, the brain's state and which orders were on (falling back,
## evading, a siege, the defend call, a hold point), and where the ship was.
func _note_station(p: PilotProfile, ai: PilotAI, ship: Ship, t: Turret, gd: float) -> void:
	var pkey := "%d:%d" % [p.team, p.slot]
	if _station_notes.size() >= STATION_NOTES or world.time - float(_note_t.get(pkey, -99.0)) < 5.0:
		return
	_note_t[pkey] = world.time
	var ts: TeamState = world.teams[p.team]
	# The nearest live enemy turret to the goal, how far and how far it reaches
	# (a goal at its reach + 350 was moved there by the keep-out from enemy
	# turrets), and whether a turret of ours on this lane is under attack (the
	# defend order puts the goal 300 from that turret).
	var lane_id: String = ai.goals.rotation_lane() if p.role == "flex" else ai.goals.lane_id()
	var near_d := -1.0
	var near_r := 0.0
	for e: Turret in world.turrets:
		if e.team == p.team or e.team == Rules.NEUTRAL or not e.alive:
			continue
		var ed := ai.goal.distance_to(e.global_position)
		if near_d < 0.0 or ed < near_d:
			near_d = ed
			near_r = e.range_r
	var threatened := ai.senses.turret_under_attack(p.team, lane_id) != null
	_station_notes.append([snappedf(world.time, 0.1), p.team, p.slot, ship.hull_id, roundi(ai.goal.x), roundi(ai.goal.y),
			roundi(t.global_position.x), roundi(t.global_position.y), t.ttype, t.node.node_name if t.node != null else "?", roundi(gd),
			ai.state, ai.fallback_t > 0.0, ai.evade_t > 0.0, ts.siege_lane, ts.defending(world.time), ai.hold_point != Vector2.INF,
			roundi(ship.global_position.x), roundi(ship.global_position.y), roundi(ship.velocity.length()),
			roundi(near_d), roundi(near_r), threatened, lane_id])


## End pilot `pkey`'s idle spell (if one is going on) and book it.
func _close_spell(pkey: String, team: int) -> void:
	var run := float(_run.get(pkey, 0.0))
	_run[pkey] = 0.0
	if run <= PARKED_AFTER:
		return
	_add(team, "parked_s", run)
	_add(team, "parked_spells")
	_add_own(pkey, "parked", run)
	var w := int(world.time / 300.0)
	while _parked_by_5min.size() <= w:
		_parked_by_5min.append(0.0)
	_parked_by_5min[w] = float(_parked_by_5min[w]) + run


## Every POSITION_EVERY seconds: remember each flying AI pilot's position. A
## pilot that moved under 150 over the last 8 s while more than 800 from its
## goal, and was not fighting, is stuck (the rule of tests/pilot_audit.gd).
func _positions() -> void:
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var ai := s.controller as PilotAI
		var key := "%d:%d" % [ai.profile.team, ai.profile.slot]
		var ps: Array = _pos.get(key, [])
		_pos[key] = ps
		ps.append(s.global_position)
		if ps.size() > 5:
			ps.pop_front()
		if ps.size() < 5:
			continue
		var moved := 0.0
		for q: Vector2 in ps:
			moved = maxf(moved, q.distance_to(ps[0]))
		var fighting := _has_target(ai) and ai.state != "home" and ai.state != "retreat" and not ai.combat.target_far(s)
		var far := s.global_position.distance_to(ai.goal) > 800.0
		var stuck := moved < 150.0 and far and not fighting
		var lane := _is_lane(ai.profile)
		if stuck and not bool(_stuck.get(key, false)):
			_add(ai.profile.team, "stuck_episodes")
			if lane:
				_add(ai.profile.team, "stuck_lane_episodes")
		if stuck:
			_add(ai.profile.team, "stuck_s", POSITION_EVERY)
			if lane:
				_add(ai.profile.team, "stuck_lane_s", POSITION_EVERY)
		_stuck[key] = stuck


## Print the FARMING_PROBE_JSON line (see HOW TO READ THE OUTPUT) and end the run.
func _finish() -> void:
	for pkey: String in _run.keys():
		_close_spell(pkey, int(pkey.get_slice(":", 0)))
	var pilots: Array = []
	for p: PilotProfile in world.profiles:
		if _is_lane(p):
			var own: Dictionary = _own.get("%d:%d" % [p.team, p.slot], {})
			pilots.append({"team": p.team, "slot": p.slot, "role": p.role, "callsign": p.callsign, "lh": p.minion_kills,
					"kills": p.kills, "deaths": p.deaths, "earned": roundi(p.earned), "lane_s": snappedf(float(own.get("lane", 0.0)), 0.1),
					"idle_s": snappedf(float(own.get("idle", 0.0)), 0.1), "parked_s": snappedf(float(own.get("parked", 0.0)), 0.1)})
	var parked: Array = []
	for v in _parked_by_5min:
		parked.append(snappedf(float(v), 0.1))
	print("FARMING_PROBE_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "ended": world.phase != "play", "winner": world.winner,
			"tot": _round_all(_tot), "team": [_round_all(_team[0]), _round_all(_team[1])], "front_enemy": _front_enemy,
			"idle_front_enemy": _idle_front_enemy, "idle_pilot_enemy": _idle_pilot_enemy, "parked_by_5min": parked, "pilots": pilots,
			"station_notes": _station_notes}))
	get_tree().quit()


## A copy of counter dictionary `d` with every number rounded to one decimal.
func _round_all(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d.keys():
		out[k] = snappedf(float(d[k]), 0.1)
	return out
