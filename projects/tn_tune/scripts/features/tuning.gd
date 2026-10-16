class_name TuningFeature
extends RefCounted
## WHAT THIS IS: the balance-tuning switch board. It lets a test run change
## five balance numbers for one match, from the command line, so a sweep can
## try many settings of them without editing any game file. It exists for
## the tuning sweep (tests with --tune=...); with no --tune option nothing
## here runs and the match is exactly the normal game.
##
## HOW IT WORKS: the option is a comma-separated list of name:value pairs,
##   --tune=minion_vs_ship:0.5,soft_retreat:0.3,ms_durability:0.8,torp_vs_small:0.5,lance_mult:0.7
## Game._parse_options switches the "tune" feature on when --tune is given,
## and FeatureRegistry then calls install() once when the match is built.
## install() reads the pairs (KNOBS lists the names, normal values and the
## ranges the sweep explored). A name that is not in KNOBS, or a value that
## is not a number, only gets a warning. A value outside the hard limits
## ("min" and "max" of the knob) is moved to the nearest limit, with a
## warning. Pairs left out keep their normal value. The knobs:
##   minion_vs_ship  how hard a minion's hit lands on a pilot ship (a
##                   multiplier, normally 0.6; read by CombatScaling through
##                   the tuned number "minion_vs_ship_mult").
##   soft_retreat    the hull-plus-shield fraction under which a ship smaller
##                   than a frigate turns back (normally 0.25; read by PilotAI
##                   through "soft_retreat_below").
##   ms_durability   a multiplier on both motherships' hull and shield pools
##                   (normally 1.0). install() applies it at once: base and
##                   current hull and shield all grow or shrink by that
##                   factor, so research (which builds on the base numbers)
##                   keeps the same proportions. The shield's refill speed is
##                   not changed.
##   torp_vs_small   the damage-table cell for a torpedo hitting a small craft
##                   (normally 0.35; read by Rules.damage_mult through
##                   "torp_vs_small").
##   lance_mult      a multiplier on the Lance beam's damage against every
##                   target (normally 1.0; read by Rules.damage_mult through
##                   "lance_mult").
## Every knob that was set is recorded in Game.usage as "tune_<name>_x1000"
## (the value times 1000, so 0.55 is 550), which the fun probe prints in its
## FUN_JSON line, and install() prints one "tune: ..." line. The module draws
## no random numbers and creates no units.
##
## WHO USES IT: FeatureRegistry installs it when --tune is given. The readers
## named above (CombatScaling, PilotAI, Rules.damage_mult) ask
## Rules.tune() or Game.tunables, which are empty without --tune.

## The knobs: name -> {"tunable": the Game.tunables name the game code reads
## ("" = install() changes the motherships directly), "normal": today's value,
## "min" / "max": the hard limits install() enforces, "lo" / "hi": the range
## the tuning sweep explored, "what": a plain-words description}.
const KNOBS := {
	"minion_vs_ship": {"tunable": "minion_vs_ship_mult", "normal": 0.6, "min": 0.0, "max": 3.0, "lo": 0.35, "hi": 0.85,
		"what": "damage multiplier of a minion's hit on a pilot ship"},
	"soft_retreat": {"tunable": "soft_retreat_below", "normal": 0.25, "min": 0.0, "max": 0.65, "lo": 0.15, "hi": 0.45,
		"what": "hull+shield fraction under which small ships retreat"},
	"ms_durability": {"tunable": "", "normal": 1.0, "min": 0.1, "max": 5.0, "lo": 0.6, "hi": 1.4,
		"what": "multiplier on both motherships' hull and shield"},
	"torp_vs_small": {"tunable": "torp_vs_small", "normal": 0.35, "min": 0.0, "max": 3.0, "lo": 0.2, "hi": 0.8,
		"what": "damage-table cell, torpedo against small craft"},
	"lance_mult": {"tunable": "lance_mult", "normal": 1.0, "min": 0.1, "max": 3.0, "lo": 0.5, "hi": 1.1,
		"what": "multiplier on the Lance beam's damage"},
}


## Read --tune and apply it to match `world` (see HOW IT WORKS).
## FeatureRegistry calls this once at match start, when --tune was given.
static func install(world: World) -> void:
	var spec := str(Game.opt("tune", ""))
	var shown: PackedStringArray = []
	# Step 1: go through the name:value pairs.
	for pair in spec.split(",", false):
		var kv := pair.split(":")
		if kv.size() != 2 or not KNOBS.has(kv[0]) or not kv[1].is_valid_float():
			push_warning("tune: cannot use \"%s\" (use name:number with a name from TuningFeature.KNOBS); skipped" % pair)
			continue
		var name: String = kv[0]
		var knob: Dictionary = KNOBS[name]
		# Step 2: keep the value inside the hard limits.
		var value := float(kv[1])
		var clamped := clampf(value, float(knob["min"]), float(knob["max"]))
		if clamped != value:
			push_warning("tune: %s=%s is outside %s..%s; using %s" % [name, kv[1], knob["min"], knob["max"], clamped])
		value = clamped
		# Step 3: hand the number to the code that reads it.
		var tunable: String = knob["tunable"]
		if tunable != "":
			Game.tunables[tunable] = value
		else:
			_scale_motherships(world, value)
		Game.count_usage("tune_%s_x1000" % name, int(round(value * 1000.0)))
		shown.append("%s=%s" % [name, value])
	# Step 4: one line for the log, so a run shows what it was given.
	print("tune: %s" % (", ".join(shown) if not shown.is_empty() else "(nothing set)"))


## Multiply both motherships' hull and shield pools by `factor`. The base
## numbers change too, because research (MothershipGuns.apply_upgrades)
## rebuilds hull and shield from them; the current hull and shield keep
## their fraction (a full mothership stays full). The shield's refill speed
## stays as it was.
static func _scale_motherships(world: World, factor: float) -> void:
	for t in 2:
		var ms := world.mothership(t)
		if ms == null:
			continue
		ms.base_hull_max *= factor
		ms.hull_max *= factor
		ms.hull *= factor
		ms.base_shield *= factor
		ms.shields.set_max(ms.shields.max_total * factor)
