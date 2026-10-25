class_name MsSoftFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "ms_soft" rule variant: a softer
## mothership (docs/FUN_PLAN.md section 5, endgame_closure fork, idea B8).
## REQ-CHANGE: "The mothership should have a lot of health", "weak to large
## ships" and the (barely) win against frigates. It does not block anything:
## its tests/ms_duel.gd table (winners and hull left) is reported.
##
## HOW IT WORKS: the variant has three values besides "off" (the default):
##   "hull"     both motherships have 0.75 times their hull (12,000 instead of
##              16,000 before research). Research and the late-game setup
##              build on the smaller base, so every later hull is 25% smaller.
##   "shield"   both motherships have 0.5 times their shield (3,000 instead of
##              6,000 before research); its refill speed is unchanged.
##   "mult"     large and capital pilot ships hurt a mothership x3.0 instead
##              of x2.0 (Rules.MOTHERSHIP_ATTACKER). It uses the tuned number
##              "mothership_attacker_large" (read by CombatScaling), not
##              incoming_mults, which would also change every other attacker.
##              The x2.0 attacker-size rule is a damage modifier: with the
##              damage modifiers removed there is nothing to raise, so "mult"
##              changes nothing then (the value is still accepted).
## The AI needs no rule: the admiral sieges and the pilots attack exactly as
## before, they just finish the job sooner. Usage: Game.usage
## "ms_soft_hull_damage" counts the hull points the motherships lose under
## the changed numbers (a tick hook measures how much each mothership's
## hull fell since the last tick). The module draws no random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=ms_soft:hull,
## shield or mult; for hull and shield it runs through World.tick_hooks.

## The variant key this module belongs to.
const KEY := "ms_soft"
## Hull multiplier of "hull".
const HULL_FACTOR := 0.75
## Shield multiplier of "shield".
const SHIELD_FACTOR := 0.5
## The new damage multiplier of "mult" for large and capital attackers (used
## only while the damage modifiers are kept).
const LARGE_MULT := 3.0

## The world we belong to.
var world: World
## Hull points each mothership had at the last tick, by team.
var _last_hull := [0.0, 0.0]
## Hull damage not yet put into Game.usage (the usage counter takes whole
## numbers), by team.
var _owed := [0.0, 0.0]


## Make the softer mothership for match `w`. FeatureRegistry calls this once
## at match start. An unknown value only gets a warning.
func install(w: World) -> void:
	var value := Game.variant(KEY)
	world = w
	match value:
		"hull":
			# Step 1: smaller base hull (research uses it), same hull fraction.
			for t in 2:
				var ms := w.mothership(t)
				ms.base_hull_max *= HULL_FACTOR
				ms.hull_max *= HULL_FACTOR
				ms.hull *= HULL_FACTOR
		"shield":
			# Step 2: smaller base shield (research uses it), same fill.
			for t in 2:
				var ms := w.mothership(t)
				ms.base_shield *= SHIELD_FACTOR
				ms.shields.set_max(ms.shields.max_total * SHIELD_FACTOR)
		"mult":
			# Step 3: the tuned number CombatScaling reads (it reads none when
			# the damage modifiers are removed, so there is nothing to set).
			if not Rules.damage_modifiers_removed():
				Game.tunables["mothership_attacker_large"] = LARGE_MULT
		_:
			push_warning("ms_soft: unknown value \"%s\" (use off, hull, shield or mult); nothing changed" % value)
			return
	for t in 2:
		_last_hull[t] = w.mothership(t).hull
	w.tick_hooks.append(_tick)


## One tick (World.tick_hooks): count the hull the motherships lost since the
## last tick as "ms_soft_hull_damage" (a gain, from repair or a late-game
## refill, counts as 0).
func _tick(_dt: float) -> void:
	for t in 2:
		var ms := world.mothership(t)
		if ms == null or not ms.alive:
			continue
		_owed[t] += maxf(0.0, _last_hull[t] - ms.hull)
		_last_hull[t] = ms.hull
		if _owed[t] >= 1.0:
			var whole := int(_owed[t])
			Game.count_usage("ms_soft_hull_damage", whole)
			_owed[t] -= float(whole)
