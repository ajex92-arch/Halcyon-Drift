class_name BomberRoleFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "bomber_role" rule variant (the
## optional carry-overs of the combat_roles fork, from the AI deep dive:
## the Bombers are the whole bottom lane, kill almost nothing and do no
## torpedo damage to a mothership). Two independent changes, chosen by the
## value of the variant ("seats", "torp" or "both"):
##   seats  the pilots in seats 6 and 10 (the two Bomber seats besides seat
##          2) fly Fighters instead of Bombers, on both teams. Seat 2 keeps
##          the Bomber. Hull choice is scripted per seat in
##          PilotShopping.HULL_PREF, so this changes the wish list of those
##          two seats to just the Fighter (BomberRoleShopping).
##   torp   the Bomber pilots, who normally leave small craft alone in the
##          lane (PilotTargeting.pick_target), also fire at a small enemy PILOT
##          ship when they have nothing else to shoot (BomberRoleTargeting).
##          Unless the damage modifiers are removed, a PILOT's torpedo then
##          also does x0.6 to small craft instead of x0.35 (the "torp" row of
##          the damage table in Rules.DAMAGE; the new number is the tuned
##          number "torp_small_mult", Rules.tune()), so the new number
##          matters. Minion and turret torpedoes keep x0.35: only the pilots'
##          weapons change, so this does not touch how hard minions hit
##          pilots (that belongs to the minion_cap variant). With the damage
##          modifiers removed there is no such number, and "torp" only
##          changes the targeting.
##
## HOW IT WORKS: install() looks at the value. For "seats" it gives seats 6
## and 10 the new shopping part (RoleBrains); each time one of them swaps a
## Bomber for a Fighter it counts "bomber_seat_swaps". For "torp" it gives
## every Bomber brain the new targeting part and, unless the damage
## modifiers are removed, sets the tuned number and adds a rule to
## RoleScaling (the damage calculator with plug-in rules) that scales a
## pilot's torpedo hit on a small target by 0.6 / 0.35, counted as
## "torpedo_small_hits". "both" does both.
##
## WHO USES IT: FeatureRegistry installs it for --variant=bomber_role:seats,
## :torp or :both. BomberRoleShopping counts the swaps.

## The variant key this module belongs to.
const KEY := "bomber_role"
## The pilot seats (PilotProfile.slot) that fly Fighters under "seats".
const SWAP_SEATS := [6, 10]
## A pilot torpedo's damage multiplier against small craft under "torp"
## (the ordinary game has 0.35). Used only while the damage modifiers are
## kept.
const TORP_SMALL_MULT := 0.6

## The match.
var world: World
## True when the "seats" change is on.
var _seats := false
## True when the "torp" change is on.
var _torp := false
## Seconds since the AI parts were last checked.
var _t := 0.0


## Plug the feature into match `w` (see HOW IT WORKS). FeatureRegistry calls
## it once at match start.
func install(w: World) -> void:
	world = w
	var value := Game.variant(KEY)
	_seats = value == "seats" or value == "both"
	_torp = value == "torp" or value == "both"
	if not _seats and not _torp:
		push_warning("bomber_role: unknown value \"%s\" (use seats, torp or both); nothing changed" % value)
		return
	# The torpedo number is a damage modifier: no tuned number and no rule
	# when the damage modifiers are removed.
	if _torp and not Rules.damage_modifiers_removed():
		Game.tunables["torp_small_mult"] = TORP_SMALL_MULT
		RoleScaling.attach(w).hooks.append(Callable(self, "_damage"))
	w.tick_hooks.append(Callable(self, "_tick"))
	_brains()


## Tick hook: every half second make sure every brain has its new parts.
func _tick(dt: float) -> void:
	_t += dt
	if _t < RoleBrains.CHECK_EVERY:
		return
	_t = 0.0
	_brains()


## Give the brains the parts this value of the variant needs.
func _brains() -> void:
	if _seats:
		RoleBrains.ensure(world, "shopping", BomberRoleShopping, SWAP_SEATS)
	if _torp:
		RoleBrains.ensure(world, "targeting", BomberRoleTargeting)


## The torpedo rule (only plugged in while the damage modifiers are kept): a
## torpedo fired by a pilot, hitting a small target, does the tuned multiplier
## ("torp_small_mult", 0.6) instead of the table's 0.35.
func _damage(target: Unit, info: DamageInfo, amount: float) -> float:
	if info.kind != Rules.W_TORP or not info.source_is_pilot or target.size_class != Rules.SIZE_SMALL:
		return amount
	Game.count_usage("torpedo_small_hits")
	return amount * float(Rules.tune("torp_small_mult", 0.35)) / Rules.damage_mult(Rules.W_TORP, Rules.SIZE_SMALL)
