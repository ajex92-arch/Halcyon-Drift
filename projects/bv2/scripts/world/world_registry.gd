class_name WorldRegistry
extends RefCounted
## WHAT THIS IS: the World's address book of units. It hands out id
## numbers, keeps the unit lists sorted by kind (ships, minions, turrets,
## ...), and files every unit into the spatial hashes once a tick.
##
## HOW IT WORKS: making a unit always goes the same four steps:
##   1. make the unit's node from its scene file ("instantiate"),
##   2. attach(): give it an id and the world link, and add it to the scene
##      tree (only then does its global_position work),
##   3. the unit's own setup() (this decides its kind),
##   4. index(): put it in World.units and in the list for its kind.
## When a unit dies, remove() takes it out of the lists again. Once a tick,
## rebuild_hashes() files every live unit into the spatial hashes (a
## spatial hash is a grid over the map; each unit is filed under the grid
## square it sits in, so "who is near here?" is quick to answer).
##
## WHO USES IT: World makes one (World.registry). WorldSpawner and
## WorldSetup call attach() and index(); World.next_uid() and
## World.remove_unit() forward here (Combat calls remove_unit() for every
## death); World's tick calls rebuild_hashes(). The lists themselves stay
## on World (World.units, World.ships, ...) because many files read them.

## The world whose lists we keep.
var world: World
## The last id number handed out (0 = none yet).
var last_uid := 0


## Remember the world. World makes this part once.
func _init(w: World) -> void:
	world = w


## A new, unique id number for a unit: 1, 2, 3, ...
func next_uid() -> int:
	last_uid += 1
	return last_uid


## Step 2 of making a unit: give it an id and the world link, and put it
## into the scene tree under World.units_root.
func attach(u: Unit) -> void:
	u.uid = next_uid()
	u.world = world
	world.units_root.add_child(u)


## Step 4 of making a unit: add it to World.units and to its kind's list.
func index(u: Unit) -> void:
	world.units.append(u)
	# Start hidden if the viewer can't see it. The visibility pass only
	# reaches each team every 0.2 s, and a fresh enemy unit must not pop
	# out of the fog in the meantime.
	if world.viewer_team >= 0 and u.team != world.viewer_team and world.vision != null:
		if not world.vision.is_visible(world.viewer_team, u.global_position):
			u.visible = false
	# The list for its kind. (Motherships have none here: WorldSetup puts
	# them in World.motherships. Derelicts are the K_MONSTER kind.)
	match u.kind:
		Unit.K_SHIP:
			world.ships.append(u)
		Unit.K_MINION:
			world.minions.append(u)
		Unit.K_TURRET:
			world.turrets.append(u)
		Unit.K_BAY:
			world.bays.append(u)
		Unit.K_WARD:
			world.wards.append(u)
		Unit.K_MINING_DRONE:
			world.mining_drones.append(u)
		Unit.K_REPAIR_DRONE:
			world.repair_drones.append(u)
		Unit.K_MONSTER, Unit.K_SNUB:
			world.monsters.append(u)


## Take unit `u` out of World.units and its kind's list, and free its node
## at the end of the frame (queue_free). A mothership's node is kept (it
## stays in World.motherships).
func remove(u: Unit) -> void:
	world.units.erase(u)
	match u.kind:
		Unit.K_SHIP:
			world.ships.erase(u)
			# A pilot whose flying ship is removed has died: start their
			# respawn. (Docking sets the pilot to "docked" and clears
			# profile.ship first, so a docked ship never counts as a death.)
			var s := u as Ship
			if s.profile != null and s.profile.ship == s and s.profile.state == "flying":
				world.rules.on_pilot_died(s.profile)
		Unit.K_MINION:
			world.minions.erase(u)
		Unit.K_TURRET:
			world.turrets.erase(u)
		Unit.K_BAY:
			world.bays.erase(u)
		Unit.K_WARD:
			world.wards.erase(u)
		Unit.K_MINING_DRONE:
			world.mining_drones.erase(u)
		Unit.K_REPAIR_DRONE:
			world.repair_drones.erase(u)
		Unit.K_MONSTER, Unit.K_SNUB:
			world.monsters.erase(u)
	if u.kind != Unit.K_MOTHERSHIP:
		u.queue_free()


## Once a tick: empty both spatial hashes and file every live unit (except
## motherships) into World.unit_hash. Units wider than
## Projectiles.HASH_PAD (60 world units) also go into World.big_hash,
## counted in World.big_count.
func rebuild_hashes() -> void:
	world.unit_hash.clear()
	world.big_hash.clear()
	world.big_count = 0
	for u in world.units:
		if u.alive and u.kind != Unit.K_MOTHERSHIP:
			world.unit_hash.insert(u)
			if u.radius > Projectiles.HASH_PAD:
				world.big_hash.insert(u)
				world.big_count += 1
