class_name MsNosmallFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "ms" rule variant: small craft
## stop sieging the mothership (docs/FUN_PLAN.md section 5, endgame_closure
## fork, an optional carry-over from docs/AI_DEEP_DIVE.md section 5 item 4).
## REQ-CHANGE: "Larger ships should not be inherently better than smaller
## ships, both should be needed to push lanes" (it makes pushing the
## mothership a big-ship job).
##
## HOW IT WORKS: the variant has one value besides "off" (the default):
##   "nosmall"   small ships that are not bombers (strike craft: scouts,
##               fighters, lance fighters) no longer pick the enemy
##               mothership as a target and no longer push it together with
##               3 or more friendly minions at its hull. Everything else is
##               as before: they still fight pilots, minions, turrets and
##               the defenders around it; bombers and every bigger hull still
##               attack the mothership.
## The AI uses it by itself: PilotTargeting asks skips() whenever a small
## ship would have gone for the mothership. Each time that happens is counted
## in Game.usage as "small_siege_skips". The module has no state and draws no
## random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=ms:nosmall (nothing
## to set up). PilotTargeting.pick_target() and push_target() call skips()
## when World.features has "ms".

## The variant key this module belongs to.
const KEY := "ms"


## Nothing to set up: PilotTargeting asks skips(). Only an unknown value
## gets a warning. FeatureRegistry calls this once at match start.
static func install(_world: World) -> void:
	if Game.variant(KEY) != "nosmall":
		push_warning("ms: unknown value \"%s\" (use off or nosmall); nothing changed" % Game.variant(KEY))


## Should `ship` leave the enemy mothership alone? True for a small ship that
## is not a bomber (and counts the skip in Game.usage); always false when the
## variant is not "nosmall".
static func skips(ship: Ship) -> bool:
	if Game.variant(KEY) != "nosmall":
		return false
	if ship.is_small() and ship.hull_id != "bomber":
		Game.count_usage("small_siege_skips")
		return true
	return false
