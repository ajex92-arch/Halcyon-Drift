class_name Combat
extends RefCounted
## WHAT THIS IS: the one place where damage is dealt. Every hit in the game
## (rounds, beams, blasts, crashes into rocks) goes through apply_damage(),
## and every death that pays a reward goes through kill(). DESIGN.md A5,
## A9, B1.
##
## HOW IT WORKS: apply_damage(target, info) takes a DamageInfo note (who
## hit, with what weapon, how hard) and:
##   1-4. works out the final damage with all the damage rules
##        (CombatScaling, in combat_scaling.gd):
##        1. the damage table, Rules.DAMAGE[weapon kind][target size], and
##           the weapon's bonus against small targets;
##        2. motherships: an extra multiplier by attacker size; minions x0.5;
##        3. turrets: minions x0.35; pilots x0.3 when no minion of their
##           own team is near the turret ("backdoor protection"). Pilot
##           ships take x0.6 from minions; minions take x1.8 from minions
##           (so wave clashes end fast);
##        4. "painted" ships take +30% from torpedoes;
##      then the two feature hooks, which do nothing unless a feature
##      module (scripts/features/, see FeatureRegistry) set them:
##        - minion_scale_hook may give a minion's hit a different strength
##          against this one target (_rescale_minion_hit);
##        - the target's own incoming_mults (Unit) multiply the hit;
##   5. target.take_hit(): the shield zone facing the attacker soaks the
##      hit first, the hull takes the rest (and the unit flashes white);
##   6. bookkeeping: the target's damage log (for assists), the shooting
##      pilot's damage total, the turret "aggro" marker, a sound cue and,
##      for probes only, the Events.damage_applied signal
##      (emit_damage_events);
##   7. if the hull is at 0: kill() pays the rewards (Economy), tells
##      everyone (Events), lets the unit react (on_killed) and removes it
##      (World.remove_unit).
##
## Two more ways to find who gets hurt live in CombatBeamArea
## (combat_beam_area.gd): beam() for continuous beams (the first thing on a
## straight line) and area() for blasts such as flak bursts (every enemy in
## a circle, less at the edge).
##
## WHO USES IT: WorldSetup makes it (World.combat). ProjectilesImpact sends
## the hits of rounds (apply_damage, area); WeaponMount fires beams (beam);
## ShipFlight sends crash damage (apply_damage). kill_silently() takes
## units away with no reward: WorldHangar (drones of a ship that docks),
## AdmiralCommand (an old ward replaced by a new one), RepairBay and Ship
## (their drones when they die), RepairDrone and SnubFighter (themselves).
## The ui_tour test calls kill(); the support_probe test calls
## apply_damage(). Feature modules set minion_scale_hook; the fun probe
## turns on emit_damage_events.

## How much more damage a torpedo does to a "painted" ship: x1.3, that is
## +30%. A Support ship paints enemies (Ship.paint_t, set by WorldSupport).
const PAINT_BONUS := 1.3

## The world (we read its clock and remove dead units from it).
var world: World
## The part that works out the final damage (combat_scaling.gd).
var scaling: CombatScaling
## The part for beams and blasts (combat_beam_area.gd).
var beam_area: CombatBeamArea
## Measurement only: when true, every applied hit sends
## Events.damage_applied(target, info, amount, hull damage). False by
## default; only probes turn it on (tests/fun_probe.gd sets
## world.combat.emit_damage_events = true). Nothing in the game listens,
## so the match plays the same either way.
var emit_damage_events := false
## Feature hook: a different strength for a minion's hit against one
## target. Empty (the default) = no change. A feature module sets it to a
## function  f(minion: Minion, target: Unit, scale: float) -> float.  It
## gets the minion's own strength multiplier (Minion.stat_scale: match-time
## growth x Reinforced Waves research), which is already inside the hit's
## damage, and returns the multiplier the hit should use against `target`
## instead (return `scale` itself for no change). Example: cap it at 1.15
## against pilot ships. The real work: _rescale_minion_hit().
var minion_scale_hook := Callable()


## Remember the world and make the two parts. WorldSetup calls this once.
func _init(w: World) -> void:
	world = w
	scaling = CombatScaling.new(w)
	beam_area = CombatBeamArea.new(self)


## Hurt `target` with the hit described by `info` (see steps 1-7 at the top
## of this file). Returns the damage the hull took: 0 when the shields
## soaked it all, or when nothing happened. Missing and dead targets are
## ignored.
func apply_damage(target: Unit, info: DamageInfo) -> float:
	if target == null or not is_instance_valid(target) or not target.alive:
		return 0.0
	# Steps 1-4: the final damage after every rule (CombatScaling).
	var amount := scaling.final_amount(target, info)
	# The feature hooks (both are skipped unless a feature module set
	# them): a minion's hit may get another strength against this target,
	# and the target may take more or less damage (Unit.incoming_mults).
	if info.source_is_minion and minion_scale_hook.is_valid():
		amount = _rescale_minion_hit(target, info, amount)
	if not target.incoming_mults.is_empty():
		amount *= target.incoming_mult_product()
	if amount <= 0.0:
		return 0.0
	# Step 5: shields first, then the hull.
	var hull_dmg := target.take_hit(info, amount)
	# Step 6: remember who hurt the target (for assists), and add to the
	# shooting pilot's damage total.
	target.log_damage(info, amount)
	if info.source_profile != null:
		(info.source_profile as PilotProfile).damage_done += amount
	# Turret aggro rule: remember that this attacker hurt a pilot ship, when
	# and where. Turrets and minions near the victim then prefer to shoot it.
	if target.kind == Unit.K_SHIP and info.source != null and is_instance_valid(info.source):
		info.source.aggro_time = world.time
		info.source.aggro_victim_pos = target.global_position
	# The sound cue (Sfx plays it): "hit" when the hull was hurt,
	# "shield_hit" when the shields took it all.
	if hull_dmg > 0.0:
		Events.cue.emit("hit", target.global_position)
	else:
		Events.cue.emit("shield_hit", target.global_position)
	# Measurement only (probes): announce the applied hit, before any death.
	if emit_damage_events:
		Events.damage_applied.emit(target, info, amount, hull_dmg)
	# Step 7: no hull left, so the target dies.
	if target.hull <= 0.0:
		kill(target, info)
	return hull_dmg


## Feature hook helper: the damage `amount` of a minion's hit (`info`) on
## `target`, re-scaled with minion_scale_hook. The minion's own strength
## multiplier (its stat_scale) is already inside the damage (its guns fire
## with it), so it is divided out here and the hook's answer is multiplied
## in. Nothing changes when the minion that fired is already gone (it died
## while its round was flying) or when the hook gives back the same
## multiplier.
func _rescale_minion_hit(target: Unit, info: DamageInfo, amount: float) -> float:
	# Step 1: the minion that fired, and the strength its hit carries.
	var m := info.source as Minion
	if m == null or m.stat_scale <= 0.0:
		return amount
	# Step 2: ask the hook for the strength to use against this target.
	var new_scale := float(minion_scale_hook.call(m, target, m.stat_scale))
	if new_scale == m.stat_scale:
		return amount
	# Step 3: swap the minion's strength for the new one.
	return amount / m.stat_scale * new_scale


## Destroy `target` with every consequence: mark it dead with 0 hull, pay
## the kill rewards (Economy.on_unit_killed), send the unit_killed event,
## let the unit react (on_killed: explosions, dropping its drones) and
## remove it from the world. `info` is the killing blow.
## Does nothing if the target is already dead.
func kill(target: Unit, info: DamageInfo) -> void:
	if not target.alive:
		return
	target.alive = false
	target.hull = 0.0
	Economy.on_unit_killed(world, target, info)
	Events.unit_killed.emit(target, info)
	target.on_killed(info)
	world.remove_unit(target)


## Take `target` away with no reward, no events and no on_killed(), for
## units that leave the game quietly: an expired kit drone, a snub fighter
## back home, drones whose owner died or docked, an old ward. Does nothing
## if it is already dead.
func kill_silently(target: Unit) -> void:
	if not target.alive:
		return
	target.alive = false
	world.remove_unit(target)


## A continuous beam from `from` in direction `dir` (a unit-length vector),
## `length` world units long, fired by `src`. It damages the first enemy
## unit on its line (or chips an asteroid, for a cutting beam). Returns the
## point where the beam stops. The real code is CombatBeamArea.beam().
func beam(src: Unit, from: Vector2, dir: Vector2, length: float, dmg: float, kind: int, cuts: bool) -> Vector2:
	return beam_area.beam(src, from, dir, length, dmg, kind, cuts)


## A blast at `pos` with radius `r` (world units) that hurts everyone not on
## team `exclude_team`: full damage within half the radius, half at the
## edge. The real code is CombatBeamArea.area().
func area(src_info: DamageInfo, pos: Vector2, r: float, exclude_team: int) -> void:
	beam_area.area(src_info, pos, r, exclude_team)
