class_name Ship
extends Unit
## WHAT THIS IS: a pilot ship: the spaceship that one pilot (a human player
## or an AI pilot) flies. There are ten hulls, from the small Scout to the
## huge Battlecruiser (Ships.HULLS). DESIGN.md A5.
##
## HOW IT WORKS: every tick (the game moves forward in small steps called
## ticks, 60 per second) World calls sim_update(), which in this order:
##   1. lets the controller (the human's PlayerController or an AI pilot's
##      PilotAI brain) fill in `controls`, the ship's "sticks and buttons";
##   2. counts down the timers, then carries out the button presses: shield
##      focus, energy routing, special, repair kit, dock;
##   3. works out the stats again when needed (ShipStats);
##   4. flies and moves (ShipFlight): turning, thrust, boost, sliding along
##      asteroids and gentle crash damage;
##   5. refills the battery and shields, and works the guns (WeaponMount);
##   6. keeps a Logistics ship's escort repair drones topped up.
##
## A Ship node exists only while flying. Docked pilots have no node: their
## owned hull and modules live on the PilotProfile; World.launch() spawns a
## fresh Ship and World.try_dock() removes it. Death destroys the ship and
## its modules; pilot gear stays on the profile.
##
## THE PARTS: Ship keeps all the ship's variables and its public functions
## (many other files read ship.something). The detail lives in three
## "static library" parts that are handed the ship:
##   ShipStats     (ship_stats.gd)     works out speed, turning, damage,
##                                     hull, shields, battery and vision
##   ShipFlight    (ship_flight.gd)    flying, bumping and crashing
##   ShipAbilities (ship_abilities.gd) specials, repair kits, escort drones
##
## WHO USES IT: World.launch() creates it and calls setup(); World runs
## sim_update() and removes it on docking (try_dock) or death; Combat
## damages it and Unit.take_hit() asks incoming_mult() and
## shield_resist_bonus(); Economy
## reads bounty_value() and sets ace_t; World sets support_t, paint_t and
## stats_dirty and reads jam_t; PilotProfile sets stats_dirty when gear
## changes; PlayerController and PilotAI fill `controls` and read the stats
## and timers; ShipVisual draws it; the HUD (ShipStatus) shows its timers;
## WeaponMount asks homing_target(); RepairDrone reads repair_recv.
##
## To add a hull: data in ships.gd, silhouette in ShipVisual.HULLS, special
## in ShipAbilities.use_special() (Ship._use_special() forwards there).

## How much faster the Fighter turns while its Snap special is on (1.9x).
const SPECIAL_SNAP_TURN := 1.9

# --- what this ship is -----------------------------------------------------------------

## Which hull this is: an id from Ships.HULLS (e.g. "fighter").
var hull_id := ""
## That hull's data from Ships.HULLS (speeds, hull, shields, guns, special).
var def: Dictionary = {}
## The pilot's record (PilotProfile): team, callsign, gear, kits, credits.
var profile: PilotProfile = null
## The pilot's "hands": anything with `func update(ship: Ship, dt: float)
## -> void`. World.launch() sets the human's PlayerController or the AI
## pilot's PilotAI brain. Null = nobody at the controls.
var controller = null
## The sticks and buttons for this tick (ShipControls), filled by the
## controller.
var controls := ShipControls.new()
## The ids of the modules fitted to this ship (Modules.MODULES).
var modules: Array[String] = []
## The summed bonuses from gear and modules (StatBlock), rebuilt by
## recompute_stats().
var stats := StatBlock.new()
## The ship's battery and energy routing (EnergyPool).
var energy := EnergyPool.new()
## The ship's guns (WeaponMount): the hull's own, then any added by modules.
var mounts: Array[WeaponMount] = []
## Flight assist on or off (the human can toggle it; PlayerController copies
## it into controls.assist).
var assist := true

# --- worked-out flight and combat numbers (set by recompute_stats) --------------------

## Main engine push, in world units per second, per second.
var f_accel := 0.0
## Reverse thruster push, in world units per second, per second.
var f_reverse := 0.0
## Side thruster push, in world units per second, per second.
var f_strafe := 0.0
## Top speed (a soft cap), in world units per second.
var f_max := 0.0
## Turning speed, in radians per second (a full turn is about 6.28).
var f_turn := 0.0
## The fraction (0..1) of turning speed lost at top speed.
var f_bleed := 0.0
## Flight assist strength: how fast sideways drift dies away (per second).
var f_assist := 0.0
## How fast speed above the cap is pulled back down (per second).
var f_cap_rate := 2.0
## Engine push multiplier while boosting.
var f_boost_mul := 1.0
## How far over top speed boosting may go (a multiplier of f_max).
var f_boost_cap := 1.0
## Energy spent per second while boosting.
var f_boost_drain := 30.0
## True if this ship can boost right now (a booster hull or a Boost Cell
## module, and not EMP'd).
var can_boost := false
## Rate-of-fire multiplier for all guns.
var fire_mult := 1.0
## Damage multiplier for all guns.
var dmg_mult := 1.0
## Reach multiplier for all guns.
var range_mult := 1.0
## Shield refill speed multiplier.
var regen_mult := 1.0
## Seconds added to the shields' wait before refilling (from gear).
var shield_delay_bonus := 0.0
## The fraction (0..0.9) of crash damage ignored.
var collision_resist := 0.0
## Multiplier on repairs this ship receives from repair drones.
var repair_recv := 1.0
## Seconds until the next routine stats rebuild (every 0.25 s).
var stats_t := 0.0
## True = rebuild the stats on the next tick (set when something changes).
var stats_dirty := true

# --- timers and effects (all in seconds; 0 = off or ready) ----------------------------

## Seconds until the special can be used again.
var special_cd := 0.0
## Seconds left on a special that lasts (Snap, Overload, Brace, Overcharge,
## Broadside).
var special_t := 0.0
## Seconds until the shield focus may change again.
var focus_cd := 0.0
## Seconds until the energy routing may change again.
var energy_cd := 0.0
## Seconds left of "ace" bonuses (faster, harder-hitting). Economy starts it
## (Rules.ACE_TIME) when the pilot gets Rules.ACE_KILLS kills in a row.
var ace_t := 0.0
## Seconds left of an EMP from an enemy Scout's ping: engines at 35%, no
## boost.
var emp_t := 0.0
## Seconds left of our Jam special: enemy vision near us shrinks (World).
var jam_t := 0.0
## Seconds left of being "painted" by an enemy Support ship: torpedoes do
## 30% more damage to us (Combat.PAINT_BONUS). World sets it.
var paint_t := 0.0
## Seconds left of a friendly Support ship's aura: +6% turning, +6% damage,
## +8% reach. World sets it.
var support_t := 0.0
## Seconds until a crash can hurt us again (0.4 s after each painful crash).
var collide_cd := 0.0
## Our repair-kit drones that may still be flying (RepairDrone nodes).
var kit_drones: Array = []
## Our escort repair drones (Logistics ship only; RepairDrone nodes).
var escort_drones: Array = []
## Match time (seconds) of launch. PlayerController ignores the dock key for
## 0.5 s after it, so the launch key press can't also dock us.
var launched_at := 0.0

# --- read by ShipVisual for the engine flames (0..1 each) -----------------------------

## How hard the main engine burns (0..1).
var thrust_main := 0.0
## How hard the port (left-pushing) thruster burns (0..1).
var thrust_port := 0.0
## How hard the starboard (right-pushing) thruster burns (0..1).
var thrust_star := 0.0
## True while boosting this tick (also shown by the HUD).
var boosting := false
## Feature hook (Lane Slipstream, WorldSlipstream): true while this ship runs
## in the slipstream, which raises its top speed (ShipStats calls
## WorldSlipstream.apply()). Always false unless --variant=slipstream is on.
var slip := false


## Set up a freshly made ship. Called by World.launch() with the world `w`,
## the pilot `p`, hull id `hid`, module ids `mods`, start point `at` and
## facing `facing` (radians).
func setup(w: World, p: PilotProfile, hid: String, mods: Array, at: Vector2, facing: float) -> void:
	# Step 1: who we are.
	world = w
	profile = p
	team = p.team
	kind = Unit.K_SHIP
	launched_at = w.time
	hull_id = hid
	def = Ships.get_def(hid)
	size_class = int(def["size"])
	radius = float(def["radius"])
	display_name = p.callsign
	modules.assign(mods)
	# Step 2: where we start (already moving forward at 120), and how we
	# collide: we are on physics layer 2 ("pilot ships") and bump into
	# layers 1, 3 and 4 (asteroids, structures, ore-field rocks).
	position = at
	rotation = facing
	velocity = Vector2.from_angle(facing) * 120.0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	var cs := get_node_or_null("Shape") as CollisionShape2D
	if cs != null:
		var circ := CircleShape2D.new()
		circ.radius = radius
		cs.shape = circ
	# Step 3: shields, battery and hull from the hull's data.
	shields = ShieldZones.new()
	shields.setup(float(def["shield"]), float(def["shield_regen"]), float(Rules.SHIELD_DELAY[size_class]))
	shields.resist = float(def["shield_resist"])
	energy.setup(float(def["energy"]), float(def["energy_regen"]))
	hull_max = float(def["hull"])
	hull = hull_max
	hull_resist = float(def["hull_resist"])
	# Step 4: guns: the hull's own, then one AUTO gun per module that adds
	# one (mounted near the tail, free to swing all the way round).
	mounts.clear()
	for m: Dictionary in def["mounts"]:
		mounts.append(WeaponMount.new(self, m["w"], m["type"], m["off"], float(m["arc"])))
	for mid: String in modules:
		var md: Dictionary = Modules.MODULES[mid]
		if md.has("adds_mount"):
			mounts.append(WeaponMount.new(self, md["adds_mount"], "auto", Vector2(-radius * 0.4, 0), 180.0))
	# Step 5: work out the stats with a full repair, and aim straight ahead.
	recompute_stats(true)
	controls.aim_point = at + Vector2.from_angle(facing) * 2000.0
	controls.face_point = controls.aim_point


## What the ship is worth in credits: hull price + module prices. Used for
## kill bounties and insurance (and by the AI when trading in a hull).
func bounty_value() -> float:
	var v := float(def.get("price", 0.0))
	for mid: String in modules:
		v += Modules.price_for(mid, hull_id)
	return v


## True for small ships (size class Rules.SIZE_SMALL).
func is_small() -> bool:
	return size_class == Rules.SIZE_SMALL


## Can the special be used now? (Cooldown over and enough energy.)
func special_ready() -> bool:
	return special_cd <= 0.0 and energy.value >= float(def["special_energy"])


## Rebuild the worked-out stats from hull + modules + pilot gear + team
## upgrades + buffs. Cheap; runs every 0.25 s and whenever something
## changes. `full_heal` also fills hull, shields and battery (at launch).
## Forwarding function: the real code is ShipStats.recompute().
func recompute_stats(full_heal: bool = false) -> void:
	ShipStats.recompute(self, full_heal)


## Damage multiplier on incoming hits: 0.62 while a Flak ship's Brace
## special is on, otherwise 1.0. (Unit.take_hit() uses it.)
func incoming_mult() -> float:
	if hull_id == "flak" and special_t > 0.0:
		return 0.62
	return 1.0


## Extra shield resistance from energy routing (0.15 when routing to
## Shields, else 0). Unit.take_hit() uses it.
func shield_resist_bonus() -> float:
	return energy.m("sresist")


## The unit our homing torpedoes should chase: the controller's
## `lock_target` (PilotAI has one; PlayerController doesn't), if it is
## still alive. Else null.
func homing_target() -> Unit:
	if controller != null and "lock_target" in controller:
		var t = controller.lock_target
		if t != null and is_instance_valid(t) and t is Unit and t.alive:
			return t
	return null


# --- per tick ---------------------------------------------------------------------------

## One tick of `dt` seconds (see HOW IT WORKS at the top). When World's
## speed measuring ("profiling") is on, it also adds up how long each stage
## took, in microseconds, into world.prof.
func sim_update(dt: float) -> void:
	if not alive:
		return
	var prof := world != null and world.profiling
	var t0 := Time.get_ticks_usec() if prof else 0
	# Stage 1: the controller works the sticks and buttons.
	if controller != null:
		controller.update(self, dt)
	var t1 := Time.get_ticks_usec() if prof else 0
	# Stage 2: timers, then button presses.
	_timers(dt)
	_requests()
	# Docking (F) removes the ship inside _requests().
	if not alive:
		controls.clear_edges()
		return
	# Stage 3: stats if due, then fly and move.
	stats_t -= dt
	if stats_dirty or stats_t <= 0.0:
		recompute_stats()
	ShipFlight.fly(self, dt)
	var t2 := Time.get_ticks_usec() if prof else 0
	ShipFlight.move(self)
	# A hard asteroid hit can kill us inside ShipFlight.move().
	if not alive:
		return
	var t3 := Time.get_ticks_usec() if prof else 0
	# Stage 4: battery, shields, guns and escort drones.
	energy.tick(dt)
	shields.tick(dt, regen_mult, shield_delay_bonus)
	_weapons(dt)
	if def.has("repair_drones"):
		ShipAbilities.manage_escort_drones(self)
	# Stage 5: one-tick button presses are used up.
	controls.clear_edges()
	if prof:
		var t4 := Time.get_ticks_usec()
		world.prof["s_ctrl"] = int(world.prof.get("s_ctrl", 0)) + (t1 - t0)
		world.prof["s_flight"] = int(world.prof.get("s_flight", 0)) + (t2 - t1)
		world.prof["s_move"] = int(world.prof.get("s_move", 0)) + (t3 - t2)
		world.prof["s_weap"] = int(world.prof.get("s_weap", 0)) + (t4 - t3)


## Count every timer down by `dt` seconds (never below 0). When a special,
## ace or EMP runs out, the stats must be worked out again.
func _timers(dt: float) -> void:
	# Cooldowns and lasting effects.
	if special_cd > 0.0:
		special_cd = maxf(0.0, special_cd - dt)
	if special_t > 0.0:
		special_t = maxf(0.0, special_t - dt)
		if special_t == 0.0:
			stats_dirty = true
	if focus_cd > 0.0:
		focus_cd = maxf(0.0, focus_cd - dt)
	if energy_cd > 0.0:
		energy_cd = maxf(0.0, energy_cd - dt)
	# Buffs and debuffs from others.
	if ace_t > 0.0:
		ace_t = maxf(0.0, ace_t - dt)
		if ace_t == 0.0:
			stats_dirty = true
	if emp_t > 0.0:
		emp_t = maxf(0.0, emp_t - dt)
		if emp_t == 0.0:
			stats_dirty = true
	if jam_t > 0.0:
		jam_t = maxf(0.0, jam_t - dt)
	if paint_t > 0.0:
		paint_t = maxf(0.0, paint_t - dt)
	if support_t > 0.0:
		support_t = maxf(0.0, support_t - dt)
	# The crash timer may dip below 0 (it is only compared with 0).
	if collide_cd > 0.0:
		collide_cd -= dt
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)


## Carry out this tick's button presses from `controls`. A shield focus or
## energy routing change only happens when its cooldown is over and it is a
## real change; it then starts a new cooldown (by size class, shortened by
## "redirect" gear but never below 20%). Then the special, the repair kit
## and docking.
func _requests() -> void:
	var c := controls
	var cd_mul := maxf(0.2, stats.mul("redirect_cd_pct"))
	# Shield focus.
	if c.focus_request >= 0 and focus_cd <= 0.0 and c.focus_request != shields.focus:
		shields.set_focus(c.focus_request)
		focus_cd = float(Rules.FOCUS_COOLDOWN[size_class]) * cd_mul
		Events.cue.emit("ui", global_position)
	# Energy routing (changes the stats).
	if c.energy_request >= 0 and energy_cd <= 0.0 and c.energy_request != energy.mode:
		energy.mode = c.energy_request
		energy_cd = float(Rules.ENERGY_COOLDOWN[size_class]) * cd_mul
		stats_dirty = true
		Events.cue.emit("ui", global_position)
	# Special, repair kit, dock.
	if c.special and special_ready():
		_use_special()
	if c.use_kit:
		use_repair_kit()
	if c.dock and world != null:
		world.try_dock(self)


## Work every gun for this tick. Torpedo guns get the team's torpedo damage
## upgrade on top of the ship's damage multiplier.
func _weapons(dt: float) -> void:
	var c := controls
	var t: TeamState = world.teams[team]
	for m in mounts:
		var dm := dmg_mult
		if m.kind == Rules.W_TORP:
			dm *= 1.0 + t.torp_dmg
		m.update(dt, c.aim_point, c.fire, fire_mult, dm, range_mult, energy)


# --- specials and kits (forwarding) -----------------------------------------------------

## Use this hull's special ability now.
## Forwarding function: the real code is ShipAbilities.use_special().
func _use_special() -> void:
	ShipAbilities.use_special(self)


## True while a repair-kit drone of ours is still alive (gone drones are
## pruned from kit_drones).
## Forwarding function: the real code is ShipAbilities.has_active_kit().
func has_active_kit() -> bool:
	return ShipAbilities.has_active_kit(self)


## R: spend one repair kit from the inventory; a weak repair drone heals us.
## Forwarding function: the real code is ShipAbilities.use_repair_kit().
func use_repair_kit() -> void:
	ShipAbilities.use_repair_kit(self)


## Called once by Combat.kill() when we are destroyed: remove our escort and
## kit drones quietly (no bounty for them) and show an explosion.
func on_killed(_info: DamageInfo) -> void:
	for d in escort_drones + kit_drones:
		if is_instance_valid(d) and d.alive:
			world.combat.kill_silently(d)
	escort_drones.clear()
	kit_drones.clear()
	world.effects.explosion(global_position, radius, Palette.team(team))
