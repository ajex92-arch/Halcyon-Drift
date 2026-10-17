class_name CombatScaling
extends RefCounted
## WHAT THIS IS: the damage calculator. It turns the raw damage of a hit
## into the final damage, using all of the game's damage rules. A part of
## Combat (steps 1-4 of Combat.apply_damage), kept in its own file.
##
## HOW IT WORKS: start from the raw damage in the DamageInfo note, then
## multiply, in this order:
##   1. the damage table, Rules.DAMAGE[weapon kind][target size class]: for
##      example torpedoes do x1.6 to large ships but only x0.35 to small
##      ones. Against SMALL targets also the weapon's small_bonus (the
##      fighter's twin autocannon has 1.25).
##   2-3. one special rule, picked by what the target is:
##      - a mothership: x0.5 from minions (Rules.MOTHERSHIP_MINION_MULT);
##        from anyone else, by the attacker's size
##        (Rules.MOTHERSHIP_ATTACKER: small x0.3, medium x0.8, large and
##        capital x2.0, others x1.0). So strike craft barely scratch it and
##        big ships tear it apart.
##      - a turret: x0.35 from minions (Rules.TURRET_MINION_MULT). From a
##        pilot, x0.3 when no minion of the pilot's team is within 1800
##        world units of the turret (TurretData.BACKDOOR_MULT and
##        BACKDOOR_RADIUS). This "backdoor protection" means turrets must
##        be pushed together with a minion wave.
##      - a pilot ship hit by a minion: x0.6 (Rules.MINION_VS_SHIP_MULT;
##        playtest: minions were the top killer of pilots).
##      - a minion hit by a minion: x1.8 (Rules.MINION_VS_MINION_MULT;
##        playtest: at x1 wave clashes took about 40 s and waves piled up).
##   4. a torpedo hitting a "painted" ship (Ship.paint_t above 0): x1.3
##      (Combat.PAINT_BONUS).
##
## WHO USES IT: only Combat.apply_damage(), through Combat.scaling.

## The world (we search its spatial hash for minions near a turret).
var world: World
## A reusable list that the spatial hash fills for the backdoor check. It
## must not be the list CombatBeamArea uses: apply_damage() runs inside
## area()'s loop over that list, and this check must not overwrite it.
var _scratch_backdoor: Array = []


## Remember the world. Combat makes this part once.
func _init(w: World) -> void:
	world = w


## The final damage of hit `info` on `target`, after the rules 1-4 above.
## When it comes out as 0 or less (for example when the raw damage was 0),
## Combat ignores the hit.
func final_amount(target: Unit, info: DamageInfo) -> float:
	# Step 1: the damage table, and the bonus against small targets.
	var tc := target.size_class
	var amount := info.amount * Rules.damage_mult(info.kind, tc)
	if tc == Rules.SIZE_SMALL:
		amount *= info.small_bonus
	# Steps 2-3: at most one special rule, by what the target is.
	if target.kind == Unit.K_MOTHERSHIP:
		if info.source_is_minion:
			amount *= Rules.MOTHERSHIP_MINION_MULT
		else:
			amount *= float(Rules.MOTHERSHIP_ATTACKER[clampi(info.source_size, 0, 6)])
	elif target.kind == Unit.K_TURRET:
		# Backdoor protection: only checked for pilots (the minion search
		# is skipped for everyone else).
		if info.source_is_minion:
			amount *= Rules.TURRET_MINION_MULT
		elif info.source_is_pilot and not friendly_minion_near(target.global_position, info.source_team):
			amount *= TurretData.BACKDOOR_MULT
	elif target.kind == Unit.K_SHIP and info.source_is_minion:
		amount *= Rules.MINION_VS_SHIP_MULT
	elif target.kind == Unit.K_MINION and info.source_is_minion:
		amount *= Rules.MINION_VS_MINION_MULT
	# Step 4: torpedoes hurt painted ships more.
	if info.kind == Rules.W_TORP and target is Ship and (target as Ship).paint_t > 0.0:
		amount *= Combat.PAINT_BONUS
	return amount


## True if a live minion of team `team` is within
## TurretData.BACKDOOR_RADIUS (1800 world units) of point `pos`.
func friendly_minion_near(pos: Vector2, team: int) -> bool:
	for u: Unit in world.unit_hash.query(pos, TurretData.BACKDOOR_RADIUS, _scratch_backdoor):
		if u.kind == Unit.K_MINION and u.team == team and u.alive and u.global_position.distance_to(pos) < TurretData.BACKDOOR_RADIUS:
			return true
	return false
