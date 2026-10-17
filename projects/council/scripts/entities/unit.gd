class_name Unit
extends CharacterBody2D
## WHAT THIS IS: the shared starting point (the "base class") of every thing
## in the game that can fight, be shot or be destroyed: pilot ships, minions,
## mining and repair drones, wards, turrets, repair bays, the motherships,
## derelict camps (the neutral "jungle monsters") and their snub fighters.
## Each of those is its own script that says "extends Unit": it gets
## everything written here for free and adds its own behaviour on top.
##
## HOW IT WORKS:
##   - Birth: World makes a unit in three steps. World._attach() gives it an
##     id number (`uid`), tells it which world it lives in and puts it into
##     the scene tree; then the unit's own setup() fills in its team, kind,
##     size and hull; then World._index() adds it to World's lists.
##   - Life: every tick (the game moves forward in small steps called ticks,
##     60 per second) World calls sim_update(dt) on every living unit, where
##     dt is the length of the step in seconds. Units must not use Godot's
##     own _physics_process: World decides who moves first.
##   - Getting hurt: Combat.apply_damage() is the only thing that lowers the
##     hull (the unit's body, its "health"). Combat scales the hit (and
##     multiplies it by this unit's incoming_mults, which feature modules
##     may fill), then calls take_hit() here: the shield zone facing the
##     attacker soaks what it can, and the hull takes the rest.
##   - Death: when the hull reaches 0, Combat.kill() pays the bounties, calls
##     on_killed() and then World.remove_unit(), which frees the node.
##   - Moving: pilot ships use Godot's move_and_slide() (a CharacterBody2D
##     feature that slides along asteroids instead of passing through them).
##     Lighter units just set `position` directly.
##
## WHO USES IT: nearly everything. World spawns, updates and removes units;
## Combat damages and kills them (take_hit, log_damage, on_killed);
## Projectiles and Combat.beam() call hit_t(); Vision and World fill
## visible_mask and seen_mask; Economy reads damage_log and bounty_value();
## turrets and minions read aggro_time (the "aggro" rule); WeaponMount calls
## homing_target(); the HUD, minimap and AI pilots read hull_frac(),
## visible_to() and is_structure(); the AI pilots (PilotTargeting, PilotAI)
## also read total_frac(); feature modules (scripts/features/)
## fill incoming_mults and Combat reads incoming_mult_product().
##
## Functions marked "Override" are meant to be replaced: a script that
## extends Unit writes its own function with the same name, and that one runs
## instead of the plain version here.
##
## To add a new kind of unit: extend Unit, set kind / size_class / radius /
## hull in a setup function, override sim_update() and on_killed(), and
## handle its bounty in Economy.on_unit_killed().

# --- kinds of unit ---------------------------------------------------------------------

## Kind number: a pilot ship (Ship), flown by a human or an AI pilot.
const K_SHIP := 0
## Kind number: a minion (Minion), the small robot ships each mothership
## sends down the lanes in waves.
const K_MINION := 1
## Kind number: a mining drone (MiningDrone), which fetches ore (money).
const K_MINING_DRONE := 2
## Kind number: a repair drone (RepairDrone), which heals friendly units.
const K_REPAIR_DRONE := 3
## Kind number: a ward (Ward), a small vision beacon.
const K_WARD := 4
## Kind number: a turret (Turret), a gun platform that guards a lane.
const K_TURRET := 5
## Kind number: a repair bay (RepairBay), a station that repairs ships.
const K_BAY := 6
## Kind number: a mothership (Mothership), each team's huge home ship.
const K_MOTHERSHIP := 7
## Kind number: a derelict camp (Derelict), a neutral "jungle monster" ship.
## KIND_NAMES calls it "derelict".
const K_MONSTER := 8
## Kind number: a snub fighter (SnubFighter), a small neutral fighter that a
## Derelict Carrier launches.
const K_SNUB := 9
## Kind number: a pilot's personal ore extractor (PilotExtractor; only with
## the pilot_mining:extractor feature). It is in World.units but in no
## kind list.
const K_EXTRACTOR := 10
## A readable name for each kind number, in the same order as the K_*
## numbers above (KIND_NAMES[K_TURRET] is "turret"). The HUD, World's speed
## measurements and some tests print these.
const KIND_NAMES := ["ship", "minion", "mining drone", "repair drone", "ward", "turret", "repair bay", "mothership", "derelict", "snub fighter", "extractor"]

# --- who and what this unit is ---------------------------------------------------------

## This unit's id number, unique for the whole match (World.next_uid()).
## 0 until World._attach() sets it.
var uid := 0
## Which side it is on: 0 or 1 for the two teams, or Rules.NEUTRAL (2) for
## neutral units such as derelicts.
var team := Rules.NEUTRAL
## What kind of unit this is: one of the K_* numbers above.
var kind := K_SHIP
## Its size class, one of Rules.SIZE_* (small, medium, large, capital,
## structure, mothership). It picks the column of the damage table, so a
## weapon can be strong against small ships and weak against big ones.
var size_class := Rules.SIZE_SMALL
## How big it is, as a circle radius in world units (1 world unit is about
## one pixel at normal zoom). Used for hit tests and spacing.
var radius := 10.0
## Hull points left (its health). 0 means destroyed.
var hull := 100.0
## Hull points when fully repaired.
var hull_max := 100.0
## The fraction (0..1) of hull damage it shrugs off (armour). take_hit()
## never lets it go above 0.9.
var hull_resist := 0.0
## Its shields (see ShieldZones), or null for units without shields.
var shields: ShieldZones = null
## How far it can see, in world units. 0 means it lights up no fog.
var vision_radius := 0.0
## False once it is dead (or, for pilot ships, docked). Dead units are
## skipped everywhere.
var alive := true
## The name shown on screen (a pilot's callsign, for example).
var display_name := ""
## The game world it lives in (set by World._attach()).
var world: World = null

# --- who can see it --------------------------------------------------------------------

## Which teams can see this unit right now, stored as a "bitmask": a whole
## number whose binary digits are on/off switches, one per team. The switch
## for a team is the value (1 << team): 1 for team 0, 2 for team 1, so 3
## means both teams see it. World refreshes it from Vision.
var visible_mask := 0
## The same kind of bitmask, for the teams that have EVER seen this unit.
## Structures a team has seen once stay drawn as "ghosts" in its fog.
var seen_mask := 0

# --- memory of fights ------------------------------------------------------------------

## Who hurt us: attacker uid -> [total damage, match time of their last hit
## in seconds, their PilotProfile or null]. Economy uses it to share kill
## rewards (assists); a Derelict uses it to remember who attacked it.
var damage_log := {}
## Match time (seconds) of the last hit of any kind. -999 means never.
var last_damage_time := -999.0
## Match time (seconds) of the last hit that got through to the hull.
## -999 means never.
var last_hull_damage_time := -999.0
## Match time (seconds) when this unit last damaged an enemy pilot SHIP
## (Combat sets it). Turrets and minions near the victim then prefer to
## shoot this unit: the "aggro" rule. -999 means never.
var aggro_time := -999.0
## Where that victim ship was at the time (world position), so turrets and
## minions can tell whether the attack happened near them.
var aggro_victim_pos := Vector2.ZERO
## Seconds left on the white "I was hit" flash (only for drawing).
var flash := 0.0
## Feature hook: extra multipliers on all the damage this unit takes, by
## name: key -> multiplier (0.2 = takes a fifth of the damage, 1.25 = a
## quarter more). Empty (the default) = normal damage. Combat.apply_damage()
## multiplies every hit on this unit by all of them together
## (incoming_mult_product()), right after the damage rules and before the
## shields, so they also count for assists and damage totals. A feature
## module adds one with  unit.incoming_mults["fortify"] = 0.2  and takes it
## away with  unit.incoming_mults.erase("fortify").  (incoming_mult()
## below is a different thing: a unit's own effects, such as Brace.)
var incoming_mults := {}


## Per-tick simulation: move, think, shoot. World calls it every tick on
## every living unit. Override.
func sim_update(_dt: float) -> void:
	pass


## Called once by Combat.kill() just before the unit is removed. Override to
## drop loot, spawn effects or tell owners.
func on_killed(_info: DamageInfo) -> void:
	pass


## A multiplier on every incoming hit (e.g. 0.62 while a Flak ship's Brace
## is on). 1.0 = normal damage. Ship overrides it; take_hit() applies it.
func incoming_mult() -> float:
	return 1.0


## All of this unit's feature multipliers (incoming_mults) multiplied
## together: 1.0 when there are none. Combat.apply_damage() multiplies
## every hit on this unit by it (it only asks when the list is not empty).
func incoming_mult_product() -> float:
	var m := 1.0
	for key in incoming_mults:
		m *= float(incoming_mults[key])
	return m


## Extra shield resistance, as a 0..1 fraction (energy routing gives ships
## this). Override.
func shield_resist_bonus() -> float:
	return 0.0


## How much this unit is worth in credits when someone kills it (used for
## kill bounties). Override for ships.
func bounty_value() -> float:
	return 0.0


## The unit a freshly fired homing torpedo should chase, or null for none.
## Pilot ships and turrets override it. WeaponMount asks this when it fires.
func homing_target() -> Unit:
	return null


## The direction the unit's nose points, as a length-1 arrow (vector).
func forward() -> Vector2:
	return Vector2.from_angle(rotation)


## Hull left as a 0..1 fraction (1 = undamaged). 0 if hull_max is 0.
func hull_frac() -> float:
	return hull / hull_max if hull_max > 0.0 else 0.0


## Shield points left over all zones (0 for units without shields).
func shield_total() -> float:
	return shields.total() if shields != null else 0.0


## Hull plus shields left as a 0..1 fraction of their maximum together
## (1 = undamaged). Unlike hull_frac(), which stays at 1 until the shields
## are gone, this one falls as soon as the shields do. 0 if the unit has
## neither hull nor shields.
func total_frac() -> float:
	var most := hull_max + (shields.max_total if shields != null else 0.0)
	return (hull + shield_total()) / most if most > 0.0 else 0.0


## True for buildings: turrets, repair bays and motherships.
func is_structure() -> bool:
	return kind == K_TURRET or kind == K_BAY or kind == K_MOTHERSHIP


## Can the team `viewer_team` see this unit right now? Our own team (and a
## viewer team below 0, meaning "see everything") always can; others check
## their switch in visible_mask.
func visible_to(viewer_team: int) -> bool:
	if viewer_team < 0 or viewer_team == team:
		return true
	return (visible_mask & (1 << viewer_team)) != 0


## Hit test for a fast-moving round. A round moves from point `a` to point
## `b` in one tick; a "swept" test checks the whole line between them, so a
## fast round can't skip past us. Returns where along that line it first
## touches us, as a 0..1 fraction (0 = at a, 1 = at b), or -1 for a miss.
## `pad` (world units) makes us a little bigger. A circle by default; the
## mothership overrides this with its long hull.
func hit_t(a: Vector2, b: Vector2, pad: float) -> float:
	return Util.seg_circle_t(a, b, global_position, radius + pad)


## Take a hit that Combat has already scaled. The shield zone facing the
## attacker soaks first; the hull takes what is left after its resistance.
## Returns the damage the hull took.
func take_hit(info: DamageInfo, amount: float) -> float:
	if not alive:
		return 0.0
	# Step 1: special effects (e.g. Brace) change the size of the hit, and
	# we start the hit flash.
	amount *= incoming_mult()
	flash = 0.09
	var raw := amount
	# Step 2: work out where the attacker is "in our own frame" (as if we
	# always faced right), pick the shield zone on that side, and let it
	# soak the hit. `raw` becomes what got past the shield.
	if shields != null and shields.max_total > 0.0:
		var local := (info.from_pos - global_position).rotated(-rotation)
		var zone := ShieldZones.zone_for_local(local)
		raw = shields.absorb(zone, amount, shield_resist_bonus())
	# Step 3: armour lowers what reaches the hull, then the hull takes it.
	var hull_dmg := raw * (1.0 - clampf(hull_resist, 0.0, 0.9))
	if hull_dmg > 0.0:
		hull -= hull_dmg
		last_hull_damage_time = _now()
	last_damage_time = _now()
	return hull_dmg


## Repair the hull by `amount` points (never above hull_max). Returns how
## much was actually repaired. Dead units can't be healed.
func heal(amount: float) -> float:
	if not alive or amount <= 0.0:
		return 0.0
	var before := hull
	hull = minf(hull_max, hull + amount)
	return hull - before


## Remember who hurt us and how much (for assists, derelict rewards and
## turret bounties). Hits with no known source (uid below 0) are ignored.
func log_damage(info: DamageInfo, amount: float) -> void:
	if info.source_uid < 0:
		return
	# Add to the attacker's running total and stamp the time; keep the
	# pilot's profile once we know it.
	var e: Array = damage_log.get(info.source_uid, [0.0, 0.0, null])
	e[0] = float(e[0]) + amount
	e[1] = _now()
	if info.source_profile != null:
		e[2] = info.source_profile
	damage_log[info.source_uid] = e


## The match clock in seconds (0 if we are not in a world yet).
func _now() -> float:
	return world.time if world != null else 0.0
