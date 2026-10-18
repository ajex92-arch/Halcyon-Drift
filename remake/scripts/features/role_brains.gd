class_name RoleBrains
extends RefCounted
## WHAT THIS IS: a small helper that lets a feature module give the AI
## pilots a slightly different "part" of their brain (PilotAI is built from
## parts: PilotGoals, PilotCombat, PilotSystems, PilotShopping,
## PilotTargeting...). A feature writes a version of a part that extends the
## original (so it keeps all of its behaviour) and changes only what it
## must; this helper puts the new part into every pilot's brain.
##
## HOW IT WORKS: ensure() looks at every AI brain in world.pilot_ai. For a
## brain whose part (the variable named `member`, for example "goals") does
## not yet use the feature's script, it makes a new part from that script
## (the parts are made with the brain as their one argument) and puts it
## in place. A brain that already has it is left alone. Features call it
## once when the match starts and then every half second, so brains made
## later (the arena tests make theirs after the match is built) get the
## new part too.
##
## WHO USES IT: LanceRoleFeature (goals, combat), RoutingPayoffFeature
## (systems) and BomberRoleFeature (shopping, targeting). It is never
## called unless one of those features is on, so with every combat_roles
## key at its default the AI pilots keep their ordinary parts.

## How often (seconds) a feature checks for brains without its part.
const CHECK_EVERY := 0.5


## Give every AI brain in `world` the part made from `script` in its
## variable `member` ("goals", "combat", "systems", "shopping" or
## "targeting"). `only_slots` (a list of seat numbers; empty = all seats)
## limits it to those pilot seats. Returns how many brains were changed.
static func ensure(world: World, member: String, script: GDScript, only_slots: Array = []) -> int:
	var changed := 0
	for p: PilotProfile in world.pilot_ai:
		# Step 1: skip seats the feature does not want.
		if not only_slots.is_empty() and not only_slots.has(p.slot):
			continue
		# Step 2: skip a brain that already has the new part.
		var brain: PilotAI = world.pilot_ai[p]
		var current: Object = brain.get(member)
		if current != null and current.get_script() == script:
			continue
		# Step 3: put in the new part (made with the brain as its owner).
		brain.set(member, script.new(brain))
		changed += 1
	return changed
