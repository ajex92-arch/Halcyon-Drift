extends Node
## WHAT THIS IS: a measuring tool for the three Crossing nodes (the ore
## nodes on the centre line, x = 20000). It answers: when does each team
## first get a turret at each Crossing, which Crossing does each admiral
## pick for its first one and why, how long does a turret stand, and what
## stops a team from building there when it wants to?
##
## HOW IT WORKS: once a game second it looks at the three "middle" ore
## nodes. For every turret slot it notes when a live turret first appears
## (the order was paid for and the turret placed), when it finishes building
## (Turret.is_built()) and when it is gone. For each team and node it also
## asks the same question the admiral's build order asks
## (AdmiralCommand.turret_blocker for a PD turret) and counts the seconds
## per answer: free ("" = it could build), "enemy_near" (an enemy ship or
## minion within TurretData.BUILD_CLEAR_RADIUS), "enemy_turret" (the other
## team holds the node), "lock" (a turret died here in the last 60 s),
## "full" or "other". Beside each answer it counts the team's own pilots
## and minions within CROSSING_R of the node (the disc the admiral looks at
## when it picks the Crossing for its first turret). The first time a team
## has a turret at any Crossing it writes "first": the node, the time, and
## for all three Crossings [answer, own ships near] in the sample just before
## the turret was seen and in the sample that saw it. It also notes, per team,
## the first time its number of live turrets at its own inner nodes reached
## 1, 2, ... 9, and the team treasury every 300 s. At the end it prints one
## "CROSSING_JSON {...}" line and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --test=crossing_probe --secs=900 --skill-jitter
##
## WHO USES IT: main.gd loads it for --test=crossing_probe. It only reads the
## game; it changes nothing in the match.

## The radius (world units) around a Crossing within which the team's own
## pilots and minions are counted. The same disc as the one in which an enemy
## ship stops a team from building there (TurretData.BUILD_CLEAR_RADIUS,
## 1,500), and the one the admiral's choice of its first Crossing uses.
const CROSSING_R := 1500.0

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 900.0
## Seconds until the next 1 s sample.
var _sample_t := 0.0
## Per turret (key: its instance id) at a Crossing: node id, team, game time
## it appeared, game time it finished building (-1 = not yet) and game time
## it was gone (-1 = still there).
var _turrets := {}
## Seconds per answer of the build check: key "node_id:team", value a
## Dictionary answer -> seconds.
var _blocked := {}
## Per team (key "0" or "1"): its first turret at any Crossing: "node" (id),
## "t" (game time it was first seen), "before" and "after": for each Crossing
## (node id) [build-check answer, own pilots and minions within CROSSING_R],
## in the sample before the turret was seen and in the one that saw it.
var _first := {}
## The last sample's [answer, own ships near] per "team:node_id".
var _prev := {}
## Per team: the game time at which its live inner-node turrets first
## numbered 1, 2, ... (index 0 = first turret).
var _inner := [[], []]
## The treasuries of both teams every 300 s: a list of [time, team 0, team 1].
var _treasury := []
## The next game time of a treasury note.
var _treasury_t := 300.0
## A reusable list for the spatial hash (see _own_near()).
var _scratch: Array = []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 900.0))


## Every tick: sample once a second, and at the end print the JSON line and
## quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	_sample_t -= dt
	if _sample_t <= 0.0:
		_sample_t = 1.0
		_sample()
	if world.time >= secs or world.phase != "play":
		_finish()


## The 1 s checks (see the top of this file).
func _sample() -> void:
	var live := {}
	var now := {}
	var fresh := []
	for n in world.nodes:
		if n.node_kind == "middle":
			for t in n.slots:
				if t != null and is_instance_valid(t) and t.alive:
					live[t.get_instance_id()] = true
					var rec: Dictionary = _turrets.get(t.get_instance_id(), {})
					if rec.is_empty():
						rec = {"node": n.node_id, "team": t.team, "t": snappedf(world.time, 0.1), "ready": -1.0, "gone": -1.0}
						_turrets[t.get_instance_id()] = rec
						if not _first.has(str(t.team)):
							fresh.append([t.team, n.node_id])
					if float(rec["ready"]) < 0.0 and t.is_built():
						rec["ready"] = snappedf(world.time, 0.1)
			for team in 2:
				var key := "%s:%d" % [n.node_id, team]
				var d: Dictionary = _blocked.get(key, {})
				var answer := _category(world.command.turret_blocker(team, n.node_id, "pd"))
				d[answer] = float(d.get(answer, 0.0)) + 1.0
				_blocked[key] = d
				now["%d:%s" % [team, n.node_id]] = [answer, _own_near(team, n.global_position)]
	for id: int in _turrets:
		var rec: Dictionary = _turrets[id]
		if float(rec["gone"]) < 0.0 and not live.has(id):
			rec["gone"] = snappedf(world.time, 0.1)
	# A team's first turret at a Crossing: where it went, and what the build
	# check and the own ships near each Crossing looked like just before.
	for f: Array in fresh:
		if not _first.has(str(f[0])):
			_first[str(f[0])] = {"node": f[1], "t": snappedf(world.time, 0.1), "before": _picture(_prev, int(f[0])), "after": _picture(now, int(f[0]))}
	_prev = now
	for team in 2:
		var count := 0
		for n in world.nodes:
			if n.node_kind == "inner" and n.side == team:
				count += n.turret_count(team)
		while (_inner[team] as Array).size() < count:
			(_inner[team] as Array).append(snappedf(world.time, 0.1))
	if world.time >= _treasury_t:
		_treasury.append([roundi(world.time), roundi(world.teams[0].treasury), roundi(world.teams[1].treasury)])
		_treasury_t += 300.0


## How many live pilots and minions of `team` are within CROSSING_R of
## point `pos` (the spatial hash may list units a little outside the circle,
## so the distance is checked).
func _own_near(team: int, pos: Vector2) -> int:
	var c := 0
	for u: Unit in world.unit_hash.query(pos, CROSSING_R, _scratch):
		if u.alive and u.team == team and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION) and u.global_position.distance_to(pos) < CROSSING_R:
			c += 1
	return c


## From a sample ("team:node_id" -> [answer, own near]) the entries of `team`
## as node id -> [answer, own near]; empty before the first sample.
func _picture(sample: Dictionary, team: int) -> Dictionary:
	var out := {}
	for n in world.nodes:
		if n.node_kind == "middle" and sample.has("%d:%s" % [team, n.node_id]):
			out[n.node_id] = sample["%d:%s" % [team, n.node_id]]
	return out


## A short word for a build-check answer (the sentence from
## ResourceNode.build_blocker, or "" for "it could build").
func _category(sentence: String) -> String:
	if sentence == "":
		return "free"
	if sentence.begins_with("Enemy ships"):
		return "enemy_near"
	if sentence.begins_with("The enemy has"):
		return "enemy_turret"
	if sentence.begins_with("A turret was just"):
		return "lock"
	if sentence.begins_with("Every turret"):
		return "full"
	return "other"


## Print the result and quit.
func _finish() -> void:
	print("CROSSING_JSON ", JSON.stringify({"time": snappedf(world.time, 1.0), "turrets": _turrets.values(), "blocked": _blocked, "first": _first, "inner": _inner, "treasury": _treasury}))
	get_tree().quit()
