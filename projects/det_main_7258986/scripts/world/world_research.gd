class_name WorldResearch
extends RefCounted
## WHAT THIS IS: makes finished research reach the units that are already
## out in space, not only the ones built later.
##
## HOW IT WORKS: when a team finishes any research, on_research_done():
##   1. tells each of the team's pilot ships to recompute its stats,
##   2. gives each live turret its new maximum hull (turret armour
##      research), keeping the same fraction of health,
##   3. gives each live mining drone its new maximum hull (drone armour)
##      and its new cargo size (mining capacity research).
## "Keeping the same fraction" means a turret at half health stays at half
## health of the new, bigger maximum.
##
## WHO USES IT: World.on_research_done() forwards here; TeamState calls
## that when research completes. (on_research_done is a "static"
## function: called as WorldResearch.on_research_done(world, ...), with no
## object made.)


## Apply `team`'s research to its units already in world `w`. `_id` (the
## research that finished) is not used: every upgrade is simply
## re-checked.
static func on_research_done(w: World, team: int, _id: String) -> void:
	# Step 1: ships recompute their stats on their next turn.
	for s in w.ships:
		if s.team == team:
			s.stats_dirty = true
	# Step 2: turret / drone upgrades apply to the ones already out there
	# too. A turret's maximum hull is its type's hull x (1 + turret armour).
	var ts := w.teams[team]
	for t in w.turrets:
		if t.team == team and t.alive:
			var want := float(t.tdef["hull"]) * (1.0 + ts.turret_armor)
			# Only change it if it differs by more than 0.5 hull points.
			if absf(want - t.hull_max) > 0.5:
				var frac := t.hull_frac()
				t.hull_max = want
				t.hull = want * frac
	# Step 3: mining drones: the same for their hull (drone armour), and
	# their cargo size is set from the base capacity x (1 + mining capacity).
	for d in w.mining_drones:
		if d.team == team and d.alive:
			var want_hp := float(Structures.MINING_DRONE["hp"]) * (1.0 + ts.drone_armor)
			if absf(want_hp - d.hull_max) > 0.5:
				var frac := d.hull_frac()
				d.hull_max = want_hp
				d.hull = want_hp * frac
			d.capacity = float(Structures.MINING_DRONE["capacity"]) * (1.0 + ts.mining_capacity)
