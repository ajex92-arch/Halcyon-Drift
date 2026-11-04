extends Node
## WHAT THIS IS: the hit-size probe: a measuring tool that prints, for every
## pilot hull and every minion type, how big the target really is for each
## kind of thing that can touch it. It asserts nothing: its numbers are put
## side by side for two builds of the game.
##
## HOW IT WORKS: it freezes the match, makes one unit of each kind and asks
## the real game code, again and again, "does this touch it?", moving the
## shot a little further off each time until the answer flips (halving the
## interval, 40 times). The answer is the largest distance from the unit's
## centre at which the thing still touches. Four ways are measured:
##   round_edge   a plain round (not flak) flying past the unit: the largest
##                distance from its centre to the round's path, less the
##                round's own radius, at which ProjectilesHitScan.scan() still
##                finds it.
##   beam_edge    a beam flying past: the largest distance from the centre to
##                the beam's line, less the 2 world units of width the beam
##                code adds, at which Combat.beam() still hurts it.
##   blast_edge   a blast going off beside it: the largest distance from the
##                centre to the blast's middle, less the blast's radius, at
##                which Combat.area() still hurts it.
##   push_min_d   (pilot ships only) the distance between the centres of two
##                ships of the hull below which WorldSeparation.separate()
##                shoves them apart. Half of it is the body's size.
## It also prints the unit's `radius`, the radius of its physics circle (the
## one that bumps into rocks and walls) and, in builds that have it, what
## Unit.hit_radius() says.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hit_size_probe
##
## HOW TO READ THE OUTPUT: one "HIT <unit> ..." line per unit, then one
## "HIT_PROBE_JSON {...}" line with the same numbers.
##
## WHO USES IT: main.gd loads it for --test=hit_size_probe. It reads the game
## and hurts only units of a frozen match that is thrown away; it draws no
## random numbers.

## The minion types measured (the pilot hulls are every hull of Ships.ORDER).
const MINION_TYPES := ["fighter", "bomber", "corvette"]
## The radius (world units) of the rounds asked about.
const ROUND_RADIUS := 3.0
## The width (world units) the beam code adds to a unit's circle.
const BEAM_PAD := 2.0
## The radius (world units) of the blast asked about.
const BLAST_RADIUS := 100.0
## The damage of each probing shot: tiny, so no unit ever dies of it.
const DAMAGE := 0.01
## The shortest and the longest line (world units) a round flies in one tick.
const TICK_LINE := 16.0
## How many times the interval is halved.
const HALVINGS := 40
## A time (seconds) older than any real hit, to tell "not hit" from "hit".
const NEVER := -999.0

## The running match (set by setup()).
var world: World
## The unit that fires the probing shots (team 0's mothership).
var _src: Unit
## Where the measured unit stands: open ground between the lanes.
var _home := Vector2.ZERO
## A far corner where finished units are put away.
var _away := Vector2(-5000.0, -5000.0)
## How many units have been put away, so each gets its own far spot.
var _put_away := 0


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	_run.call_deferred()


## Measure every unit, print the table and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_src = world.mothership(0)
	var out := {}
	for hid: String in Ships.ORDER:
		var a := _launch(hid, 1)
		var b := _launch(hid, 0)
		out["ship:" + hid] = _measure("ship:" + hid, a, b)
		_put(a)
		_put(b)
	for type_id: String in MINION_TYPES:
		var m := world.spawn_minion(1, type_id, "mid", _home)
		out["minion:" + type_id] = _measure("minion:" + type_id, m, null)
		_put(m)
	print("HIT_PROBE_JSON ", JSON.stringify({"probe": "hit_size_probe", "round_radius": ROUND_RADIUS, "rows": out}))
	get_tree().quit()


## Measure unit `u` (team 1, called `label` in the printout) standing at home;
## `partner` is a second ship of the same hull (team 0) for the push test, or
## null for a minion. Prints the line and returns the numbers.
func _measure(label: String, u: Unit, partner: Ship) -> Dictionary:
	_place(u, _home)
	var row := {"kind": u.kind, "size": u.size_class, "radius": u.radius, "shape": _shape_radius(u),
		"hit_radius": u.call("hit_radius") if u.has_method("hit_radius") else null}
	row["round_edge"] = _edge(u, "round")
	row["beam_edge"] = _edge(u, "beam")
	row["blast_edge"] = _edge(u, "blast")
	row["push_min_d"] = _push_min_d(u as Ship, partner) if partner != null else null
	print("HIT %s kind %d size %d radius %s shape %s hit_radius %s round_edge %.3f beam_edge %.3f blast_edge %.3f push_min_d %s" % [
		label, row["kind"], row["size"], row["radius"], row["shape"], row["hit_radius"],
		row["round_edge"], row["beam_edge"], row["blast_edge"], row["push_min_d"]])
	return row


## Launch a pilot ship of hull `hid` for team `team` (a pilot named after the
## hull), standing still.
func _launch(hid: String, team: int) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), team, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s


## Stand unit `u` at `at`, not moving, and tell the spatial hashes.
func _place(u: Unit, at: Vector2) -> void:
	u.global_position = at
	u.velocity = Vector2.ZERO
	world.registry.rebuild_hashes()


## Put unit `u` away in its own far corner, out of everything's way, and
## make it dead so nothing looks at it again.
func _put(u: Unit) -> void:
	_put_away += 1
	u.global_position = _away - Vector2(float(_put_away) * 400.0, 0.0)
	u.alive = false
	world.registry.rebuild_hashes()


## The radius of unit `u`'s physics circle (the one that bumps into rocks and
## walls), or -1 if it has none.
func _shape_radius(u: Unit) -> float:
	var cs := u.get_node_or_null("Shape") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		return (cs.shape as CircleShape2D).radius
	return -1.0


## Does thing `way` ("round", "beam" or "blast"), `off` world units from the
## centre of unit `u` (which stands at home), touch it? `off` is measured
## from the centre to the path of the round or beam, or to the middle of the
## blast.
func _touches(u: Unit, way: String, off: float) -> bool:
	u.last_damage_time = NEVER
	u.hull = u.hull_max
	match way:
		"round":
			# A round's one-tick line passing the centre at distance `off`.
			var a := _home + Vector2(-TICK_LINE * 0.5, off)
			var b := _home + Vector2(TICK_LINE * 0.5, off)
			world.projectiles.hit_scan.scan(a, b, ROUND_RADIUS, 0.0, Rules.W_BOLT, 0, 2.0)
			return world.projectiles.hit_scan.hit_unit == u
		"beam":
			# A beam passing the centre at distance `off`.
			world.combat.beam(_src, _home + Vector2(-200.0, off), Vector2.RIGHT, 400.0, DAMAGE, Rules.W_LANCE, false)
			return u.last_damage_time > NEVER
		_:
			# A blast whose middle is `off` away from the centre.
			var at := _home + Vector2(off, 0.0)
			world.combat.area(DamageInfo.from_unit(_src, DAMAGE, Rules.W_FLAK, at), at, BLAST_RADIUS, 0)
			return u.last_damage_time > NEVER


## The largest `off` at which `way` still touches unit `u`, less what the
## shot itself adds (the round's radius, the beam's width, the blast's
## radius): the size of the target as that way sees it, to a hundredth (the
## positions are 32-bit numbers, so a finer answer would be noise).
func _edge(u: Unit, way: String) -> float:
	var lo := 0.0
	var hi := 4.0 * u.radius + BLAST_RADIUS + 20.0
	for _i in HALVINGS:
		var mid := (lo + hi) * 0.5
		if _touches(u, way, mid):
			lo = mid
		else:
			hi = mid
	match way:
		"round":
			return snappedf(lo - ROUND_RADIUS, 0.01)
		"beam":
			return snappedf(lo - BEAM_PAD, 0.01)
		_:
			return snappedf(lo - BLAST_RADIUS, 0.01)


## The distance between the centres of ships `a` (team 1) and `b` (team 0),
## standing still, below which WorldSeparation.separate() moves them.
func _push_min_d(a: Ship, b: Ship) -> float:
	var lo := 0.0
	var hi := 4.0 * (a.radius + b.radius) + 40.0
	for _i in HALVINGS:
		var mid := (lo + hi) * 0.5
		a.global_position = _home
		b.global_position = _home + Vector2(mid, 0.0)
		a.velocity = Vector2.ZERO
		b.velocity = Vector2.ZERO
		world.registry.rebuild_hashes()
		world.separation.separate(1.0 / 60.0)
		# Moved apart? Then they overlapped at this distance.
		var pushed := a.global_position.distance_to(_home) > 1e-6 or b.global_position.distance_to(_home + Vector2(mid, 0.0)) > 1e-6
		if pushed:
			lo = mid
		else:
			hi = mid
	a.global_position = _home
	b.global_position = _away
	world.registry.rebuild_hashes()
	return snappedf(lo, 0.01)
