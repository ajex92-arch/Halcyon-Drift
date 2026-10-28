extends Node
## WHAT THIS IS: the turret-repair probe: a measuring tool that stands a
## damaged turret, a damaged repair bay and a damaged fighter beside a
## Logistics Corvette and prints, second by second, what happens to their
## hulls. It also prints the turret's shield. It asserts nothing: its numbers
## are put side by side for two builds of the game.
##
## HOW IT WORKS: a quiet match (no AI pilots, no admirals, no jungle) runs for
## a moment. Then the probe builds a finished PD turret for team 0 on the ore
## node nearest to team 0's mothership, an anchored repair bay and a fighter
## 260 to 300 world units away from the Logistics Corvette it launches,
## and takes each of them down to 40% hull. The corvette sits still and does
## its two jobs the way it does in a match: its two escort repair drones look
## for work (the whole of ShipAbilities.manage_escort_drones() and
## RepairDrone run as in a match), and the probe makes it use Emergency Repair
## twice (ShipAbilities.use_special(), after 6 and after 30 seconds). Every
## second it writes down the hulls and the turret's shield, and every tick it
## counts the seconds a Logistics drone spent with the turret as its target.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=turret_repair_probe
##
## HOW TO READ THE OUTPUT: one "TURRET t <seconds> ..." line per second, then
## one "TURRET_PROBE_JSON {...}" line: the start and end hulls of the turret,
## the repair bay and the fighter, the turret's shield (its size and whether
## it has a shield pool at all), how many seconds a drone had the turret as
## its target, and how many seconds a drone was healing.
##
## WHO USES IT: main.gd loads it for --test=turret_repair_probe. It changes
## only the units it builds itself, and draws no random numbers of its own.

## Seconds the scenario runs after it is built.
const RUN_SECS := 40.0
## The match times (seconds after the build) of the two Emergency Repairs.
const EMERGENCY_AT := [6.0, 30.0]
## The hull fraction every unit starts the scenario at.
const START_FRAC := 0.4
## The match time (seconds) at which the scenario is built.
const BUILD_AT := 1.0

## The running match (set by setup()).
var world: World
## The finished PD turret the scenario watches.
var turret: Turret
## The anchored repair bay beside it.
var bay: RepairBay
## The damaged fighter beside it.
var fighter: Ship
## The Logistics Corvette that sends drones and uses Emergency Repair.
var logi: Ship
## The match time (seconds) the scenario was built; -1 until then.
var _t0 := -1.0
## Seconds since the last printed line.
var _t_print := 0.0
## How many of the two Emergency Repairs have been used.
var _used := 0
## Seconds a Logistics drone had the turret as its target.
var _drone_on_turret_s := 0.0
## Seconds a Logistics drone was healing something.
var _healing_s := 0.0
## The start values, written down when the scenario is built.
var _start := {}
## One row per printed second.
var _rows: Array = []


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w


## Every tick: build the scenario when it is time, then watch it.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	if _t0 < 0.0:
		if world.time >= BUILD_AT:
			_build()
		return
	var t := world.time - _t0
	# The two Emergency Repairs.
	if _used < EMERGENCY_AT.size() and t >= float(EMERGENCY_AT[_used]) and is_instance_valid(logi) and logi.alive:
		ShipAbilities.use_special(logi)
		_used += 1
	# Seconds a Logistics drone spent on the turret or healing.
	var on_turret := false
	var healing := false
	for d: RepairDrone in world.repair_drones:
		if d.alive and d.mode == RepairDrone.MODE_LOGISTICS:
			if d.target == turret and is_instance_valid(turret):
				on_turret = true
			if d.healing:
				healing = true
	if on_turret:
		_drone_on_turret_s += dt
	if healing:
		_healing_s += dt
	# One line a second.
	_t_print += dt
	if _t_print >= 1.0:
		_t_print -= 1.0
		var row := _state()
		row["t"] = snappedf(t, 0.1)
		_rows.append(row)
		print("TURRET t %.1f turret_hull %.1f turret_shield %.1f bay_hull %.1f fighter_hull %.1f" % [t, row["turret_hull"], row["turret_shield"], row["bay_hull"], row["fighter_hull"]])
	if t >= RUN_SECS:
		_finish()


## The hulls and the turret's shield now.
func _state() -> Dictionary:
	return {"turret_hull": snappedf(turret.hull, 0.01), "turret_shield": snappedf(turret.shield_total(), 0.01),
		"bay_hull": snappedf(bay.hull, 0.01), "fighter_hull": snappedf(fighter.hull, 0.01)}


## Build the scenario (see HOW IT WORKS).
func _build() -> void:
	_t0 = world.time
	var ms := world.mothership(0)
	# The ore node nearest to team 0's mothership that has a free turret spot.
	var node: ResourceNode = null
	var slot := -1
	var best := INF
	for n: ResourceNode in world.nodes:
		for i in n.slots.size():
			if n.slots[i] == null and ms.global_position.distance_to(n.global_position) < best:
				best = ms.global_position.distance_to(n.global_position)
				node = n
				slot = i
	turret = world.spawn_turret(0, node, slot, "pd", true)
	var home := turret.global_position
	logi = _launch("logistics", home + Vector2(0.0, 260.0))
	fighter = _launch("fighter", home + Vector2(300.0, 0.0))
	bay = world.spawn_bay(0, home + Vector2(-260.0, 0.0))
	bay.state = "anchored"
	bay.velocity = Vector2.ZERO
	bay.global_position = home + Vector2(-260.0, 0.0)
	# Take every damaged unit down to the start fraction.
	turret.hull = turret.hull_max * START_FRAC
	bay.hull = bay.hull_max * START_FRAC
	fighter.hull = fighter.hull_max * START_FRAC
	_start = _state()
	_start["turret_hull_max"] = turret.hull_max
	_start["turret_has_shield_pool"] = turret.shields != null
	_start["turret_shield_max"] = turret.shields.max_total if turret.shields != null else 0.0


## Launch a pilot ship of hull `hid` for team 0 and put it at `at`, not
## flying (no driver).
func _launch(hid: String, at: Vector2) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 0, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.global_position = at
	s.velocity = Vector2.ZERO
	return s


## Print the summary line and end the run.
func _finish() -> void:
	var end := _state()
	print("TURRET_PROBE_JSON ", JSON.stringify({"probe": "turret_repair_probe", "start": _start, "end": end,
		"drone_on_turret_s": snappedf(_drone_on_turret_s, 0.01), "drone_healing_s": snappedf(_healing_s, 0.01),
		"emergency_used": _used, "rows": _rows}))
	get_tree().quit()
