class_name SpatialHash
extends RefCounted
## WHAT THIS IS: a quick way to find the units near a spot. Instead of
## checking every unit in the match, we lay a grid of squares ("cells")
## over the map and file each unit under the cell its centre is in. To
## find units near a spot we only look in the few cells around it. (A
## grid used like this is called a "spatial hash".)
##
## HOW IT WORKS: World empties the grid and files every live unit again
## once per tick (a "tick" is one small step of game time, normally 60 a
## second), so it always matches where units are now.
## Every proximity query in the sim goes through here: targeting, aggro,
## repair drones, separation, projectile hits.
##
## Usage:
##   hash.query(pos, radius, out)        -> fills `out` with units (any team)
## `out` is cleared first; reuse one Array per caller to avoid allocations.
## Results may include units slightly outside `radius` (cell granularity);
## callers check exact distance themselves.
## A unit is filed by its centre only, so a search can miss a big unit whose
## centre is just outside the searched cells; callers looking for big units
## search a bit wider (Projectiles does this with World.big_hash).
##
## WHO USES IT: WorldSetup makes two: World.unit_hash (every live unit
## except motherships) and World.big_hash (only units wider than
## Projectiles.HASH_PAD). WorldRegistry.rebuild_hashes() runs clear() and
## insert() every tick. query() is asked by targeting (PilotTargeting,
## WeaponMountTargeting, turrets), PilotSenses, Combat, Projectiles,
## WorldSeparation, WorldQueries, WorldVisibility, WorldSupport, minions,
## mining drones, repair drones, derelicts, ship abilities and some tests.

## Size (world units) of one square cell.
const CELL := 320.0

## How many cells across (enough for the map, plus one).
var cols := 1
## How many cells down (enough for the map, plus one).
var rows := 1
## The cells: one Array of units per cell (an Array of Arrays). Row by row
## from the top; cell (cx, cy) is entry cx + cy * cols.
var cells: Array = []
## The cells that have something in them since the last clear(), so
## clear() only has to empty those.
var used: PackedInt32Array = PackedInt32Array()
## Per row: the leftmost and rightmost column that has a unit in it right
## now (row_lo > row_hi means the row is empty). query() uses them to skip
## empty rows and the empty ends of rows: most of the map is open space, and
## a wide search (2,500 world units is about 17 x 17 cells) would otherwise
## step through hundreds of empty cells. Skipping empty cells can't change
## the answer or its order.
var row_lo: PackedInt32Array = PackedInt32Array()
## Per row: the rightmost column with a unit in it (see row_lo above; -1
## while the row is empty).
var row_hi: PackedInt32Array = PackedInt32Array()


## Make an empty grid big enough for a map `width` by `height` world units.
func _init(width: float, height: float) -> void:
	cols = int(ceil(width / CELL)) + 1
	rows = int(ceil(height / CELL)) + 1
	cells.resize(cols * rows)
	for i in cells.size():
		cells[i] = []
	# Every row starts empty: lo past the right edge, hi before the left.
	row_lo.resize(rows)
	row_hi.resize(rows)
	row_lo.fill(cols)
	row_hi.fill(-1)


## Empty the grid (only the cells that were used, and their rows).
func clear() -> void:
	for idx in used:
		(cells[idx] as Array).clear()
		var cy := idx / cols
		row_lo[cy] = cols
		row_hi[cy] = -1
	used.clear()


## File unit `u` under the cell its centre is in. Units off the map's edge
## go into the nearest edge cell.
func insert(u: Node2D) -> void:
	var p := u.global_position
	var cx := clampi(int(p.x / CELL), 0, cols - 1)
	var cy := clampi(int(p.y / CELL), 0, rows - 1)
	var idx := cx + cy * cols
	var cell: Array = cells[idx]
	# The first unit in a cell: note the cell as used, and widen its row's
	# occupied span if needed.
	if cell.is_empty():
		used.append(idx)
		if cx < row_lo[cy]:
			row_lo[cy] = cx
		if cx > row_hi[cy]:
			row_hi[cy] = cx
	cell.append(u)


## Fill `out` with every unit in cells overlapping the circle.
## (More exactly: the cells that the circle's bounding square touches; row
## by row from the top, left to right, and in filing order within a cell.)
## Returns `out`.
func query(pos: Vector2, radius: float, out: Array) -> Array:
	out.clear()
	var x0 := clampi(int((pos.x - radius) / CELL), 0, cols - 1)
	var x1 := clampi(int((pos.x + radius) / CELL), 0, cols - 1)
	var y0 := clampi(int((pos.y - radius) / CELL), 0, rows - 1)
	var y1 := clampi(int((pos.y + radius) / CELL), 0, rows - 1)
	for cy in range(y0, y1 + 1):
		# Only the part of the row that has units in it (empty rows: none).
		var a := maxi(x0, row_lo[cy])
		var b := mini(x1, row_hi[cy])
		if a > b:
			continue
		var base := cy * cols
		for cx in range(a, b + 1):
			var cell: Array = cells[base + cx]
			if not cell.is_empty():
				out.append_array(cell)
	return out
