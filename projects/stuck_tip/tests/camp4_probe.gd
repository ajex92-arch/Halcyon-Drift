extends Node
## WHAT THIS IS: a map check for the "camp4" rule variant of the fork
## teamfights_jungle (a fourth derelict camp per quarter). It proves that
## every camp on the map (the old ones and the new ones) is a clear spot that
## a strike craft (radius up to 17 world units) can fly to from its mothership
## along the route graph, and that the rock-gap sealing has finished.
##
## HOW IT WORKS: for every camp in the map it checks (1) no rock within 40
## world units of the camp's centre, (2) the route graph (small-ship links
## allowed) has a path from the camp's own team's mothership, and (3) every
## hop of that path misses all rocks when thickened by 17 world units. It also
## runs AsteroidField.seal_tight_gaps() a second time: it should find nothing
## left to seal (0). Then it prints one line,
##   CAMP4_PROBE camps=N extra=E bad_spots=B unreachable=U blocked_hops=H resealed=R rocks=K
## and "camp4_probe: 0 failures" (or the number of problems).
##
## HOW TO RUN IT (from the folder that holds the project):
##   godot --headless --path <project> -- --all-ai --no-pilots --no-admiral-ai --test=camp4_probe --variant=camp4:on
## Compare with the same command without --variant to see today's map.
##
## WHO USES IT: main.gd loads it for --test=camp4_probe. The fork's build
## report quotes its output.

## The strike craft radius the paths must clear (world units).
const SHIP_R := 17.0


## main.gd calls this once, right after the World is built: run the checks,
## print the result and quit half a second later.
func setup(w: World) -> void:
	var bad_spots := 0
	var unreachable := 0
	var blocked_hops := 0
	var extra := 0
	for c: Dictionary in w.map.camps:
		var pos: Vector2 = c["pos"]
		if str(c["id"]).ends_with("_d"):
			extra += 1
		# Step 1: a clear spot.
		if w.asteroids.blocked(pos, 40.0):
			bad_spots += 1
			print("CAMP4_PROBE bad spot ", c["id"])
		# Step 2: a route from the camp's own mothership.
		var team := 0 if str(c["quad"]).ends_with("l") else 1
		var path := w.map.route.path(w.map.mothership_pos[team], pos, true)
		if path.is_empty():
			unreachable += 1
			print("CAMP4_PROBE unreachable ", c["id"])
			continue
		# Step 3: every hop clear for a small ship.
		for i in range(path.size() - 1):
			if not w.asteroids.segment_hit(path[i], path[i + 1], SHIP_R).is_empty():
				blocked_hops += 1
				print("CAMP4_PROBE blocked hop on the way to ", c["id"], " at ", path[i])
	var resealed := w.asteroids.seal_tight_gaps()
	print("CAMP4_PROBE camps=%d extra=%d bad_spots=%d unreachable=%d blocked_hops=%d resealed=%d rocks=%d" % [w.map.camps.size(), extra, bad_spots, unreachable, blocked_hops, resealed, w.asteroids.pos.size()])
	print("camp4_probe: %d failures" % (bad_spots + unreachable + blocked_hops))
	get_tree().create_timer(0.5).timeout.connect(func() -> void: get_tree().quit())
