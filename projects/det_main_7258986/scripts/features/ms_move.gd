class_name MsMoveFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "ms_move" rule variant (fork
## admiral_command, idea F5 "Earlier or airborne mothership moves").
## REQ-CHANGE: the requirement says the mothership is "moved by a docked
## admiral ... starting at 20 minutes"; this variant relaxes one half of it
## per value, and is kept switchable.
##
## HOW IT WORKS: the variant has these values (Rules.VARIANT_DEFAULTS):
##   "off"     (default) today's game: engines online at 20:00, a docked
##             admiral gives the order.
##   "early"   the engines come online at 12:00 (720 s) instead of 20:00:
##             the tuned number "mothership_move_unlock" is set to 720
##             (Rules.move_unlock_time()). The AI admiral's mover
##             (AdmiralMothershipMover) already asks that function, so it
##             starts advancing from 12:00 on its usual 2-minute gap. The
##             sieges still wait for 20:00.
##   "flying"  an admiral who is out flying their own ship may also order the
##             move: the tuned flag "mothership_move_needs_dock" is switched
##             off (AdmiralCommand.move_blocker()). AI admirals always sit in
##             the chair, so this is only for a human admiral (test it with
##             tests/admiral_fork_probe.gd); in AI-only matches its usage is 0,
##             which means "not screenable", not "bad".
##   "both"    early and flying together.
## Usage counters (Game.count_usage): early_moves (a mothership move was
## ordered before 20:00) and flying_moves (one was ordered while the admiral
## was flying a ship).
##
## WHO USES IT: FeatureRegistry installs it for --variant=ms_move:early|flying|both.

## The variant key this module belongs to.
const KEY := "ms_move"
## The earlier unlock time (seconds): 12:00.
const EARLY_UNLOCK := 720.0

## The match this module runs in.
var world: World


## Switch the move rules for match `w` (FeatureRegistry calls this once).
func install(w: World) -> void:
	world = w
	var value := Game.variant(KEY)
	if not (value in ["early", "flying", "both"]):
		push_warning("ms_move: unknown value \"%s\" (use off, early, flying or both); nothing changed" % value)
		return
	# Step 1: the tuned numbers (the code that checks them is
	# Rules.move_unlock_time() and AdmiralCommand.move_blocker()).
	if value == "early" or value == "both":
		Game.tunables["mothership_move_unlock"] = EARLY_UNLOCK
	if value == "flying" or value == "both":
		Game.tunables["mothership_move_needs_dock"] = false
	# Step 2: count the moves that use the new freedom.
	Events.admiral_result.connect(_on_result)
	world.tree_exiting.connect(func() -> void:
		if Events.admiral_result.is_connected(_on_result):
			Events.admiral_result.disconnect(_on_result))


## An admiral order finished (Events.admiral_result): count a successful
## move that only this variant allows.
func _on_result(team: int, action: String, ok: bool, _message: String) -> void:
	if action != "move" or not ok:
		return
	if world.time < Rules.MOTHERSHIP_MOVE_UNLOCK:
		Game.count_usage("early_moves")
	if not world.teams[team].admiral_docked:
		Game.count_usage("flying_moves")
