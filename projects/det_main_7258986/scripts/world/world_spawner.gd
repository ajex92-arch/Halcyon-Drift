class_name WorldSpawner
extends RefCounted
## WHAT THIS IS: the factory for new units. Every new pilot ship, minion,
## drone, turret, repair bay, ward, derelict and snub fighter in the match
## is made here.
##
## HOW IT WORKS: each spawn function makes the unit's node from its scene
## file, then follows WorldRegistry's recipe: attach() (id, world link,
## into the scene tree), the unit's own setup(), then index() (into the
## unit lists). It hands back the new unit.
##
## WHO USES IT: World makes one (World.spawner), and World's spawn_*
## functions forward here. The callers are: MinionDirector (minions),
## TeamState and WorldSetup (mining drones), Ship and RepairBay (repair
## drones), AdmiralCommand (turrets, repair bays and wards), JungleDirector
## (derelicts), Derelict (snub fighters) and WorldHangar.launch() (pilot
## ships). Some tests spawn turrets too.

## The pilot ship scene.
const SHIP_SCENE := preload("res://scenes/entities/ship.tscn")
## The lane minion scene.
const MINION_SCENE := preload("res://scenes/entities/minion.tscn")
## The turret scene.
const TURRET_SCENE := preload("res://scenes/entities/turret.tscn")
## The repair bay scene.
const BAY_SCENE := preload("res://scenes/entities/repair_bay.tscn")
## The repair drone scene.
const REPAIR_DRONE_SCENE := preload("res://scenes/entities/repair_drone.tscn")
## The mining drone scene.
const MINING_DRONE_SCENE := preload("res://scenes/entities/mining_drone.tscn")
## The ward scene.
const WARD_SCENE := preload("res://scenes/entities/ward.tscn")
## The derelict (jungle monster) scene.
const DERELICT_SCENE := preload("res://scenes/entities/derelict.tscn")
## The snub fighter scene.
const SNUB_SCENE := preload("res://scenes/entities/snub_fighter.tscn")

## The world the new units go into.
var world: World


## Remember the world. World makes this part once.
func _init(w: World) -> void:
	world = w


## Make pilot `p`'s ship in their chosen hull and modules, at `pos`,
## pointing at angle `facing` (radians). WorldHangar.launch() picks the
## spot and then gives the ship its driver.
func spawn_pilot_ship(p: PilotProfile, pos: Vector2, facing: float) -> Ship:
	var s: Ship = SHIP_SCENE.instantiate()
	world.registry.attach(s)
	s.setup(world, p, p.hull_id, p.modules, pos, facing)
	world.registry.index(s)
	return s


## Make a minion of type `type_id` ("fighter", "bomber", "corvette") for
## `team` on lane `lane`, at point `at`. Its strength multiplier grows with
## match time (Minions.scaling: +7% per full 5 minutes) and with the team's
## minion research bonus (TeamState.minion_buff).
func spawn_minion(team: int, type_id: String, lane: String, at: Vector2) -> Minion:
	var m: Minion = MINION_SCENE.instantiate()
	world.registry.attach(m)
	m.setup(world, team, type_id, lane, at, Minions.scaling(world.time) * (1.0 + world.teams[team].minion_buff))
	world.registry.index(m)
	return m


## Make a mining drone for `team`. It appears in a random direction from
## the mothership's centre, half of the ship's half-length away (one
## random number). `assign` is the ore node id to mine, or "" to let the
## drone pick (World.best_node_for_drone).
func spawn_mining_drone(team: int, assign: String) -> MiningDrone:
	var ms := world.mothership(team)
	var at := ms.global_position + Vector2.from_angle(randf() * TAU) * (ms.half_len * 0.5)
	var d: MiningDrone = MINING_DRONE_SCENE.instantiate()
	world.registry.attach(d)
	d.setup(world, team, at, assign)
	world.registry.index(d)
	return d


## Make a repair drone for `team` at `at`, working for `owner` (a repair
## bay or a ship). `mode` is its job: RepairDrone.MODE_BAY, MODE_KIT or
## MODE_LOGISTICS.
func spawn_repair_drone(owner: Unit, team: int, at: Vector2, mode: int) -> RepairDrone:
	var d: RepairDrone = REPAIR_DRONE_SCENE.instantiate()
	world.registry.attach(d)
	d.setup(world, owner, team, at, mode)
	world.registry.index(d)
	return d


## Build a turret of type `ttype` for `team` on slot `slot` of ore node
## `n`. Normally it starts at 30% hull and builds up over time;
## `instant` = finished at once with full hull (see Turret.setup).
func spawn_turret(team: int, n: ResourceNode, slot: int, ttype: String, instant: bool = false) -> Turret:
	var t: Turret = TURRET_SCENE.instantiate()
	world.registry.attach(t)
	t.setup(world, team, n, slot, ttype, instant)
	world.registry.index(t)
	return t


## Launch a repair bay for `team`. It starts at the mothership's launch
## point 2 and flies to `target`, where it anchors.
func spawn_bay(team: int, target: Vector2) -> RepairBay:
	var ms := world.mothership(team)
	var b: RepairBay = BAY_SCENE.instantiate()
	world.registry.attach(b)
	b.setup(world, team, ms.launch_point(2), target)
	world.registry.index(b)
	return b


## Launch a ward for `team`. It starts at the mothership's launch point 1
## and flies to `target`.
func spawn_ward(team: int, target: Vector2) -> Ward:
	var ms := world.mothership(team)
	var w: Ward = WARD_SCENE.instantiate()
	world.registry.attach(w)
	w.setup(world, team, ms.launch_point(1), target)
	world.registry.index(w)
	return w


## Make the derelict of jungle camp `camp_id` (type `type_id`, a key of
## Jungle.CAMPS) at `at`.
func spawn_derelict(camp_id: String, type_id: String, at: Vector2) -> Derelict:
	var d: Derelict = DERELICT_SCENE.instantiate()
	world.registry.attach(d)
	d.setup(world, camp_id, type_id, at)
	world.registry.index(d)
	return d


## Make a snub fighter that belongs to derelict carrier `carrier`.
func spawn_snub(carrier: Derelict) -> SnubFighter:
	var s: SnubFighter = SNUB_SCENE.instantiate()
	world.registry.attach(s)
	s.setup(world, carrier)
	world.registry.index(s)
	return s
