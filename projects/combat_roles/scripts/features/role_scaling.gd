class_name RoleScaling
extends CombatScaling
## WHAT THIS IS: the damage calculator (CombatScaling) with a list of extra
## rules that feature modules can plug in. The combat_roles features use it
## for the rules that depend on WHO hit WHAT and from WHERE: the Lance's
## rear-shield bonus (LanceRoleFeature), the energy-routing overcharge
## (RoutingPayoffFeature) and the torpedo change (BomberRoleFeature).
##
## HOW IT WORKS: it is a copy of CombatScaling that does exactly what the
## original does (final_amount() asks the original through super), and then
## hands the answer to every function in `hooks`, one after the other, in
## the order they were added. Each hook gets the target, the hit's note
## (DamageInfo) and the damage so far, and returns the new damage. With no
## hooks it gives back the original answer, so the match plays the same.
## A feature that needs it calls RoleScaling.attach(world); the first call
## swaps this calculator into world.combat.scaling, and later calls reuse
## it.
##
## WHO USES IT: only feature modules (LanceRoleFeature,
## RoutingPayoffFeature, BomberRoleFeature) call attach() from their
## install(). Combat.apply_damage() uses it without knowing, through
## Combat.scaling. It never runs unless one of those features is on.

## The extra rules, in order. Each is a function
## f(target: Unit, info: DamageInfo, amount: float) -> float: the damage
## after the original rules comes in as `amount`, the new damage goes out.
var hooks: Array[Callable] = []


## The final damage of hit `info` on `target`: the original rules first
## (CombatScaling.final_amount), then every hook in `hooks`. A hit that is
## already at 0 damage stays 0.
func final_amount(target: Unit, info: DamageInfo) -> float:
	# Step 1: the original damage rules.
	var amount := super.final_amount(target, info)
	if amount <= 0.0 or hooks.is_empty():
		return amount
	# Step 2: the feature rules, one after the other.
	for f: Callable in hooks:
		amount = float(f.call(target, info, amount))
	return amount


## Put a RoleScaling into match `w` (once) and return it. The first call
## swaps it in for world.combat.scaling; any later call returns the same
## one, so several features share it.
static func attach(w: World) -> RoleScaling:
	var current := w.combat.scaling
	if current is RoleScaling:
		return current as RoleScaling
	var rs := RoleScaling.new(w)
	w.combat.scaling = rs
	return rs
