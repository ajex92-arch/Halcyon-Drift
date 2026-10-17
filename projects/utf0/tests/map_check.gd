extends Node
## WHAT THIS IS: the map check. It tests the finished map against the plan it
## was built from (MapLayout), so that a change to the map (a taller map,
## different lanes, new ore nodes) can be made in the plan alone, and this
## test says whether the map that came out is sound. It checks:
##   - the map's size and frame (the centre line, the motherships, everything
##     lying inside the map);
##   - the width of every lane, as the game reads it (the open-lane lookup),
##     against the plan's width;
##   - the chokes: at every jungle entrance a corvette-sized ship cannot get
##     through and a strike craft can, both for the map as planned and as it
##     really is in the match (see tests/lib/map_check_choke.gd);
##   - roads: strike craft reach every monster camp and ore node from both
##     motherships, every ore node has a mining-drone road out and home, and
##     how close those roads and nodes lie to the monster camps;
##   - clear space: no ordinary rock inside a node's area, the camps' clear
##     radius kept;
##   - the mirror: Aurelian's half against Cinder's (nodes, camps, entrances,
##     every rock), things on the centre line exist once;
## and finishes with one MAP_JSON line holding the numbers (lane widths,
## counts, the smallest distances, the drone roads' distances to the camps).
## It is the user test fork's yardstick for the new map (stage 2). Every
## expected number is read from MapLayout and MapInfo, never written into the
## test.
##
## HOW IT WORKS: setup() takes the finished World; the first physics tick runs
## all the checks, prints the result and quits. The checks live in three
## helper files in tests/lib (each starts with a description):
##   map_check_layout.gd   size, lane widths, clear space, the mirror, distances
##   map_check_choke.gd    the gates
##   map_check_routes.gd   roads and drone roads
## The test only reads the match, except that it makes a few mining drones
## (and removes them again) to see the roads the drones' own code plans.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --test=map_check
## --headless runs with no window. It needs no match time (it ends within
## seconds). The option --strict-choke makes "a corvette-sized ship fits
## through a gate as built" a failure (otherwise it is a WARN line).
##
## HOW TO READ THE OUTPUT: one line per check: "PASS <what> <detail>" or
## "FAIL <what> <detail>", plus "WARN" lines (something worth knowing that is
## not a failure: a drone road that passes a monster camp, a gate a corvette
## could squeeze through) and "INFO" lines. Then "map_check: N failures" (0
## means the map is sound), a "RESULT" line, and last the "MAP_JSON {...}"
## line with the numbers.
##
## WHO USES IT: main.gd loads it for --test=map_check (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()). Stage 2
## of the user test fork (docs/USER_FORK_PLAN.md) runs it after every change
## to the map.

const Layout := preload("res://tests/lib/map_check_layout.gd")
const Choke := preload("res://tests/lib/map_check_choke.gd")
const Routes := preload("res://tests/lib/map_check_routes.gd")

## The running match (set by setup()).
var world: World
## True once the checks have run (they run once).
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w


## Godot calls this every tick. On the first one, run every check, print the
## result and quit.
func _physics_process(_dt: float) -> void:
	if world == null or _done:
		return
	_done = true
	_run()
	get_tree().quit()


## Run every check, print the rows and the verdict, then the numbers.
func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var rows: Array = []
	var nums := {"map_seed": MapLayout.SEED}
	# The checks, in the order of the description above.
	Layout.frame(world, rows, nums)
	Layout.lanes(world, rows, nums)
	Choke.chokes(world, rows, nums, bool(Game.opt("strict-choke", false)))
	Routes.reach(world, rows, nums)
	Routes.drones(world, rows, nums)
	Layout.clearances(world, rows, nums)
	Layout.mirror(world, rows, nums)
	Layout.distances(world, nums)
	Routes.links(world, rows, nums)
	_counts(nums)
	# The rows: one line each.
	var fails := 0
	var warns := 0
	for r: Dictionary in rows:
		var level: String = r["level"]
		fails += 1 if level == "fail" else 0
		warns += 1 if level == "warn" else 0
		print("%s %s %s" % [level.to_upper(), r["name"], r["detail"]])
	# The verdict, a line for run_batch (it looks for "RESULT"), and the numbers.
	print("map_check: %d failures" % fails)
	print("map_check: %d warnings (WARN lines above)" % warns)
	print("RESULT map_check %d failures, %d warnings, %d ms" % [fails, warns, Time.get_ticks_msec() - t0])
	nums["failures"] = fails
	nums["warnings"] = warns
	print("MAP_JSON ", JSON.stringify(_finite(nums)))


## How many of each thing the map has, into `nums["counts"]`.
func _counts(nums: Dictionary) -> void:
	var info := world.map
	var kinds := {}
	for n: Dictionary in info.nodes:
		kinds[n["kind"]] = int(kinds.get(n["kind"], 0)) + 1
	var camp_types := {}
	for c: Dictionary in info.camps:
		camp_types[c["type"]] = int(camp_types.get(c["type"], 0)) + 1
	nums["counts"] = {"rocks": info.rock_pos.size(), "nodes": info.nodes.size(), "nodes_by_kind": kinds,
		"camps": info.camps.size(), "camps_by_type": camp_types, "entrances": info.entrances.size(),
		"jungle_paths": info.jungle_paths.size(), "route_nodes": info.route.node_count(), "lanes": info.lanes.size()}


## A copy of `v` (numbers, text, lists and dictionaries) in which every
## number that is not an ordinary finite number (infinity, "not a number")
## is replaced by -1, so that the JSON line is valid JSON.
func _finite(v: Variant) -> Variant:
	if v is float:
		return v if is_finite(v) else -1.0
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _finite(v[k])
		return out
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(_finite(x))
		return arr
	return v
