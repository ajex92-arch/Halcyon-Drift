class_name CouncilPresets
extends RefCounted
## WHAT THIS IS: the two rule sets ("presets") that the fun council made for
## playtests (docs/FUN_PLAN.md section 6; docs/RELEASE_NOTES.md has the evidence).
## A preset is a named bundle of rule variants: the switches that turn the
## feature modules on (scripts/features/, FeatureRegistry). The standard rules
## are no preset at all: every variant at its default (Rules.VARIANT_DEFAULTS).
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
##           have up to 60 bought minions alive (fleet_cap:60; 30 in the
##           standard rules). None of these changes a requirement: 60 is the
##           Fleet Command limit requirement since the user's decision of
##           2026-10-17 (docs/DESIGN.md, C22).
##   pick    "Council's pick": "within" plus persistent nodes (node_persist:
##           a destroyed turret's node stays locked for 150 s instead of 60,
##           a rebuilt turret comes back at half hull and then repairs only
##           1% a second, and the AI admiral rebuilds the nodes nearest its
##           own mothership first). Also within the requirements.
## The user chose both on 2026-10-17. Both presets use fleet cap 60. No
## requirement-changing idea (REQ-CHANGE) is in either preset: each one stays
## a single --variant switch, off by default.
##
## HOW IT WORKS: each preset is one --variant string (VARIANTS). Game builds
## a match's variants in this order: the defaults, then the preset's pairs,
## then the pairs of --variant, so --variant can still change one key of a
## preset (--preset=within --variant=fleet_cap:30 is "within" with today's
## limit). The preset comes from the launch option --preset=<name>, or from
## the start screen's rule-set buttons (Game.apply_preset()). A name that is
## not in VARIANTS makes FeatureRegistry refuse the match (exit code 3), so a
## typo never quietly plays today's game instead.
##
## WHO USES IT: Game (autoload) reads it for --preset and apply_preset();
## the start screen (StartScreen) shows ORDER with LABELS and BLURBS;
## FeatureRegistry.install() refuses an unknown name (Game.preset_error).
## The council's 80-seed validation runs these same strings as --variant.

## The presets, in the order the start screen shows them.
const ORDER := ["within", "pick"]

## Each preset's --variant string: preset name -> "key:value,key:value,...".
## The keys and values are those of Rules.VARIANT_DEFAULTS.
const VARIANTS := {
	"within": "minion_cap:on,lance_role:on,bomber_role:both,admiral_sinks:fleet,redeploy:on,gear_mk2:on,fleet_cap:60",
	"pick": "minion_cap:on,lance_role:on,bomber_role:both,admiral_sinks:fleet,redeploy:on,gear_mk2:on,fleet_cap:60,node_persist:on",
}

## Each preset's name for players (the start screen's buttons).
const LABELS := {
	"within": "Within requirements",
	"pick": "Council's pick",
}

## Each preset's description for players (shown on the start screen under
## the rule-set buttons).
const BLURBS := {
	"within": "Changes that stay within the game's design requirements: late minions no longer out-scale pilots, the Lance hunts lone big ships, two Bomber seats fly Fighters and pilot torpedoes hurt small craft more, the AI admiral spends a big treasury on Fleet Command and wards and builds the Hyperspace Module early, a hyperspace launch to a repair bay spools for 4 seconds instead of 6 (AI pilots can also jump to a friendly turret near the fight), gear has Mk II upgrades, and Fleet Command allows up to 60 bought minions.",
	"pick": "Within requirements, plus persistent nodes: a node whose turret is destroyed stays locked for 150 seconds (not 60), a turret built there again starts at half hull and then only repairs 1% a second, and the AI admiral rebuilds the nodes nearest its own mothership first.",
}

## The start screen's name for the standard rules (no preset).
const TODAY_LABEL := "Standard rules"
## The start screen's description of the standard rules (no preset).
const TODAY_BLURB := "The standard rules of v0.1.0."


## Is `preset_name` one of the presets (a key of VARIANTS)?
static func is_preset(preset_name: String) -> bool:
	return VARIANTS.has(preset_name)


## The --variant string of preset `preset_name`, or "" when there is no such
## preset.
static func variant_string(preset_name: String) -> String:
	return str(VARIANTS.get(preset_name, ""))
