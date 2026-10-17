class_name CouncilPresets
extends RefCounted
## WHAT THIS IS: the two rule sets ("presets") that the fun council made for
## playtests (docs/FUN_PLAN.md section 6; FORK_MANIFEST.md has the evidence).
## A preset is a named bundle of rule variants: the switches that turn the
## feature modules on (scripts/features/, FeatureRegistry). Today's game is
## no preset at all: every variant at its default (Rules.VARIANT_DEFAULTS).
##   within  "Within requirements": minions stop out-scaling pilots
##           (minion_cap), the Lance hunts lone big ships (lance_role), two
##           Bomber seats fly Fighters and pilot torpedoes hurt small craft
##           more (bomber_role:both), the AI admiral spends a big treasury
##           on the Fleet Command Module and wards (admiral_sinks:fleet),
##           pilots can jump to forward repair bays and turrets (redeploy),
##           every gear item has a Mk II upgrade (gear_mk2), and a team may
##           have up to 60 bought minions alive (fleet_cap:60; 30 today).
##           None of these changes a requirement of
##           docs/USER_REQUIREMENTS_2026-10-13.md.
##   pick    "Council's pick": "within" plus persistent nodes (node_persist:
##           a destroyed turret's node stays locked for 150 s instead of 60,
##           and a rebuilt turret comes back at half hull). Also within the
##           requirements.
## The user chose both on 2026-10-17, the limit of 60 included ("Yes, but
## another fleet cap. 60"). No requirement-changing idea (REQ-CHANGE) is in
## either preset: each one stays a single --variant switch, off by default.
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
	"within": "The council's changes that keep every design rule: late minions no longer out-scale pilots, the Lance hunts lone big ships, two Bomber seats fly Fighters and pilot torpedoes hurt small craft more, the AI admiral spends a big treasury on Fleet Command and wards, pilots can jump to forward repair bays and turrets, gear has Mk II upgrades, and Fleet Command allows up to 60 bought minions.",
	"pick": "Within requirements, plus persistent nodes: a node whose turret is destroyed stays locked for 150 seconds (not 60), and a turret built there again starts at half hull and repairs slowly.",
}

## The start screen's name for today's game (no preset).
const TODAY_LABEL := "Today's game"
## The start screen's description of today's game (no preset).
const TODAY_BLURB := "Every rule as it is today, with no council changes."


## Is `preset_name` one of the presets (a key of VARIANTS)?
static func is_preset(preset_name: String) -> bool:
	return VARIANTS.has(preset_name)


## The --variant string of preset `preset_name`, or "" when there is no such
## preset.
static func variant_string(preset_name: String) -> String:
	return str(VARIANTS.get(preset_name, ""))
