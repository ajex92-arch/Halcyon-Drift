class_name WorldHangar
extends RefCounted
## WHAT THIS IS: the hangar desk of the motherships. It launches pilots
## into space, docks them again, starts hyperspace launches to a repair
## bay, and swaps ship modules for pilots flying inside a repair bay.
##
## HOW IT WORKS: a pilot is always in one of four states
## (PilotProfile.state): "docked" (inside the mothership), "spooling"
## (waiting for a hyperspace jump), "flying" or "dead".
##   - launch() turns "docked" into "flying" and makes the ship.
##   - try_dock() turns "flying" back into "docked" and removes the ship.
##     Docking repairs fully: the ship node goes away, but the pilot keeps
##     owning the hull and its modules for the next launch.
##   - hyperspace_launch() turns "docked" into "spooling". MatchRules.tick()
##     counts the spool down and then calls launch() with the bay.
##   - swap_module_in_bay() buys or sells one module while flying
##     (DESIGN.md A11).
##
## WHO USES IT: World makes one (World.hangar); World.launch(),
## World.hyperspace_launch(), World.swap_module_in_bay() and
## World.try_dock() forward here. Callers: the hangar screen (hangar.gd),
## AI pilots (PilotAI), MatchRules, Ship (docking), main.gd and tests.

## The world (for motherships, teams, bays and the spawner).
var world: World


## Remember the world. World makes this part once.
func _init(w: World) -> void:
	world = w


## Launch docked pilot `p` in the hull they own. Returns the new ship, or
## null if they can't launch (not docked, no hull picked, or nowhere to
## launch from). `at_bay`: for a hyperspace launch, the friendly repair
## bay to appear at (only works while the team owns the Hyperspace Module).
func launch(p: PilotProfile, at_bay: RepairBay = null) -> Ship:
	# Only a docked pilot who has picked a hull can launch.
	if p.state != "docked" or p.hull_id == "":
		return null
	var ms := world.mothership(p.team)
	var pos: Vector2
	var facing: float
	# Where the ship appears, best choice first. (a) Hyperspace: a random
	# spot 160 world units from the chosen bay, facing where the enemy
	# mothership started (map.mothership_pos).
	if at_bay != null and is_instance_valid(at_bay) and at_bay.alive and world.teams[p.team].facilities.has("hyperspace"):
		pos = at_bay.global_position + Vector2.from_angle(randf() * TAU) * 160.0
		facing = (world.map.mothership_pos[1 - p.team] - pos).angle()
	# (b) Normally: the pilot's launch point off the mothership's bow,
	# pointing the way the mothership points.
	elif ms != null and ms.available():
		pos = ms.launch_point(p.slot)
		facing = ms.rotation
	# (c) While the mothership is offline: a random spot 160 world units
	# from the anchored repair bay nearest to it, or no launch at all.
	else:
		var bay := world.best_bay(p.team, ms.global_position if ms != null else Vector2.ZERO)
		if bay == null:
			return null
		pos = bay.global_position + Vector2.from_angle(randf() * TAU) * 160.0
		facing = (world.map.mothership_pos[1 - p.team] - pos).angle()
	# Make the ship and give it a driver: the keyboard and mouse
	# (PlayerController) for a human, the pilot's AI brain otherwise.
	var s := world.spawner.spawn_pilot_ship(p, pos, facing)
	s.controller = PlayerController.new(world) if p.is_human else world.pilot_ai.get(p)
	p.ship = s
	p.state = "flying"
	# An admiral flying their own ship has left the admiral's chair.
	if p.role == "admiral":
		world.teams[p.team].admiral_docked = false
	Events.cue.emit("launch", pos)
	return s


## Hyperspace launch (needs the Hyperspace Module): docked pilot `p` spools
## up for World.HYPERSPACE_SPOOL seconds (6), then appears at repair bay
## `bay` (MatchRules.tick finishes it). Returns "" or why not (shown to the
## player).
func hyperspace_launch(p: PilotProfile, bay: Unit) -> String:
	# Feature hook (Forward Redeploy): the jump may go to a repair bay or a
	# turret and spools for 4 s (RedeployFeature.start).
	if world.features.has("redeploy"):
		return (world.features["redeploy"] as RedeployFeature).start(p, bay)
	# Check every reason it can't happen, in order.
	if p.state != "docked":
		return "You must be docked at the mothership"
	if not world.teams[p.team].facilities.has("hyperspace"):
		return "Needs the Hyperspace Module"
	if bay == null or not is_instance_valid(bay) or not bay.alive or not (bay as RepairBay).is_anchored():
		return "That repair bay is gone"
	if p.hull_id == "":
		return "Pick a ship first"
	# Start the spool: respawn_t doubles as the spool countdown.
	p.state = "spooling"
	p.respawn_t = World.HYPERSPACE_SPOOL
	p.spool_bay = bay as RepairBay
	return ""


## Buy or sell ship module `id` in flight, while inside a friendly repair
## bay's module-swap circle (DESIGN.md A11). Returns "" or why not.
func swap_module_in_bay(p: PilotProfile, id: String) -> String:
	# Must be flying, and inside one of our bays.
	var s := p.ship
	if s == null or not is_instance_valid(s) or not s.alive:
		return "You need to be flying"
	if world.bay_at(p.team, s.global_position) == null:
		return "Fly inside one of our repair bays to swap modules"
	# Copy the ship's modules to the profile, buy or sell there
	# (PilotProfile.toggle_module), then copy the result back to the ship.
	p.modules.assign(s.modules)
	var err := p.toggle_module(id)
	if err != "":
		return err
	s.modules.assign(p.modules)
	# Rebuild the gun mounts that modules add (the PD Module adds a
	# point-defence gun); the hull's own mounts stay as they are.
	var base_count := (s.def["mounts"] as Array).size()
	while s.mounts.size() > base_count:
		s.mounts.pop_back()
	for mid: String in s.modules:
		var md: Dictionary = Modules.MODULES[mid]
		if md.has("adds_mount"):
			s.mounts.append(WeaponMount.new(s, md["adds_mount"], "auto", Vector2(-s.radius * 0.4, 0), 180.0))
	# The ship recomputes its stats (speed, shields, ...) on its next turn.
	s.stats_dirty = true
	return ""


## Dock flying ship `s` at its mothership if it is close enough. Returns
## true if it docked. A human gets a short message when they can't.
## `from_anywhere` (only the Recall feature passes true) skips the distance
## test: the ship docks wherever it is.
func try_dock(s: Ship, from_anywhere: bool = false) -> bool:
	# The mothership must be working, and the ship within its dock radius
	# of the hull.
	var ms := world.mothership(s.team)
	if ms == null or not ms.available():
		if s.profile.is_human:
			Events.toast.emit("Can't dock: the mothership is offline.")
		return false
	if not from_anywhere and ms.hull_dist(s.global_position) > ms.dock_radius():
		if s.profile.is_human:
			Events.toast.emit("Fly closer to the mothership to dock.")
		return false
	# The pilot keeps the modules and goes back inside. This happens before
	# the ship is removed, so the removal does not count as a death.
	var p := s.profile
	p.modules.assign(s.modules)
	p.state = "docked"
	p.ship = null
	if p.role == "admiral":
		world.teams[p.team].admiral_docked = true
	# The ship and its escort and kit drones leave the match quietly (no
	# kill rewards).
	s.alive = false
	for d in s.escort_drones + s.kit_drones:
		if is_instance_valid(d) and d.alive:
			world.combat.kill_silently(d)
	world.remove_unit(s)
	Events.cue.emit("ui", ms.global_position)
	return true
