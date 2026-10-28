extends Node
## WHAT THIS IS: the "lane probe": a small measuring tool for the minion
## waves of an AI-vs-AI match (added for T-07, the smaller waves). It answers four plain questions: how many minions are
## alive on each lane, how far down the lane each team's wave gets, which
## turrets are lost where and when, and how many credits the pilots earn
## from minion last hits.
##
## HOW IT WORKS: it listens for four events (a free-wave minion launched, a
## unit killed, credits earned, a turret destroyed) and, every SAMPLE_EVERY
## (10) game seconds, looks at every lane of both teams: the number of live
## minions and the front of the wave (the live minion furthest down the lane,
## as a fraction of the lane's length counted from its own team's end: 0.0 =
## its own mothership, 1.0 = the enemy's). At the end (--secs, or when a
## mothership dies) it prints one "LANE_JSON {...}" line and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --skill-jitter --test=lane_probe --secs=1200
## --secs is how many game seconds to watch (default 1200). Use the same
## options as a fun_probe run and the match is the same match. With --late
## the match starts at 25:00 with both sides fully teched (LateGame.apply, as
## in fun_probe --late; Escort Wing is then researched, so every lane's wave
## has one more Patrol Leader) and --secs counts from 25:00.
##
## HOW TO READ THE OUTPUT: LANE_JSON holds
##   "launched"   per "team:lane" ("0:top" = Aurelian's top lane, team 0 or 1,
##                lane top, mid or bot): how many free-wave minions of each
##                type left the mothership (shows the wave makeup);
##   "alive"      per "team:lane": the live minions at each sample (one number
##                per SAMPLE_EVERY seconds, the first at 0 s);
##   "front"      per "team:lane": the wave front at each sample (-1 = none out);
##   "turrets"    one [time, team that lost it, lane, node kind, team that
##                killed it] per turret destroyed;
##   "hits"       last hits by pilots on enemy minions: per minion type, and per
##                victim "team:lane"; "other_kills" = minions killed by anything
##                else (a turret, another minion, the mothership);
##   "pilots"     one row per pilot: team, slot, role, callsign, last hits,
##                credits from last hits ("lh_credits"), all credits earned.
##
## WHO USES IT: main.gd loads it for --test=lane_probe. It only reads the
## game and draws no random numbers, so the match plays exactly as without
## it. A small script outside the game turns the LANE_JSON lines of two builds
## into the before/after tables.

## Seconds of game time between two samples of the lanes.
const SAMPLE_EVERY := 10.0

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 1200.0
## Game time of the next sample.
var _next_sample := 0.0
## Per "team:lane": the live minions at each sample.
var _alive := {}
## Per "team:lane": the wave front (0..1) at each sample, -1 with no minion out.
var _front := {}
## Per "team:lane": how many minions of each type launched.
var _launched := {}
## One entry per destroyed turret: [time, team that lost it, lane, node kind, killer team].
var _turrets: Array = []
## Last hits by pilots, per victim type: type id -> count.
var _hits_type := {}
## Last hits by pilots, per victim "team:lane": count.
var _hits_lane := {}
## Minions killed by something that is not a pilot.
var _other_kills := 0
## Credits earned from minion last hits, per pilot key "team:slot".
var _lh_credits := {}


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1200.0))
	# --late: the late-game setup (tests/lib/late_game.gd); --secs then counts
	# from 25:00.
	if Game.opt("late", false):
		LateGame.apply(world, Game.opt("symmetric") != null)
		secs += LateGame.START
	_next_sample = world.time
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			var key := "%d:%s" % [team, lane]
			_alive[key] = []
			_front[key] = []
			_launched[key] = {}
			_hits_lane[key] = 0
	Events.minion_launched.connect(_on_launched)
	Events.unit_killed.connect(_on_killed)
	Events.credits_earned.connect(_on_credits)
	Events.turret_destroyed.connect(_on_turret)


## A free-wave minion launched: count it by team, lane and type.
func _on_launched(node: Node, _wave_id: float) -> void:
	var m := node as Minion
	if m == null:
		return
	var d: Dictionary = _launched["%d:%s" % [m.team, m.lane]]
	d[m.mtype] = int(d.get(m.mtype, 0)) + 1


## Something died: when it is a minion, count who finished it off.
func _on_killed(u: Node, info: RefCounted) -> void:
	var m := u as Minion
	var d := info as DamageInfo
	if m == null or d == null:
		return
	if d.source_profile != null and (d.source_profile as PilotProfile).team != m.team:
		_hits_type[m.mtype] = int(_hits_type.get(m.mtype, 0)) + 1
		_hits_lane["%d:%s" % [m.team, m.lane]] = int(_hits_lane["%d:%s" % [m.team, m.lane]]) + 1
	else:
		_other_kills += 1


## A pilot earned credits: keep the ones paid for minion last hits.
func _on_credits(profile: RefCounted, amount: float, reason: String) -> void:
	if reason != "minion":
		return
	var p := profile as PilotProfile
	if p == null:
		return
	var key := "%d:%d" % [p.team, p.slot]
	_lh_credits[key] = float(_lh_credits.get(key, 0.0)) + amount


## A turret was destroyed: write down where, when and by whom.
func _on_turret(turret: Node, by_team: int) -> void:
	var t := turret as Turret
	if t == null:
		return
	var lane := "?"
	var kind := "?"
	if t.node != null:
		lane = t.node.lane
		kind = t.node.node_kind
	_turrets.append([snappedf(world.time, 1.0), t.team, lane, kind, by_team])


## How far down `lane` the front of `team`'s wave is, as a fraction of the
## lane's length from its own end (-1.0 with no live minion on the lane).
func _front_of(team: int, lane: String) -> float:
	var pts := MapLayout.lane_points(lane, team)
	var length := Util.polyline_length(pts)
	var best := -1.0
	for m: Minion in world.minions:
		if m.team == team and m.alive and m.lane == lane:
			best = maxf(best, float(Util.project_on_polyline(m.global_position, pts)["s"]) / length)
	return best


## Every tick: take a sample when it is due, and at the end print the JSON
## line and quit.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time >= _next_sample:
		_next_sample += SAMPLE_EVERY
		_sample()
	if world.time >= secs or world.phase != "play":
		_finish()


## One sample: the live minions and the wave front of every team and lane.
func _sample() -> void:
	for team in 2:
		for lane: String in MapLayout.LANE_ORDER:
			var n := 0
			for m: Minion in world.minions:
				if m.team == team and m.alive and m.lane == lane:
					n += 1
			var key := "%d:%s" % [team, lane]
			(_alive[key] as Array).append(n)
			(_front[key] as Array).append(snappedf(_front_of(team, lane), 0.001))


## Print the LANE_JSON line (see HOW TO READ THE OUTPUT) and end the run.
func _finish() -> void:
	var pilots: Array = []
	for p: PilotProfile in world.profiles:
		pilots.append({"team": p.team, "slot": p.slot, "role": p.role, "callsign": p.callsign, "lh": p.minion_kills,
				"lh_credits": roundi(float(_lh_credits.get("%d:%d" % [p.team, p.slot], 0.0))), "earned": roundi(p.earned)})
	print("LANE_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "every": SAMPLE_EVERY, "launched": _launched, "alive": _alive,
			"front": _front, "turrets": _turrets, "hits": {"by_type": _hits_type, "by_lane": _hits_lane, "other_kills": _other_kills}, "pilots": pilots}))
	get_tree().quit()
