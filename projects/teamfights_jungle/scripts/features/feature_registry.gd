class_name FeatureRegistry
extends RefCounted
## WHAT THIS IS: the list of "feature modules": optional new game mechanics,
## one small script each in scripts/features/, that a match only gets when
## its rule variant is switched on. With every variant at its default
## (Rules.VARIANT_DEFAULTS) no feature is installed, so the match is
## exactly today's game.
##
## HOW IT WORKS: when a match is built, WorldSetup.build() calls install()
## once, as its very last step (after the map, teams, pilots and admirals
## exist, before the first tick). install() goes down FEATURES in order.
## For each entry it asks Game.variant(key) (set on the command line with
## --variant=key:value). The feature is "on" when that value is not empty,
## not "off" and not the key's default (is_on()). For a feature that is on,
## the registry:
##   1. makes the feature's object from its script (script.new()) and keeps
##      it in world.features[key] for the rest of the match (a feature that
##      is a Node also goes under the World);
##   2. calls its install(world), which plugs the feature into the game
##      through the hooks listed below.
## Then it warns (push_warning) about any tuned number in Game.tunables that
## no code reads (see Rules.TUNABLES), which is usually a typo, and prints
## one "features: ..." line naming the features that are on (nothing is
## printed when none are).
##
## WHO USES IT: WorldSetup.build() calls install(). Feature modules are
## listed in FEATURES. Tests and probes can read world.features to see
## which features are on.
##
## HOW A FORK ADDS A FEATURE (the example name is "slipstream"):
##   1. Choose the variant key and its values. The default value must be
##      today's game, usually "off": add  "slipstream": "off",  to
##      Rules.VARIANT_DEFAULTS, with a ## note saying what each value does.
##   2. Write scripts/features/slipstream.gd and follow docs/CODE_STYLE.md
##      (a WHAT THIS IS / HOW IT WORKS / WHO USES IT header, a ## note on
##      every function, variable and constant). It needs one of these:
##          static func install(world: World) -> void
##      or, when the feature keeps its own state (timers, lists),
##          func install(world: World) -> void
##      on the object the registry makes with new(). install() runs once
##      per match. A feature with several values (say "on" and "strong")
##      reads Game.variant("slipstream") inside install() and acts on it.
##      Give it a class_name ending in "Feature" (SlipstreamFeature) if
##      other files must call it.
##   3. Add ONE line to FEATURES below:
##          ["slipstream", preload("res://scripts/features/slipstream.gd")],
##   4. Plug in through the hooks (all empty by default) instead of
##      editing shared code where you can:
##        Game.tunables["name"] = value   change a tuned number for this
##                                        match (the names and normal
##                                        values: Rules.TUNABLES; readers
##                                        call Rules.tune())
##        unit.incoming_mults["key"] = m  that unit takes x m damage from
##                                        every hit (Combat)
##        world.combat.minion_scale_hook  how hard a minion hits one target
##        world.push_weight_hooks         how AI pilots score the enemy
##                                        turrets they might push
##        world.tick_hooks                run your own code every tick
##        Events signals                  for example unit_killed,
##                                        turret_destroyed, respawned
##        Game.count_usage("slipstream_seconds")
##                                        record that the AI (or a human)
##                                        used the mechanic; the fun probe
##                                        prints Game.usage, and a mechanic
##                                        nobody used proves nothing
##      The AI must use the mechanic, or the test matches show nothing: put
##      that AI rule in the feature too where you can, or else behind
##      world.features.has("slipstream") in the AI file.
##   5. Check: with --variant=slipstream:on the feature works and its usage
##      count is above 0; with every key at its default, tests/det_hash.gd
##      prints exactly main's hash lines (normal and --late).
## Rules for features: a feature that is off must change nothing, so none
## of its code may run, draw random numbers or create units. Several
## features may be on together; they are installed in FEATURES order. No
## feature may read another fork's variant.

## Every feature module, in install order: [variant key, the module's
## script]. A fork adds one line per feature (see the top of this file).
const FEATURES := [
	# escort_wing: with "upgrade", Escort Wing research upgrades each free
	# wave's single corvette instead of adding a second one
	# (EscortWingFeature, scripts/features/escort_wing.gd).
	["escort_wing", preload("res://scripts/features/escort_wing.gd")],
	# Fork teamfights_jungle (docs/FUN_PLAN.md section 5, fork D). All default
	# to "off". group_late = D1 (GroupLateFeature), salvage_core = D2
	# (SalvageCoreFeature), jungle_scale = D3 (JungleScaleFeature), node_persist
	# = D4 (NodePersistFeature), epic = D5 (EpicNeutralFeature; values
	# "dreadnought" and "elder"), beacons = D6 (BeaconsFeature), camp4 = D7
	# (Camp4Feature; the map change is in MapBuilderJungle), feats = D8
	# (FeatsFeature).
	["group_late", preload("res://scripts/features/group_late.gd")],
	["salvage_core", preload("res://scripts/features/salvage_core.gd")],
	["jungle_scale", preload("res://scripts/features/jungle_scale.gd")],
	["node_persist", preload("res://scripts/features/node_persist.gd")],
	["epic", preload("res://scripts/features/epic_neutral.gd")],
	["beacons", preload("res://scripts/features/beacons.gd")],
	["camp4", preload("res://scripts/features/camp4.gd")],
	["feats", preload("res://scripts/features/feats.gd")],
]


## Install every feature that is on into match `world` (see HOW IT WORKS
## at the top). WorldSetup.build() calls this once, as its last step.
static func install(world: World) -> void:
	for entry: Array in FEATURES:
		# Step 1: skip a feature whose variant is off (the usual case).
		var key: String = entry[0]
		if not is_on(key):
			continue
		# Step 2: make the feature's object and keep it for the match. A
		# static install() can be called through the object too, so both
		# kinds of feature work the same way here. A Node feature also goes
		# under the World, so it lives and dies with the match.
		var script: GDScript = entry[1]
		var feature: Object = script.new()
		world.features[key] = feature
		if feature is Node:
			world.add_child(feature)
		# Step 3: let the feature plug itself in.
		feature.call("install", world)
	# Step 4: warn about tuned numbers that no code reads (usually typos).
	for name in Game.tunables:
		var n := str(name)
		if not Rules.TUNABLES.has(n) and not n.begins_with("tech_blurb:"):
			push_warning("Game.tunables[\"%s\"] is not read by any code (see Rules.TUNABLES)" % n)
	# Step 5: one line in the log naming the features that are on.
	if not world.features.is_empty():
		print("features: %s" % ", ".join(PackedStringArray(world.features.keys())))


## Is the feature with variant key `key` on for this match? "On" means
## Game.variant(key) is not "" (not set at all), not "off" and not the
## key's default in Rules.VARIANT_DEFAULTS (a default always means today's
## game). A feature with several values reads Game.variant(key) itself to
## see which one was chosen.
static func is_on(key: String) -> bool:
	var v := Game.variant(key)
	return v != "" and v != "off" and v != str(Rules.VARIANT_DEFAULTS.get(key, "off"))
