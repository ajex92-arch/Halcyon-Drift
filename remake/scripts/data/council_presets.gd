class_name CouncilPresets
extends RefCounted
## WHAT THIS IS: the game's standard rules and the other rule sets ("presets")
## that stay reachable as launch options for tests and research (the fun
## council made them: docs/FUN_PLAN.md section 6; docs/RELEASE_NOTES.md has the
## evidence). A preset is a named bundle of rule variants: the switches that
## turn the feature modules on (scripts/features/, FeatureRegistry).
##   pick    "Council's pick": the STANDARD RULES. Every match that is not
##           given another --preset plays it, so no screen offers a choice. It
##           is "within" plus persistent nodes (node_persist: a destroyed
##           turret's node stays locked for 150 s instead of 60, a rebuilt
##           turret comes back at half hull and then repairs only 1% a second,
##           and the AI admiral rebuilds the nodes nearest its own mothership
##           first). Also within the requirements.
##   within  "Within requirements": minions stop out-scaling pilots
##           (minion_cap), the Lance hunts lone big ships (lance_role), two
##           Bomber seats fly Fighters and pilot torpedoes hurt small craft
##           more (bomber_role:both), the AI admiral spends a big treasury
##           on the Fleet Command Module and wards (admiral_sinks:fleet),
##           hyperspace launches to a repair bay spool for 4 s instead of 6
##           and the AI admiral builds the Hyperspace Module early (redeploy;
##           AI pilots can also jump to a turret, a human's hangar offers
##           repair bays only),
##           every gear item has a Mk II upgrade (gear_mk2), and a team may
##           have up to 60 bought minions alive (fleet_cap:60; 30 in the old
##           rules). None of these changes a requirement: 60 is the Fleet
##           Command limit that docs/DESIGN.md (C22) requires.
##   none    the old standard rules: no pairs at all, so every variant is at
##           its default (Rules.VARIANT_DEFAULTS), the game as v0.1.0 played
##           it. For comparisons with older results.
## No requirement-changing idea (REQ-CHANGE) is in any preset: each one stays a
## single --variant switch, off by default.
## Three of the keys carry a damage modifier: minion_cap (the cap on a
## minion's strength), lance_role (the Lance's x1.35 on a big ship's rear
## shield zone) and bomber_role (the x0.6 torpedo number). They do their
## damage part only while the damage modifiers are kept
## (Rules.damage_modifiers_removed() is false); with the damage modifiers
## removed, minion_cap does nothing, the Lance only hunts and goes round to
## the tail, and the Bomber keeps its seats and its targeting rule.
##
## HOW IT WORKS: each preset is one --variant string (VARIANTS). Game builds
## a match's variants in this order: the defaults, then the pairs of the
## preset, then the pairs of --variant, so --variant can still change one key
## of a preset (--preset=pick --variant=fleet_cap:30 is the pick with the old
## limit). The preset comes from the launch option --preset=<name>; without
## it, STANDARD is played. A name that is not in VARIANTS makes FeatureRegistry
## refuse the match (exit code 3), so a typo never quietly plays another set of
## rules.
## While the damage modifiers are kept, variant_string() ends with the pairs
## of DAMAGE_MODIFIER_VARIANTS, so those rules never depend on VARIANTS
## still listing them.
##
## WHO USES IT: Game (autoload) reads it for --preset; FeatureRegistry.install()
## refuses an unknown name (Game.preset_error); the start screen shows no
## choice, only a line when the launch option was not understood. The council's
## 80-seed validation runs these same strings as --variant.

## The preset a match plays when --preset is not given: Council's pick, the
## standard rules.
const STANDARD := "pick"

## The launch name of the old standard rules (a preset with no pairs).
const OLD_RULES := "none"

## The names --preset accepts.
const ORDER := [OLD_RULES, "within", STANDARD]

## Each preset's --variant string: preset name -> "key:value,key:value,...".
## The keys and values are those of Rules.VARIANT_DEFAULTS. (The strings of
## "within" and "pick" list minion_cap:on; with the damage modifiers removed
## that key does nothing, but it stays so that the strings load.) "none" has no
## pairs, so it plays every variant at its default.
const VARIANTS := {
	"none": "",
	"within": "minion_cap:on,lance_role:on,bomber_role:both,admiral_sinks:fleet,redeploy:on,gear_mk2:on,fleet_cap:60",
	"pick": "minion_cap:on,lance_role:on,bomber_role:both,admiral_sinks:fleet,redeploy:on,gear_mk2:on,fleet_cap:60,node_persist:on",
}

## The pairs a preset also gets while the damage modifiers are kept: the
## variants whose rules have a damage part (minion_cap, lance_role and
## bomber_role:both, as the presets listed them). variant_string() adds them
## after the preset's own pairs, so that rules which apply the damage modifiers
## do not depend on VARIANTS still listing them. --variant is applied after
## them and can still change one.
const DAMAGE_MODIFIER_VARIANTS := "minion_cap:on,lance_role:on,bomber_role:both"


## Is `preset_name` one of the presets (a key of VARIANTS)?
static func is_preset(preset_name: String) -> bool:
	return VARIANTS.has(preset_name)


## The --variant string of preset `preset_name`, or "" when there is no such
## preset or it has no pairs ("none"). While the damage modifiers are kept a
## preset with pairs ends with DAMAGE_MODIFIER_VARIANTS (see there).
static func variant_string(preset_name: String) -> String:
	var s := str(VARIANTS.get(preset_name, ""))
	if s != "" and not Rules.damage_modifiers_removed():
		s += "," + DAMAGE_MODIFIER_VARIANTS
	return s
