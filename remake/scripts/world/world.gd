class_name World
extends Node2D
## WHAT THIS IS: the running match. The World holds both teams, every unit
## (ships, minions, drones, turrets, motherships, ...) and every game
## system, and moves the whole game forward one small step at a time.
##
## HOW IT WORKS: Godot calls _physics_process() over and over (normally 60
## times a second). Each call is one "tick": one small step of game time,
## and `dt` is its length in seconds. Every tick runs the systems in the
## same fixed order (DESIGN.md B4). The order matters: changing it would
## change how a match plays out.
##   1. The match clock, the directors (minion waves, jungle respawns) and
##      each team's own timers.
##   2. Rebuild the spatial hashes (WorldRegistry.rebuild_hashes).
##   3. Vision: one team's fog of war every 0.1 s, so each team is updated
##      5 times a second (WorldVisibility), then support corvette auras
##      every 0.25 s (WorldSupport).
##   4. Units: every live unit takes its turn (sim_update): ships fly and
##      shoot, minions push down their lanes, drones mine, structures fire.
##   5. Separation: overlapping ships and minions are pushed apart
##      (WorldSeparation).
##   6. Projectiles: bullets, torpedoes and flak move and hit (Projectiles).
##   7. Ore nodes, respawns (MatchRules), the money trickle (Economy),
##      docked AI pilots, and the AI admirals.
##   8. Feature tick hooks (tick_hooks), if a feature module added any.
##
## Feature modules (scripts/features/, see FeatureRegistry) are optional
## mechanics switched on by rule variants. The World keeps the ones that
## are on (features) and two of their hook lists (push_weight_hooks,
## tick_hooks); all are empty by default, so nothing changes.
##
## WHO USES IT: main.gd makes the world from its scene and calls setup().
## Every unit keeps a link to it (`unit.world`), and the screens reach it
## through Game.world. New units are only made through the spawn_*
## functions and launch(), so every unit gets an id, goes into the lists
## and the spatial hash, and starts hidden in the fog the same way.
##
## THE PARTS: World has many jobs, so the work is split into helper
## objects ("parts") in files next to this one:
##   world_setup.gd      (WorldSetup)      builds the match at the start
##   world_registry.gd   (WorldRegistry)   unit ids, unit lists, spatial hashes
##   world_spawner.gd    (WorldSpawner)    makes new units
##   world_hangar.gd     (WorldHangar)     launch, dock, hyperspace, module swaps
##   world_queries.gd    (WorldQueries)    questions such as "nearest enemy?"
##   world_mining.gd     (WorldMining)     where mining drones work and unload
##   world_research.gd   (WorldResearch)   upgrades units already in space
##   world_visibility.gd (WorldVisibility) fog of war: who can see what
##   world_support.gd    (WorldSupport)    support corvette auras and paint
##   world_separation.gd (WorldSeparation) pushes overlapping ships apart
## This file keeps the shared state (the lists every file reads), the tick
## order, and thin "forwarding" functions with the old names, so other
## files still call World.launch(), World.spawn_minion() and so on.
##
## Words used here: a "spatial hash" is a grid laid over the map where each
## unit is filed under the grid square it sits in, so "who is near this
## point?" only checks a few squares instead of every unit. A "world unit"
## is the game's distance unit (about one pixel at normal zoom).

## How long (seconds) a hyperspace launch "spools up" before the ship
## appears at the repair bay. WorldHangar.hyperspace_launch() uses it.
const HYPERSPACE_SPOOL := 6.0

# --- match state --------------------------------------------------------------------

## The match clock: seconds of game time since the match started.
var time := 0.0
## "play" while the match runs, "end" once a mothership is destroyed (the
## tick then stops moving anything).
var phase := "play"
## The team that won (0 = Aurelian, 1 = Vhorr), or -1 while still playing.
var winner := -1
## What the human at the keyboard plays: "pilot" | "admiral" | "spectator".
var human_role := "pilot"
## Team whose fog the screen shows (-1 = see everything).
var viewer_team := 0
## The human's pilot profile (their slot, money and ship), or null for a
## spectator.
var human: PilotProfile = null

# --- game systems ---------------------------------------------------------------------

## The map layout: lanes, ore nodes, jungle camps, mothership spots.
var map: MapInfo
## The asteroid rocks (the "Asteroids" child node).
var asteroids: AsteroidField
## Fog of war: which parts of the map each team can see.
var vision: Vision
## Every bullet, torpedo and flak burst in flight (the "Projectiles" child).
var projectiles: Projectiles
## Damage, kills and kill rewards.
var combat: Combat
## Explosions and other visual effects (the "Effects" child node).
var effects: Effects
## Spatial hash of every live unit except motherships. Rebuilt each tick.
var unit_hash: SpatialHash
## Match flow: respawns, hyperspace spool countdowns and the win condition.
var rules: MatchRules
## Sends the minion waves (and runs Fleet Command minion buying).
var minion_director: MinionDirector
## Spawns and respawns the jungle monster camps.
var jungle_director: JungleDirector
## The admiral's order desk (a human admiral and the AI admirals both use it).
var command: AdmiralCommand
## The computer admiral of each team, [Aurelian, Vhorr]. null where a human
## is admiral (or with the "no-admiral-ai" test switch).
var admiral_ai: Array = [null, null]
## The AI pilot brains: PilotProfile -> PilotAI (no entry for the human).
var pilot_ai := {}
## Each team's shared state (treasury, research, facilities); index = team.
var teams: Array[TeamState] = []
## Every pilot in the match, AI and human, both teams.
var profiles: Array[PilotProfile] = []
## The two motherships; index = team.
var motherships: Array[Mothership] = []
## The ore fields ("resource nodes") on the map.
var nodes: Array[ResourceNode] = []

# --- unit lists (kept in step by WorldRegistry) ------------------------------------------

## Every unit in the match, all kinds. A unit leaves it when it dies.
var units: Array[Unit] = []
## A second spatial hash with only the big units: wider than
## Projectiles.HASH_PAD (60 world units), such as frigates, capital ships,
## turrets and big derelicts. Rebuilt each tick; Projectiles uses it for
## hit tests.
var big_hash: SpatialHash
## How many units went into big_hash this tick.
var big_count := 0
## Pilot ships (human and AI).
var ships: Array[Ship] = []
## Lane minions.
var minions: Array[Minion] = []
## Turrets built on ore nodes.
var turrets: Array[Turret] = []
## Repair bays.
var bays: Array[RepairBay] = []
## Wards (small stealthy watch drones that light up the fog).
var wards: Array[Ward] = []
## Mining drones.
var mining_drones: Array[MiningDrone] = []
## Repair drones (their jobs are RepairDrone's MODE_* numbers).
var repair_drones: Array[RepairDrone] = []
## Jungle monsters: derelicts and their snub fighters.
var monsters: Array[Unit] = []

# --- scene and input --------------------------------------------------------------------

## The node every unit node is added under (the "Units" child).
var units_root: Node2D
## The camera.
var camera: CameraRig
## True while the left mouse button is held down over the game (fire).
var mouse_fire := false
## True while the right mouse button is held down over the game (special).
var mouse_special := false

# --- profiling ----------------------------------------------------------------------------

## How long the last tick's simulation took (microseconds). main.gd and the
## tests read it.
var tick_usec := 0
## Time spent per tick section, added up over ticks (microseconds):
## "directors", "hash", "vision", "units", "projectiles", "rest" and one
## "u_<kind>" entry per unit kind. Only filled while `profiling` is on;
## Ship and Minion code add a few entries of their own.
var prof := {}
## Turn on to measure the tick sections into `prof` (main.gd and the
## performance test set it).
var profiling := false

# --- feature modules (see scripts/features/feature_registry.gd) -----------------------------

## The feature modules switched on for this match: variant key -> the
## feature's object. FeatureRegistry.install() fills it when the match is
## built. Empty (the default) = today's game.
var features := {}
## Feature hook for AI pilots choosing an enemy turret to push
## (PilotTargeting.push_target). Each entry is a function
## f(ship: Ship, target: Unit, score: float) -> float that gets a
## turret's score (its distance from the pilot's station in world units,
## as changed by the hooks before it) and returns a new score: lower = more
## wanted, INF = never. Empty (the default) = today's choice, the nearest.
var push_weight_hooks: Array[Callable] = []
## Feature hook: functions f(dt: float) -> void that run once every tick,
## after everything else in the tick (step 8 of _physics_process), in the
## order they were added (`dt` is the tick's length in seconds). Don't add
## or remove entries from inside one of them. Empty (the default) = nothing
## extra runs.
var tick_hooks: Array[Callable] = []
## Feature hook (fork economy_comebacks): functions f(ship: Ship, brain:
## PilotAI) -> void that run inside every AI pilot's think (PilotAI._think),
## after the normal job for its state has chosen a goal and a target and
## before the energy routing is set. A feature may change brain.goal,
## brain.target, brain.lock_target and brain.intent there. Empty (the
## default) = the brain thinks exactly as before.
var pilot_think_hooks: Array[Callable] = []
## Feature hook (fork economy_comebacks): functions f(victim: PilotProfile,
## ship: Ship) -> float that Economy._ship_killed asks when a pilot's ship
## is destroyed. Each returns extra bounty credits that are added to the
## kill's bounty (so the assist share grows with it). Empty (the default) =
## the bounty is exactly as before.
var bounty_hooks: Array[Callable] = []
## Feature hook: extra sight sources, such as the admiral's Sensor Sweep.
## Each entry is a Dictionary {"team": team number, "pos": Vector2 (world
## position), "r": sight radius in world units, "until": match time in
## seconds}. WorldVisibility.viewers() adds every live entry of the team to
## its list of seeing units, so the fog is lit with the usual line of sight
## (rocks block it). Empty (the default) = nothing extra is seen. The
## feature that adds entries also removes the expired ones.
var vision_sources: Array = []
## Feature hook: functions f(team: int, unit: Unit, radius: float) -> float
## that change how far one friendly unit sees (WorldVisibility.viewers()
## runs every function in turn on the radius the last one gave back; 0 or
## less = that unit lights nothing). Empty (the default) = normal sight.
var vision_mods: Array[Callable] = []

# --- parts (see THE PARTS at the top) --------------------------------------------------------

## Unit ids, the unit lists and the spatial hashes.
var registry: WorldRegistry
## Makes new units.
var spawner: WorldSpawner
## Launching, docking, hyperspace launches and module swaps.
var hangar: WorldHangar
## Questions about the match (nearest enemy, best bay, place names, ...).
var queries: WorldQueries
## Fog of war: which units each team can see.
var visibility: WorldVisibility
## Support corvette auras and paint.
var support: WorldSupport
## Pushing overlapping ships and minions apart.
var separation: WorldSeparation


## Make the parts once, when the world node is created (before setup()).
func _init() -> void:
	registry = WorldRegistry.new(self)
	spawner = WorldSpawner.new(self)
	hangar = WorldHangar.new(self)
	queries = WorldQueries.new(self)
	visibility = WorldVisibility.new(self)
	support = WorldSupport.new(self)
	separation = WorldSeparation.new(self)


# --- setup and the unit registry -----------------------------------------------------------

## Build the match. `role` is what the human plays: "pilot" | "admiral" |
## "spectator". main.gd calls it once. The real code is WorldSetup.build().
func setup(role: String) -> void:
	WorldSetup.build(self, role)


## A new, unique id number for a unit (1, 2, 3, ...). The real code is
## WorldRegistry.next_uid().
func next_uid() -> int:
	return registry.next_uid()


## Take a dead unit out of every list and free its node at the end of the
## frame. Combat calls it once a unit is dead. The real code is
## WorldRegistry.remove().
func remove_unit(u: Unit) -> void:
	registry.remove(u)


# --- launching and docking (real code: WorldHangar) ----------------------------------------

## Launch a docked pilot in the hull they own; returns the ship or null.
## `at_bay`: for a hyperspace launch, the friendly repair bay to appear at.
func launch(p: PilotProfile, at_bay: RepairBay = null) -> Ship:
	return hangar.launch(p, at_bay)


## Start a hyperspace launch to repair bay `bay`. Returns "" or the reason
## it can't (shown to the player).
func hyperspace_launch(p: PilotProfile, bay: Unit) -> String:
	return hangar.hyperspace_launch(p, bay)


## Buy or sell ship module `id` while flying inside a friendly repair bay.
## Returns "" or the reason it can't.
func swap_module_in_bay(p: PilotProfile, id: String) -> String:
	return hangar.swap_module_in_bay(p, id)


## Dock ship `s` at its mothership if it is close enough (or from anywhere,
## with `from_anywhere`: only the Recall feature). True if it docked.
func try_dock(s: Ship, from_anywhere: bool = false) -> bool:
	return hangar.try_dock(s, from_anywhere)


# --- spawning (real code: WorldSpawner) ------------------------------------------------------

## Make a minion of type `type_id` for `team` on lane `lane`, at point `at`.
func spawn_minion(team: int, type_id: String, lane: String, at: Vector2) -> Minion:
	return spawner.spawn_minion(team, type_id, lane, at)


## Make a mining drone for `team` next to its mothership. `assign` is the
## ore node id to mine, or "" to let the drone choose.
func spawn_mining_drone(team: int, assign: String) -> MiningDrone:
	return spawner.spawn_mining_drone(team, assign)


## Make a repair drone working for `owner` (a bay or a ship). `mode` is one
## of RepairDrone's MODE_* job numbers.
func spawn_repair_drone(owner: Unit, team: int, at: Vector2, mode: int) -> RepairDrone:
	return spawner.spawn_repair_drone(owner, team, at, mode)


## Build a turret of type `ttype` on slot `slot` of ore node `n`.
## `instant` = finished at once with full hull.
func spawn_turret(team: int, n: ResourceNode, slot: int, ttype: String, instant: bool = false) -> Turret:
	return spawner.spawn_turret(team, n, slot, ttype, instant)


## Launch a repair bay that flies from the mothership to `target`.
func spawn_bay(team: int, target: Vector2) -> RepairBay:
	return spawner.spawn_bay(team, target)


## Launch a ward that flies from the mothership to `target`.
func spawn_ward(team: int, target: Vector2) -> Ward:
	return spawner.spawn_ward(team, target)


## Make the derelict (jungle monster) of camp `camp_id` at `at`.
func spawn_derelict(camp_id: String, type_id: String, at: Vector2) -> Derelict:
	return spawner.spawn_derelict(camp_id, type_id, at)


## Make a snub fighter for derelict carrier `carrier`.
func spawn_snub(carrier: Derelict) -> SnubFighter:
	return spawner.spawn_snub(carrier)


# --- questions about the match (real code: WorldQueries, WorldMining) ---------------------------

## The mothership of `team`, or null for a team number that has none
## (such as Rules.NEUTRAL). Very many files call this, so it stays here.
func mothership(team: int) -> Mothership:
	if team < 0 or team >= motherships.size():
		return null
	return motherships[team]


## The ore node with id `id`, or null.
func node_by_id(id: String) -> ResourceNode:
	return queries.node_by_id(id)


## How many live mining drones `team` has.
func mining_drone_count(team: int) -> int:
	return queries.mining_drone_count(team)


## True if a live enemy pilot ship or minion is within `r` world units
## of point `p`.
func any_enemy_ship_near(p: Vector2, r: float, team: int) -> bool:
	return queries.any_enemy_ship_near(p, r, team)


## The nearest live enemy of `team` (any kind, not neutral)
## within `r` of `p`, or null. `filter` (optional) must return true for a
## unit to count.
func nearest_enemy(p: Vector2, r: float, team: int, filter: Callable = Callable()) -> Unit:
	return queries.nearest_enemy(p, r, team, filter)


## The points of lane `lane` (as `team` walks it), starting from the lane
## point nearest `from`.
func lane_path_from(lane: String, team: int, from: Vector2) -> PackedVector2Array:
	return queries.lane_path_from(lane, team, from)


## The ore node (by id) a mining drone of `team` should work: ore on hand,
## a short and safe trip. The real code is WorldMining.best_node_for_drone().
func best_node_for_drone(team: int, from: Vector2) -> String:
	return WorldMining.best_node_for_drone(self, team, from)


## Where drones of `team` unload ore (beside their mothership). The real
## code is WorldMining.drop_off_point().
func drop_off_point(team: int, from: Vector2) -> Vector2:
	return WorldMining.drop_off_point(self, team, from)


## How far `from` is from the surface of the team's mothership (world
## units, negative inside). The real code is WorldMining.drop_off_dist().
func drop_off_dist(team: int, from: Vector2) -> float:
	return WorldMining.drop_off_dist(self, team, from)


## The nearest working (anchored) repair bay of `team` to `from`, or null.
func best_bay(team: int, from: Vector2) -> RepairBay:
	return queries.best_bay(team, from)


## The friendly repair bay whose module-swap circle contains `p`, or null.
func bay_at(team: int, p: Vector2) -> RepairBay:
	return queries.bay_at(team, p)


## A readable place name for news lines ("Top lane", "The Crossing", ...).
func place_name(p: Vector2) -> String:
	return queries.place_name(p)


## TeamState calls this when `team` finishes research `id`, so the units
## already in space get the upgrade. The real code is
## WorldResearch.on_research_done().
func on_research_done(team: int, id: String) -> void:
	WorldResearch.on_research_done(self, team, id)


## Where the mouse pointer is, in world units (for aiming and the camera).
func mouse_world() -> Vector2:
	return get_global_mouse_position()


## What lights the fog for `team`: one Vector3(x, y, radius) per unit that
## sees. The real code is WorldVisibility.viewers() (a test calls this name).
func _viewers(team: int) -> Array:
	return visibility.viewers(team)


# --- the tick ---------------------------------------------------------------------------------

## One tick of the match (see HOW IT WORKS at the top for the order).
## Godot calls this; `dt` is the tick's length in seconds.
func _physics_process(dt: float) -> void:
	# Nothing moves once the match is over.
	if phase != "play":
		return
	var t0 := Time.get_ticks_usec()
	# Step 1: the clock, the directors and each team's timers.
	time += dt
	minion_director.tick(dt)
	jungle_director.tick(dt)
	for t in teams:
		t.tick(dt)
	var tp := _prof_mark("directors", t0)

	# Step 2: file every live unit into the spatial hashes for this tick.
	registry.rebuild_hashes()
	tp = _prof_mark("hash", tp)

	# Step 3: fog of war for one team (every 0.1 s), then support corvette
	# auras (every 0.25 s).
	visibility.tick(dt)
	support.tick(dt)
	tp = _prof_mark("vision", tp)

	# Step 4: every live unit takes its turn. We walk a copy of the list,
	# because units may die or be born during the loop.
	var snapshot := units.duplicate()
	if profiling:
		# The same loop, but also timing each unit, added up per kind.
		for u: Unit in snapshot:
			if u.alive:
				var tu := Time.get_ticks_usec()
				u.sim_update(dt)
				var key: String = "u_" + Unit.KIND_NAMES[u.kind]
				prof[key] = int(prof.get(key, 0)) + (Time.get_ticks_usec() - tu)
	else:
		for u: Unit in snapshot:
			if u.alive:
				u.sim_update(dt)
	tp = _prof_mark("units", tp)

	# Steps 5 and 6: push overlapping ships apart, then move the projectiles.
	separation.separate(dt)
	projectiles.tick(dt)
	tp = _prof_mark("projectiles", tp)

	# Step 7: ore nodes, match rules (respawns), the money trickle...
	for n in nodes:
		n.tick(dt)
	rules.tick(dt)
	Economy.passive_income(self, dt)
	# ...docked AI pilots (PilotAI.update_docked), then the AI admirals.
	for p: PilotProfile in pilot_ai:
		if p.state == "docked":
			(pilot_ai[p] as PilotAI).update_docked(dt)
	for t in 2:
		if admiral_ai[t] != null:
			(admiral_ai[t] as AdmiralAI).tick(dt)
	# Step 8: the feature modules' tick hooks (none unless a feature is on).
	for f: Callable in tick_hooks:
		f.call(dt)
	_prof_mark("rest", tp)
	tick_usec = Time.get_ticks_usec() - t0


## Profiling helper: if `profiling` is on, add the microseconds since
## `since` to prof[key]. Always returns "now" (microseconds), the start
## time of the next section.
func _prof_mark(key: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	if profiling:
		prof[key] = int(prof.get(key, 0)) + (now - since)
	return now


# --- mouse input that must respect the GUI ------------------------------------------------------

## Mouse presses the GUI did not use (Godot only sends a click here when no
## button or panel took it). Left button = fire, right button = special.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			mouse_fire = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			mouse_special = mb.pressed


## Every mouse event, even over the GUI. Releases are always honoured here,
## so firing never gets stuck "on" when the button is let go over a panel.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			mouse_fire = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			mouse_special = false
