class_name LanceRoleFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "lance_role" rule variant (idea
## E3 of the combat_roles fork): the Lance Fighter hunts big ships that have
## lost their escort. A Lance's beam hits a LARGE or CAPITAL ship x1.35 as
## hard when it lands in the ship's REAR shield zone (the 90 degrees behind
## its tail), where its big guns cannot turn far enough to answer (a damage
## modifier: not while the damage modifiers are removed). A Lance pilot that
## sees such a ship alone and close goes round to its tail, whatever the
## switch says.
##
## HOW IT WORKS: three parts.
##   1. The damage rule (only while the damage modifiers are kept; with them
##      removed this part is not installed). install() adds a function to the
##      match's RoleScaling (the damage calculator with plug-in rules). _damage()
##      multiplies a beam hit (weapon kind Rules.W_LANCE) on a pilot ship
##      of size LARGE or CAPITAL by REAR_MULT (1.35) when the shield zone
##      that takes the hit is the rear one (ShieldZones.zone_for_local, the
##      same test the game uses to pick the zone). Each such hit is counted
##      in Game.usage as "rear_lance_hits". No gun arc is changed.
##   2. The hunting AI. A Lance pilot (the lancer before 20:00, and the
##      junglers) thinks as before, and then hunt() looks for prey: a visible
##      enemy big ship within HUNT_RANGE (6,000) that is "isolated" (support
##      0 under the escort_pd variant of this fork; without that variant,
##      no friend of the prey, pilot or minion, within 2,500 of it). If it
##      finds one it makes it the pilot's target with the intent "prey" and
##      flies toward the prey's tail. It only hunts with at least 60% hull
##      and never drops a pilot it is already fighting. Each new prey is
##      counted in Game.usage as "lance_prey_picks".
##   3. The approach (LanceRoleCombat). When the Lance is close it circles
##      the prey at RING_GAP from its hull, boosting, until it is behind
##      it (a big ship turns slowly, so a boosting Lance can out-turn it),
##      then fights as usual.
## The two AI parts are put in the pilots' brains by RoleBrains.
##
## WHO USES IT: FeatureRegistry installs it for --variant=lance_role:on.
## LanceRoleGoals and LanceRoleCombat call hunt() and steer_behind().

## The variant key this module belongs to.
const KEY := "lance_role"
## Damage multiplier for a Lance beam hit in the rear zone of a big ship
## (used only while the damage modifiers are kept).
const REAR_MULT := 1.35
## How far (world units) a Lance looks for isolated big ships.
const HUNT_RANGE := 6000.0
## A big ship with no friend within this many world units is isolated
## (used when the escort_pd variant is off).
const ALONE_RADIUS := 2500.0
## A Lance hunts only with at least this share of its hull left (0..1).
const MIN_HULL := 0.6
## While going round a prey the Lance keeps this far (world units) from the
## prey's hull: close enough to out-turn the big ship (the Lance boosts round
## it), far enough to stay out of reach of most of its guns.
const RING_GAP := 450.0
## How far behind the prey's tail (world units from its hull) the Lance
## heads for when it is far away.
const TAIL_GAP := 450.0
## An attacker this many radians or more away from the nose (measured in
## the prey's own frame) is in its rear zone: 135 degrees, the edge of the
## rear shield zone.
const REAR_ANGLE := 2.356

## The match.
var world: World
## Seconds since the AI parts were last checked.
var _t := 0.0
## A reusable list for spatial-hash searches.
var _scratch: Array = []


## Plug the feature into match `w`: the damage rule (unless the damage
## modifiers are removed), a tick hook and the two AI parts. FeatureRegistry
## calls it once at match start.
func install(w: World) -> void:
	world = w
	if not Rules.damage_modifiers_removed():
		RoleScaling.attach(w).hooks.append(Callable(self, "_damage"))
	w.tick_hooks.append(Callable(self, "_tick"))
	_brains()


## Tick hook: every half second make sure every brain has the two AI parts.
func _tick(dt: float) -> void:
	_t += dt
	if _t < RoleBrains.CHECK_EVERY:
		return
	_t = 0.0
	_brains()


## Give every pilot brain the Lance goals and combat parts.
func _brains() -> void:
	RoleBrains.ensure(world, "goals", LanceRoleGoals)
	RoleBrains.ensure(world, "combat", LanceRoleCombat)


## The damage rule (see HOW IT WORKS, part 1; plugged in only while the damage
## modifiers are kept): x1.35 for a Lance beam hit in the rear zone of a LARGE
## or CAPITAL pilot ship.
func _damage(target: Unit, info: DamageInfo, amount: float) -> float:
	if info.kind != Rules.W_LANCE or target.kind != Unit.K_SHIP or target.size_class < Rules.SIZE_LARGE:
		return amount
	# Which zone takes the hit: the attacker's place in the target's own frame.
	var local := (info.from_pos - target.global_position).rotated(-target.rotation)
	if ShieldZones.zone_for_local(local) != Rules.ZONE_REAR:
		return amount
	Game.count_usage("rear_lance_hits")
	return amount * REAR_MULT


## Is big enemy ship `u` alone? With the escort_pd variant on, its support
## is 0; otherwise no friend of `u` (a pilot ship or a minion of u's team)
## is within ALONE_RADIUS of it.
func is_isolated(u: Ship) -> bool:
	var esc = world.features.get(EscortPdFeature.KEY)
	if esc != null:
		var n: int = (esc as EscortPdFeature).support_n(u)
		if n >= 0:
			return n == 0
	var p := u.global_position
	for o: Unit in world.unit_hash.query(p, ALONE_RADIUS, _scratch):
		if o == u or not o.alive or o.team != u.team:
			continue
		if (o.kind == Unit.K_SHIP or o.kind == Unit.K_MINION) and o.global_position.distance_to(p) <= ALONE_RADIUS:
			return false
	return true


## The nearest isolated enemy big ship that team `ship.team` can see within
## HUNT_RANGE of `ship`, or null.
func find_prey(ship: Ship) -> Ship:
	var best: Ship = null
	var bd := HUNT_RANGE
	for u: Ship in world.ships:
		if not u.alive or u.team == ship.team or u.size_class < Rules.SIZE_LARGE or not u.visible_to(ship.team):
			continue
		var d := ship.global_position.distance_to(u.global_position)
		if d < bd and is_isolated(u):
			bd = d
			best = u
	return best


## The Lance AI (see HOW IT WORKS, part 2): called by LanceRoleGoals at the
## end of a lane or jungle think. Makes isolated big ship the target when
## the pilot is a healthy Lance with nothing better to do.
static func hunt(brain: PilotAI, ship: Ship) -> void:
	var feat = brain.world.features.get(KEY)
	if feat == null or ship.hull_id != "lance" or ship.hull_frac() < MIN_HULL:
		return
	# Only while on the lane or in the jungle, and not falling back, evading
	# or already fighting another pilot.
	if (brain.state != "lane" and brain.state != "jungle") or brain.fallback_t > 0.0 or brain.evade_t > 0.0:
		return
	var prey: Ship = (feat as LanceRoleFeature).find_prey(ship)
	if prey == null:
		return
	# A pilot we are already fighting stays our target, unless it IS the prey.
	if brain.target != null and is_instance_valid(brain.target) and brain.target.kind == Unit.K_SHIP and brain.target != prey:
		return
	# Count a new prey once.
	if brain.lock_target != prey:
		Game.count_usage("lance_prey_picks")
	brain.target = prey
	brain.lock_target = prey
	brain.intent = "prey"
	brain.goal = prey.global_position - Vector2.from_angle(prey.rotation) * (prey.radius + TAIL_GAP)


## The approach (see HOW IT WORKS, part 3): called by LanceRoleCombat after
## the normal fight steering. When the Lance's target is a big ship it is
## hunting and the Lance is not yet behind it, change the controls to fly
## round it at RING_GAP from its hull, toward its tail, and hold fire until
## the Lance is in the rear zone.
static func steer_behind(brain: PilotAI, ship: Ship) -> void:
	var feat = brain.world.features.get(KEY)
	var prey := brain.target as Ship
	if feat == null or ship.hull_id != "lance" or brain.intent != "prey" or prey == null or not prey.alive or prey.size_class < Rules.SIZE_LARGE:
		return
	if not (feat as LanceRoleFeature).is_isolated(prey):
		return
	# Where are we, in the prey's own frame (0 = dead ahead of it, +-PI = right
	# behind it)?
	var rel := (ship.global_position - prey.global_position).rotated(-prey.rotation)
	var ang := rel.angle()
	if absf(ang) >= REAR_ANGLE:
		return
	# Not behind it yet: go round the shorter way, a little further each look,
	# keeping RING_GAP off its hull.
	var step := 0.7 if ang >= 0.0 else -0.7
	var dir := Vector2.from_angle(prey.rotation + ang + step)
	var wp := prey.global_position + dir * (prey.radius + RING_GAP)
	var c := ship.controls
	c.face_point = wp
	c.aim_point = prey.global_position
	c.forward = 1.0
	c.strafe = 0.0
	c.boost = ship.can_boost and ship.energy.fraction() > 0.3
	c.fire = false
	c.special = false
