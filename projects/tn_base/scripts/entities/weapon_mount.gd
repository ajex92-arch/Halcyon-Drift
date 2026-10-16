class_name WeaponMount
extends RefCounted
## WHAT THIS IS: one gun bolted onto a unit (a pilot ship, minion, turret,
## mothership, repair bay, derelict or snub fighter), together with where it
## sits, which way it points and how soon it can fire again.
##
## HOW IT WORKS: a gun is mounted in one of three ways:
##   FIXED   fires straight along the hull's nose. Strike craft aim by
##           turning the whole ship.
##   TURRET  swings toward the owner's aim point, but only within its `arc`.
##           Big ships use these: the pilot aims a reticle while the hull
##           faces wherever positioning demands.
##   AUTO    picks its own targets (flak and point defense). This is what
##           lets a well-positioned big ship shred whatever comes at it.
##           The target picking lives in WeaponMountTargeting
##           (weapon_mount_targeting.gd).
## Every tick (one small step of the game, 60 per second) the owner calls
## update() with its aim point, its trigger and its multipliers. The gun
## turns, waits for its cooldown (`cd`), pays for the shot from the owner's
## battery (EnergyPool), and fires:
##   - Projectile guns spawn rounds through world.projectiles (_shoot).
##   - Beams deal a little damage every tick through world.combat.beam()
##     (_update_beam). "Burst" beams (the ion cannon) fire in fixed bursts.
## Minions, turrets and monsters reuse this class with a null EnergyPool,
## so their shots are free.
##
## Angles are in radians: a full turn is TAU (2 * PI, about 6.28), so one
## radian is about 57 degrees.
##
## WHO USES IT: Ship (from its hull's "mounts" list and from modules that
## add a gun), World (when a refit adds a module gun), Minion, Turret,
## Mothership, RepairBay, Derelict and SnubFighter create mounts and call
## update(). AI pilots read reach and mount_type; Turret reads cd and def;
## UnitVisual reads world_angle() and offset; tests read the beam and
## target fields.

## Mount type: fires along the nose.
const FIXED := 0
## Mount type: swings toward the owner's aim point within its arc.
const TURRET := 1
## Mount type: picks its own targets.
const AUTO := 2
## The mount type names used in the data files ("fixed", "turret", "auto")
## turned into the numbers above.
const TYPE_IDS := {"fixed": FIXED, "turret": TURRET, "auto": AUTO}

## The unit this gun is bolted to.
var owner: Unit
## Which weapon this is: its id in Weapons (e.g. "fighter_cannon").
var weapon_id := ""
## The weapon's data from Weapons (damage, rate, speed, energy cost...).
var def: Dictionary
## The weapon kind: one of Rules.W_* (bolt, torpedo, flak...). It picks the
## damage-table row and the firing sound.
var kind := Rules.W_BOLT
## How it is mounted: FIXED, TURRET or AUTO.
var mount_type := FIXED
## Where the gun sits on the hull, in the owner's own frame (+x ahead, +y to
## the right), in world units.
var offset := Vector2.ZERO
## How far the mount can swing either side of the nose, in radians (half
## of its full swing).
var arc := 0.0
## Where the gun points right now, as an angle relative to the hull's
## facing, in radians (TURRET and AUTO; FIXED is always 0).
var angle := 0.0
## Seconds until the gun may fire again (0 or below = ready).
var cd := 0.0
## The weapon's normal reach, in world units (from Weapons.reach()).
var reach := 0.0
## True for beam weapons (continuous rays instead of rounds).
var is_beam := false
## Burst beams: seconds left in the current burst.
var beam_on := 0.0
## Burst beams: seconds left of the rest between bursts.
var beam_off := 0.0
## True while the beam is drawn and dealing damage this tick.
var beam_firing := false
## Where the beam ended this tick (world position): the first thing it hit,
## or its full length.
var beam_end := Vector2.ZERO
## A one-shot damage multiplier for the next shot or burst (the Bomber's
## Focus and the Ion ship's Capacitor Dump set it). Back to 1.0 once used.
var next_mult := 1.0
## Burst beams: the one-shot bonus locked in when the current burst
## started, so it lasts for the whole burst.
var burst_mult := 1.0
## Reach this tick after range multipliers, in world units (AUTO mounts
## drop targets that move past it).
var range_now := 0.0
## AUTO mounts: the unit we are shooting at, or null.
var target: Unit = null
## AUTO mounts: the enemy torpedo we are shooting at, as its slot number in
## world.projectiles, or -1 for none (point defense shoots torpedoes down).
var target_torp := -1
## AUTO mounts: seconds until we choose a target again (every 0.25 to 0.35 s).
var retarget_t := 0.0
## True while this mount has a valid target or a pulled trigger this tick
## (read by the AI and by tests).
var engaged := false
## How fast the gun swings (radians per second), from the weapon's data
## ("turn", 3.0 if missing). Read once in _init() instead of on every
## update (it runs for every gun on every tick).
var _turn_rate := 3.0


## Create a gun: owner `o`, weapon id `wid`, mount type name `type_name`
## ("fixed", "turret" or "auto"), position `off` on the hull, and swing
## `arc_deg` in degrees either side of the nose.
func _init(o: Unit, wid: String, type_name: String = "fixed", off: Vector2 = Vector2.ZERO, arc_deg: float = 0.0) -> void:
	owner = o
	weapon_id = wid
	def = Weapons.get_def(wid)
	kind = Weapons.kind_id(def)
	mount_type = int(TYPE_IDS[type_name])
	offset = off
	arc = deg_to_rad(arc_deg)
	reach = Weapons.reach(def)
	is_beam = bool(def.get("beam", false))
	_turn_rate = float(def.get("turn", 3.0))


## Where the gun is in the world right now (its offset turned with the hull).
func world_pos() -> Vector2:
	return owner.global_position + offset.rotated(owner.rotation)


## The direction the gun points in the world, in radians.
func world_angle() -> float:
	return owner.rotation + angle


## Per-tick update: aim, then fire if we can. `aim_point` is where the
## owner aims (used by TURRET mounts; FIXED mounts ignore it and AUTO mounts
## pick their own). `trigger` = the pilot is pressing fire. `fire_mult`
## speeds up the rate of fire, `dmg_mult` scales damage and `range_mult`
## scales reach. `energy` pays for shots (null = free shots).
func update(dt: float, aim_point: Vector2, trigger: bool, fire_mult: float, dmg_mult: float, range_mult: float, energy: EnergyPool) -> void:
	# Step 1: count down the cooldown and reset this tick's state.
	if cd > 0.0:
		cd -= dt
	engaged = false
	var turn_rate: float = _turn_rate
	var want_local := 0.0
	var fire := false
	range_now = reach * range_mult
	var aim_at := aim_point

	# Step 2: aim, depending on how the gun is mounted.
	match mount_type:
		FIXED:
			# Nose gun: fires whenever the trigger is pulled.
			angle = 0.0
			fire = trigger
		TURRET:
			# Swing toward the aim point (never past the arc). Fire only if
			# the aim point is inside the arc (plus 0.05 rad of slack) and
			# the gun is already pointing within 0.3 rad of where it wants.
			var mp := world_pos()
			var desired := Util.ang_diff(owner.rotation, (aim_point - mp).angle())
			want_local = clampf(desired, -arc, arc)
			angle = _slew(angle, want_local, turn_rate * dt)
			fire = trigger and absf(desired) <= arc + 0.05 and absf(Util.wrap_angle(want_local - angle)) < 0.3
		AUTO:
			# Choose a target every 0.25-0.35 s (the random part spreads
			# the work over different ticks).
			retarget_t -= dt
			if retarget_t <= 0.0:
				retarget_t = 0.25 + randf() * 0.1
				WeaponMountTargeting.pick_target(self, range_now)
			# Aim at where the target will be. INF means "no target".
			var tp := WeaponMountTargeting.target_point(self)
			if tp.x != INF:
				aim_at = tp
				var mp := world_pos()
				var desired := Util.ang_diff(owner.rotation, (tp - mp).angle())
				if absf(desired) <= arc + 0.01:
					# Inside our arc: swing and fire once within 0.12 rad.
					want_local = desired
					angle = _slew(angle, want_local, turn_rate * dt)
					fire = absf(Util.wrap_angle(want_local - angle)) < 0.12
					engaged = true
				else:
					# Outside our arc: give the target up.
					target = null
					target_torp = -1

	if trigger and mount_type != AUTO:
		engaged = true

	# Step 3: beams work differently (damage every tick).
	if is_beam:
		_update_beam(dt, fire, dmg_mult * fire_mult, range_now, energy)
		return
	# Step 4: fire a round if we want to, the gun is ready and we can pay.
	if not fire or cd > 0.0:
		return
	var per_shot: float = float(def.get("energy", 0.0))
	if energy != null and per_shot > 0.0 and not energy.spend(per_shot):
		return
	# Keep the overshoot (cd is <= 0 here) so guns fire at their true rate
	# instead of rounding every interval up to whole ticks.
	cd += 1.0 / maxf(0.01, float(def["rate"]) * fire_mult)
	_shoot(dmg_mult * next_mult, range_mult, aim_at)
	next_mult = 1.0


## Turn angle `cur` toward angle `want` by at most `step` radians, the
## short way round. Returns the new angle.
func _slew(cur: float, want: float, step: float) -> float:
	var d := Util.wrap_angle(want - cur)
	return Util.wrap_angle(cur + clampf(d, -step, step))


## Fire one shot of rounds (one or more "pellets") from the gun. `dmg_mult`
## scales the damage, `range_mult` the flight time (so the reach). Homing
## rounds chase our AUTO target, or else the owner's homing_target().
func _shoot(dmg_mult: float, range_mult: float, aim_at: Vector2) -> void:
	var w := owner.world
	if w == null:
		return
	# Step 1: read the weapon's numbers.
	var a := world_angle()
	var pellets: int = int(def.get("pellets", 1))
	var spread: float = float(def.get("spread", 0.0))
	var speed: float = float(def["speed"])
	var life: float = float(def["life"]) * range_mult
	var mp := world_pos()
	# Step 2: choose what homing rounds chase.
	var homing_target: Unit = target if mount_type == AUTO else null
	if homing_target == null:
		homing_target = owner.homing_target()
	# Step 3: one round per pellet, each nudged by a random spread (twice
	# as wide for guns with more than 2 pellets). Rounds also carry 35% of
	# the owner's own speed.
	for i in pellets:
		var da := (randf() - 0.5) * spread * (2.0 if pellets > 2 else 1.0)
		var dir := Vector2.from_angle(a + da)
		var vel := dir * speed + owner.velocity * 0.35
		w.projectiles.spawn(mp + dir * 4.0, vel, life, float(def["dmg"]) * dmg_mult, kind, def, owner, homing_target)
	# Step 4: play the firing sound.
	Events.cue.emit(_cue_name(), mp)


## The name of the firing sound for our weapon kind.
func _cue_name() -> String:
	match kind:
		Rules.W_TORP:
			return "torp"
		Rules.W_FLAK:
			return "flak"
		Rules.W_SHELL:
			return "shell"
		Rules.W_PD:
			return "pd"
	return "fire"


## Beams deal damage every tick while firing. `dmg_mult` already includes
## fire_mult: energy routing, fire-rate gear, Broadside and strain scale a
## beam's damage the way they scale other guns' rate of fire. `length` is
## the beam's reach in world units; `energy` pays per second (null = free).
func _update_beam(dt: float, fire: bool, dmg_mult: float, length: float, energy: EnergyPool) -> void:
	var on_time: float = float(def.get("on", 0.0))
	var off_time: float = float(def.get("off", 0.0))
	beam_firing = false
	if beam_off > 0.0:
		beam_off -= dt
	var bonus := next_mult
	if on_time > 0.0:
		# Burst beams (ion): a trigger pull commits to a full burst, and a
		# one-shot bonus (Capacitor Dump) is latched for that whole burst.
		if beam_on <= 0.0 and fire and beam_off <= 0.0:
			beam_on = on_time
			burst_mult = next_mult
			next_mult = 1.0
		if beam_on <= 0.0:
			return
		bonus = burst_mult
		# Count the burst down; when it ends, start the rest time.
		beam_on -= dt
		if beam_on <= 0.0:
			beam_off = off_time
			burst_mult = 1.0
	elif not fire:
		return
	# Pay for this tick of beam; no energy, no beam.
	var cost: float = float(def.get("energy", 0.0)) * dt
	if energy != null and cost > 0.0 and not energy.spend(cost):
		return
	# Fire: Combat damages the first thing on the line and tells us where
	# the beam stopped; Projectiles draws it.
	beam_firing = true
	engaged = true
	var w := owner.world
	var mp := world_pos()
	var dir := Vector2.from_angle(world_angle())
	var dmg: float = float(def["dps"]) * dt * dmg_mult * bonus
	beam_end = w.combat.beam(owner, mp, dir, length, dmg, kind, bool(def.get("cuts", false)))
	w.projectiles.add_beam(mp, beam_end, owner.team, float(def.get("width", 3.0)), kind)
