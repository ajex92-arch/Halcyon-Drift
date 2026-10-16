class_name ShipAbilities
extends RefCounted
## WHAT THIS IS: the "special powers" of a pilot ship (a part of Ship, kept
## in its own file): each hull's special ability, repair kits, and the
## escort repair drones of the Logistics ship.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own
## (except one reusable list). Each function is handed the ship and changes
## the ship's own variables.
##   - use_special(): every hull has one special (Ships.HULLS "special").
##     Using it costs energy and starts a cooldown, then:
##       ping       (Scout) reveal everything within 4500 for 3 s; with the
##                  team's Scout EMP upgrade, also EMP enemy ships within
##                  900 for 3 s (engines at 35%, no boost).
##       snap       (Fighter) turn 1.9x faster for 1.5 s.
##       overload   (Lance) +60% damage for 2.5 s.
##       focus      (Bomber) the next shot of each FIXED gun does 1.45x.
##       capdump    (Ion) the next shot or burst of each FIXED gun does 1.8x
##                  ("Capacitor Dump").
##       emergency_repair (Logistics) repair friendly ships and structures
##                  within 650 by 12% of their maximum hull.
##       jam        (Support) jam enemy vision around us for 7 s.
##       brace      (Flak) take only 62% damage for 5 s.
##       overcharge (Destroyer) double fire rate for 5 s.
##       broadside  (Battlecruiser) +50% fire rate for 6 s.
##     (The timed effects are read elsewhere: ShipStats, ShipFlight,
##     Ship.incoming_mult() and World's vision code.)
##   - use_repair_kit(): spend one repair kit from the pilot's inventory to
##     launch a weak repair drone that heals only this ship.
##   - manage_escort_drones(): hulls with "repair_drones" in their data (the
##     Logistics ship) keep that many repair drones flying with them,
##     launching a new one at most every 12 s.
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: Ship forwards to it: Ship._use_special() (when the pilot
## presses the special key and it is ready), Ship.use_repair_kit(),
## Ship.has_active_kit(), and Ship.sim_update() for the escort drones.

## A reusable list that the spatial hash fills with nearby units, so we
## don't make a new list every time. (The "spatial hash", world.unit_hash,
## sorts units into a grid of cells so "who is near this point?" is quick to
## answer.) The query empties it before filling it.
static var _scratch: Array = []


## Use `ship`'s special ability now (the caller has checked that it is
## ready). See the list at the top of this file.
static func use_special(ship: Ship) -> void:
	var world := ship.world
	# Step 1: pay the energy and start the cooldown (gear can shorten the
	# cooldown, but never below 30%).
	ship.energy.spend(float(ship.def["special_energy"]))
	ship.special_cd = float(ship.def["special_cd"]) * maxf(0.3, ship.stats.mul("special_cd_pct"))
	var sp: String = ship.def["special"]
	# Step 2: do what this hull's special does.
	match sp:
		"ping":
			world.vision.reveal(ship.team, ship.global_position, 4500.0, 3.0)
			world.effects.pulse(ship.global_position, 4500.0, 0.9, Palette.VEIL)
			# Scout EMP upgrade: knock out nearby enemy ships' engines.
			if world.teams[ship.team].scout_emp:
				for u: Unit in world.unit_hash.query(ship.global_position, 900.0, _scratch):
					if u is Ship and u.team != ship.team and u.alive and u.global_position.distance_to(ship.global_position) < 900.0:
						(u as Ship).emp_t = 3.0
						(u as Ship).stats_dirty = true
				world.effects.pulse(ship.global_position, 900.0, 0.5, Palette.ICE)
		"snap", "overload":
			ship.special_t = 1.5 if sp == "snap" else 2.5
			ship.stats_dirty = true
		"focus", "capdump":
			for m in ship.mounts:
				if m.mount_type == WeaponMount.FIXED:
					m.next_mult = 1.45 if sp == "focus" else 1.8
		"emergency_repair":
			for u: Unit in world.unit_hash.query(ship.global_position, 650.0, _scratch):
				if u.team == ship.team and u.alive and u.global_position.distance_to(ship.global_position) < 650.0:
					if u.kind == Unit.K_SHIP or u.is_structure():
						u.heal(u.hull_max * 0.12)
			world.effects.pulse(ship.global_position, 650.0, 0.6, Palette.REPAIR)
		"jam":
			ship.jam_t = 7.0
			world.effects.pulse(ship.global_position, 1400.0, 0.8, Palette.VEIL)
		"brace", "overcharge", "broadside":
			ship.special_t = 5.0 if sp != "broadside" else 6.0
			ship.stats_dirty = true
	# Step 3: play the sound.
	Events.cue.emit("special", ship.global_position)


## True while a repair-kit drone of `ship` is still alive. Drones that are
## gone (freed, or dead) are removed from ship.kit_drones here; kit drones
## free themselves after KIT_DRONE.duration (Structures).
static func has_active_kit(ship: Ship) -> bool:
	for i in range(ship.kit_drones.size() - 1, -1, -1):
		var d = ship.kit_drones[i]
		if not is_instance_valid(d) or not d.alive:
			ship.kit_drones.remove_at(i)
	return not ship.kit_drones.is_empty()


## The R key (or the AI): spend one repair kit from the pilot's inventory;
## a weak repair drone then heals this ship. Does nothing at full hull, for
## ships without a pilot profile, or when the pilot has no kit left.
static func use_repair_kit(ship: Ship) -> void:
	if ship.profile == null or ship.hull >= ship.hull_max:
		return
	# Tidy the list of kit drones first (the answer is not needed here).
	has_active_kit(ship)
	if not ship.profile.consume_kit():
		return
	# Launch the drone and tell it to heal us.
	var d := ship.world.spawn_repair_drone(ship, ship.team, ship.global_position, RepairDrone.MODE_KIT)
	d.lock_target(ship)
	ship.kit_drones.append(d)
	Events.cue.emit("repair", ship.global_position)


## Keep the Logistics ship's escort repair drones topped up: forget the
## ones that are gone, and launch a new one when we have fewer than the
## hull's "repair_drones" number and the last launch was over 12 s ago. The
## time of the last launch is kept on the ship as metadata "drone_t" (a
## named value Godot lets you attach to any node).
static func manage_escort_drones(ship: Ship) -> void:
	var want: int = int(ship.def["repair_drones"])
	for i in range(ship.escort_drones.size() - 1, -1, -1):
		var d = ship.escort_drones[i]
		if not is_instance_valid(d) or not d.alive:
			ship.escort_drones.remove_at(i)
	if ship.escort_drones.size() < want and ship.world.time - float(ship.get_meta("drone_t", -99.0)) > 12.0:
		ship.set_meta("drone_t", ship.world.time)
		ship.escort_drones.append(ship.world.spawn_repair_drone(ship, ship.team, ship.global_position, RepairDrone.MODE_LOGISTICS))
