class_name FleetCapFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "fleet_cap" rule variant: how
## many bought minions (small computer-flown lane ships) a team may have
## alive at once once it owns the Fleet Command Module. The variant's default
## is 30 (Minions.CONTROL_CAP, the old rules); the standard rules (Council's
## pick) set 60. The variant lets a match use another
## number, so the cap can be chosen between fun (a bigger fleet makes the
## late game bigger and louder) and cost (every alive minion is one more unit
## the simulation has to move, aim and draw).
## REQ-CHANGE: a limit other than 60. The requirement is 60 (docs/DESIGN.md,
## C22), and the standard rules and "within" use it.
##
## HOW IT WORKS: the value is the limit written as a whole number,
## --variant=fleet_cap:45. The default, "30", is the old rules and installs
## nothing (FeatureRegistry skips a key that has its default value). Any
## other whole number from 1 to MAX_CAP is stored as the tuned number
## "fleet_cap" (Game.tunables), which Minions.control_cap() reads. The limit
## is enforced in one place, MinionDirector.buy(), which both the AI admiral
## (AdmiralFleetCommand, which also stops asking once the limit is reached)
## and a human admiral (the admiral board's buy buttons, through
## AdmiralCommand.buy_minion) go through, and the board's status line prints
## the same number. So the limit is one rule of the match: it is the same
## for the AI and for a human, and for both teams. A value that is not a
## whole number from 1 to MAX_CAP only gets a warning and the match keeps
## the default 30. The module draws no random numbers and makes no units. It
## records the limit it set in Game.usage as "fleet_cap_set".
##
## WHO USES IT: FeatureRegistry installs it for --variant=fleet_cap:<number>.

## The variant key this module belongs to.
const KEY := "fleet_cap"
## The most the variant accepts (a typo such as 4500 gets a warning instead of
## a match with thousands of minions).
const MAX_CAP := 300


## Set the limit for the match (FeatureRegistry calls this once at match
## start; WorldSetup empties Game.tunables for the next match). An unusable
## value only gets a warning.
func install(_w: World) -> void:
	var value := Game.variant(KEY)
	if not value.is_valid_int() or value.to_int() < 1 or value.to_int() > MAX_CAP:
		push_warning("fleet_cap: unusable value \"%s\" (use a whole number from 1 to %d); the limit stays %d" % [value, MAX_CAP, Minions.CONTROL_CAP])
		return
	var cap := value.to_int()
	Game.tunables["fleet_cap"] = cap
	Game.count_usage("fleet_cap_set", cap)
