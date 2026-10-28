extends Node
## WHAT THIS IS: a check that a round which only grazes the rim of a big
## ship's hit circle is still found by the hit search. A ship's hit circle is
## as big as its radius, and the search for big units (World.big_hash) only
## reaches so far: a round that crossed the outer band of a circle bigger than
## the search would pass through the ship without a hit.
##
## HOW IT WORKS: it builds the normal match and freezes it. For each of the
## four biggest hulls (the two frigates and the two capitals) it launches one
## ship of team 1 and stands it at 64 spots, spread over one 320-unit grid
## cell of the spatial hash in both directions (whether the cell of the ship is
## searched depends on where in its cell the ship stands). At each spot it asks
## ProjectilesHitScan.scan() about 12 straight rounds of team 0 that pass the
## ship from 12 directions, each 2 world units inside the rim of the hit
## circle (the ship's radius plus the round's own radius). A round is the short
## line it flies in one tick (16 world units: about 1,000 units a second), as
## in a match; a long line would reach further on its own and hide the gap.
## Every round must find the ship. It prints one line per hull and then the
## failures.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hit_reach_check
##
## HOW TO READ THE OUTPUT: "hit_reach_check: <hull> radius R, N rounds, M
## missed" for each hull, then "hit_reach_check: F failures" (F counts the
## rounds that missed; 0 means the search reaches every hull).
##
## WHO USES IT: main.gd loads it for --test=hit_reach_check (for --test=<name>
## it loads tests/<name>.gd, adds it after the World and calls setup()). It
## only reads the game: the match stands still and nothing in it changes.

## The hulls tried.
const HULLS := ["flak", "ion", "destroyer", "battlecruiser"]
## The radius (world units) of the rounds asked about.
const ROUND_RADIUS := 3.0
## How far (world units) inside the rim of the hit circle the rounds pass.
const INSIDE := 2.0
## The length (world units) of the line a round flies in one tick.
const TICK_LINE := 16.0
## The distance (world units) between two spots of a ship, in both directions.
const SPOT_STEP := 40.0
## How many spots there are in each direction (8 x 40 = 320, one grid cell).
const SPOTS := 8
## How many directions the rounds come from.
const DIRECTIONS := 12

## The running match (set by setup()).
var world: World


## main.gd calls this once, right after the World is built. Freeze the match
## and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	world.set_physics_process(false)
	_run.call_deferred()


## Try every hull, print the result and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	var failures := 0
	# Where the ships stand: open ground between the lanes (the hull gallery's
	# spot), well away from every other unit.
	var home := Vector2(MapLayout.CX, MapLayout.H * 0.3)
	for hid: String in HULLS:
		var ship := _launch(hid)
		var tried := 0
		var missed := 0
		for ix in SPOTS:
			for iy in SPOTS:
				ship.global_position = home + Vector2(float(ix), float(iy)) * SPOT_STEP
				world.registry.rebuild_hashes()
				for k in DIRECTIONS:
					var dir := Vector2.from_angle(float(k) * TAU / float(DIRECTIONS))
					var side := dir.orthogonal() * (ship.radius + ROUND_RADIUS - INSIDE)
					var a := ship.global_position + side - dir * TICK_LINE * 0.5
					var b := a + dir * TICK_LINE
					world.projectiles.hit_scan.scan(a, b, ROUND_RADIUS, 0.0, Rules.W_BOLT, 0, 2.0)
					tried += 1
					if world.projectiles.hit_scan.hit_unit != ship:
						missed += 1
		print("hit_reach_check: %s radius %s, %d rounds, %d missed" % [hid, ship.radius, tried, missed])
		failures += missed
		ship.global_position = Vector2(-5000.0, -5000.0)
		ship.alive = false
	print("hit_reach_check: %d failures" % failures)
	get_tree().quit()


## Launch a pilot ship of hull `hid` for team 1 (a pilot named after the hull),
## standing still.
func _launch(hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), 1, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	return s
