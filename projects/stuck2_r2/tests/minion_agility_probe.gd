extends Node
## WHAT THIS IS: the agility probe: a measuring tool that prints how nimble
## the three lane-minion types are. For each type it measures four things:
## how long it takes to go from standstill to top speed, how long to turn
## right round (fly at top speed one way, then be told to fly at top speed the
## other way), how wide the tightest circle is that it can hold at top speed,
## and how long its nose takes to swing half a turn. It asserts nothing: its
## numbers are put side by side for two builds of the game.
##
## HOW IT WORKS: it freezes the match, makes one minion of each type and
## drives the real flight functions (MinionFlight.combat_move,
## MinionFlight.lane_move and MinionFlight.face) step after step, with the
## same step length a minion really steers with (two ticks, 1/30 s). Nothing
## is copied from the flight code: whatever the functions do to the velocity
## is what gets measured. Two ways of flying are measured:
##   - "combat": combat_move() with a target far away in the wanted direction.
##     Every type then wants its own top speed straight at the target.
##   - "lane": lane_move() with a "move" order to a spot far away in the
##     wanted direction. A minion walking the lane never goes faster than
##     Minions.FORMATION_SPEED, so its top speed here is the smaller of that
##     and its own.
## Each measure is defined once, in its own function:
##   to_speed_s    seconds from standstill until the speed reaches the top
##                 speed (worked out inside the last step, so a step of 1/30 s
##                 does not round it).
##   reverse_s     seconds from flying at top speed one way until the velocity
##                 is the top speed the other way (same inside-the-step
##                 working-out).
##   bend_radius   the tightest circle (world units) the minion can fly at top
##                 speed: the largest angle by which the wanted velocity can
##                 be turned in ONE step while the minion still follows it to
##                 the full top speed (found by halving the interval), turned
##                 into a circle: an arc of top speed x step length per step
##                 and that angle per step.
##   nose180_s     seconds for face() to swing the nose half a turn.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=minion_agility_probe
##
## HOW TO READ THE OUTPUT: one "AGILITY <way> <type> ..." line per type and
## way, then one "AGILITY_PROBE_JSON {...}" line with the same numbers.
##
## WHO USES IT: main.gd loads it for --test=minion_agility_probe. It only
## reads the game and draws no random numbers (the minions it makes are
## launched into a frozen match that is thrown away).

## The three minion types, in the order the table lists them.
const TYPES := ["fighter", "bomber", "corvette"]
## The two ways of flying that are measured.
const WAYS := ["combat", "lane"]
## The length (seconds) of one steering step: a minion steers on every second
## tick of 1/60 s.
const DT := 2.0 / 60.0
## How far away (world units) the target or the ordered spot is put in the
## wanted direction, so every type wants its full top speed.
const FAR := 6000.0
## The most steps a measure may take before it gives up (20 seconds).
const MAX_STEPS := 600
## How close (world units per second) the velocity must get to the wanted one
## to count as "reached".
const EPS := 0.001

## The running match (set by setup()).
var world: World
## Where the minions are made and measured: open ground between the lanes.
var _home := Vector2.ZERO


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	_home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	world.set_physics_process(false)
	_run.call_deferred()


## Measure every type in both ways, print the table and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	var out := {}
	for way: String in WAYS:
		for type_id: String in TYPES:
			var m := world.spawn_minion(1, type_id, "mid", _home)
			var row := {
				"speed": m.speed, "accel": m.accel, "turn": m.turn, "top": _top(m, way),
				"to_speed_s": _to_speed_s(m, way), "reverse_s": _reverse_s(m, way),
				"bend_radius": _bend_radius(m, way), "nose180_s": _nose180_s(m),
			}
			out["%s:%s" % [way, type_id]] = row
			print("AGILITY %s %s speed %s accel %s turn %s top %s to_speed_s %.4f reverse_s %.4f bend_radius %.3f nose180_s %.4f" % [
				way, type_id, row["speed"], row["accel"], row["turn"], row["top"], row["to_speed_s"], row["reverse_s"],
				row["bend_radius"], row["nose180_s"]])
			m.alive = false
	print("AGILITY_PROBE_JSON ", JSON.stringify({"probe": "minion_agility_probe", "dt": DT, "rows": out}))
	get_tree().quit()


## The top speed (world units per second) the way `way` aims for: the
## minion's own in combat, the lane pace in the lane.
func _top(m: Minion, way: String) -> float:
	return m.speed if way == "combat" else minf(m.speed, Minions.FORMATION_SPEED)


## Put minion `m` back to its start: at home, not moving, nose to the right.
func _reset(m: Minion) -> void:
	m.position = _home
	m.velocity = Vector2.ZERO
	m.rotation = 0.0
	m._rock_push = Vector2.ZERO


## One steering step of minion `m` in the way `way` toward direction `dir`
## (a length-1 arrow): call the real flight function, then move the minion by
## its velocity as Minion.sim_update() does.
func _drive(m: Minion, way: String, dir: Vector2) -> void:
	if way == "combat":
		var tp := m.position + dir * FAR
		m.aim_pt = tp
		MinionFlight.combat_move(m, tp, m.position.distance_to(tp), m.mounts[0].reach, DT)
	else:
		m.order = {"type": "move", "pos": m.position + dir * FAR}
		MinionFlight.lane_move(m, DT)
	m.position += m.velocity * DT


## Seconds from standstill until the speed reaches the top speed, flying
## straight to the right; -1 if it never does. The step that arrives is
## usually cut short (the velocity stops at the wanted one), so its share of
## a step is worked out from the step before it, which was a full one.
func _to_speed_s(m: Minion, way: String) -> float:
	_reset(m)
	var top := _top(m, way)
	var last_gain := 0.0
	for i in MAX_STEPS:
		var before := m.velocity.length()
		_drive(m, way, Vector2.RIGHT)
		var after := m.velocity.length()
		if after >= top - EPS:
			var full := last_gain if last_gain > 0.0 else after - before
			var frac := clampf((top - before) / full, 0.0, 1.0) if full > 0.0 else 1.0
			return (float(i) + frac) * DT
		last_gain = after - before
	return -1.0


## Seconds from flying at top speed to the right until the velocity is the top
## speed to the left, told to fly left from the first step; -1 if it never is.
## The arriving step is cut short, so its share of a step is worked out from the
## step before it, as in _to_speed_s().
func _reverse_s(m: Minion, way: String) -> float:
	_reset(m)
	var top := _top(m, way)
	m.velocity = Vector2.RIGHT * top
	var last_drop := 0.0
	for i in MAX_STEPS:
		var before := m.velocity.x
		_drive(m, way, Vector2.LEFT)
		var after := m.velocity.x
		if after <= -top + EPS:
			var full := last_drop if last_drop > 0.0 else before - after
			var frac := clampf((before + top) / full, 0.0, 1.0) if full > 0.0 else 1.0
			return (float(i) + frac) * DT
		last_drop = before - after
	return -1.0


## Does minion `m`, flying at top speed to the right, follow a wanted velocity
## of the same size turned by `phi` radians (to the full top speed) in one
## step?
func _follows_turn(m: Minion, way: String, phi: float) -> bool:
	_reset(m)
	var top := _top(m, way)
	m.velocity = Vector2.RIGHT * top
	var dir := Vector2.RIGHT.rotated(phi)
	_drive(m, way, dir)
	return m.velocity.distance_to(dir * top) < EPS


## The radius (world units) of the tightest circle minion `m` can hold at top
## speed: halve the interval of turn angles per step until the largest one it
## still follows is found, then fit a circle to it (an arc of top speed x DT
## per step, turning by that angle per step). 0 if it follows no turn.
func _bend_radius(m: Minion, way: String) -> float:
	var lo := 0.0
	var hi := PI * 0.5
	for _i in 48:
		var mid := (lo + hi) * 0.5
		if _follows_turn(m, way, mid):
			lo = mid
		else:
			hi = mid
	if lo <= 0.0:
		return 0.0
	return _top(m, way) * DT / (2.0 * sin(lo * 0.5))


## Seconds for face() to swing the nose of minion `m` half a turn (from
## pointing right to pointing left).
func _nose180_s(m: Minion) -> float:
	_reset(m)
	for i in MAX_STEPS:
		var before := absf(Util.ang_diff(m.rotation, PI))
		MinionFlight.face(m, PI, DT)
		var after := absf(Util.ang_diff(m.rotation, PI))
		if after < 1e-6:
			var frac := clampf(before / (m.turn * DT), 0.0, 1.0)
			return (float(i) + frac) * DT
	return -1.0
