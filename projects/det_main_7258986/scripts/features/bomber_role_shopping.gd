class_name BomberRoleShopping
extends PilotShopping
## WHAT THIS IS: a version of the AI pilot's "shopping" part (PilotShopping)
## used by the bomber_role:seats variant, for the pilots in seats 6 and 10.
## They want Fighters, not Bombers.
##
## HOW IT WORKS: wish_list() gives the list ["fighter"] to a pilot with the
## "striker" temperament (seats 2, 6 and 10 are strikers; RoleBrains only
## puts this part into seats 6 and 10); every other temperament would get
## the ordinary list. shop() runs the original shopping and then counts a
## swap ("bomber_seat_swaps" in Game.usage) each time the pilot ends up in
## a Fighter that it was not flying before.
##
## WHO USES IT: RoleBrains (installed by BomberRoleFeature); PilotAI calls
## shop() and wants_shopping() through brain.shopping, and they use
## wish_list().


## Hulls we want, best first: just the Fighter for a striker, otherwise the
## ordinary list.
func wish_list() -> Array:
	if ai.temperament == "striker":
		return ["fighter"]
	return super.wish_list()


## Shop as usual, then count a new Fighter in a seat that would have flown
## a Bomber.
func shop() -> void:
	var before := ai.profile.hull_id
	super.shop()
	if ai.temperament == "striker" and ai.profile.hull_id == "fighter" and before != "fighter":
		Game.count_usage("bomber_seat_swaps")
