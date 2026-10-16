class_name VisionRays
extends RefCounted
## WHAT THIS IS: the line-of-sight "ray caster" of the fog of war. Given a
## viewer's cell and sight radius, it lists every cell the viewer can see.
## A part of Vision, kept in its own file.
##
## HOW IT WORKS: from the centre of the viewer's cell we send straight lines
## ("rays") out in many directions, evenly spread around the circle: about
## 1.5 rays for every cell along the circle's edge, and at least 16. Each
## ray walks outward in half-cell steps and lists every cell it enters. It
## stops when it leaves the map, goes past the sight radius, or enters a
## blocked (asteroid) cell: that cell is still listed (you see the rock),
## but nothing behind it. The viewer's own cell never blocks.
##
## The same cell and radius always give the same answer until the
## asteroids change, so answers are remembered in a "cache" (a lookup
## table). Viewers standing where others stood before cost almost nothing.
## Vision empties the cache when the asteroids change; it is also emptied
## whenever it grows past CACHE_MAX (30,000) answers, to save memory.
##
## WHO USES IT: Vision makes one in setup(), asks cells_seen() in
## update_team(), and calls clear_cache() from rebuild_blocked().

## The fog grid we cast over (we read its size and its blocked cells).
var vision: Vision
## The cache: key (cell number * 64 + radius in cells) -> the list of cell
## numbers seen (a PackedInt32Array).
var _cache := {}
## Per cell: the number of the cast that last listed it, so one cast never
## lists a cell twice (and nothing has to be wiped between casts).
var _mark := PackedInt32Array()
## The number of the latest cast (goes up by one per cast).
var _mark_id := 0
## The most answers the cache keeps before it is emptied.
const CACHE_MAX := 30000
## Per ray count: each ray's half-cell step, x and y (the ray direction's
## cos and sin, times 0.5), worked out once instead of at every cast. Kept
## in 64-bit float lists so the numbers are exactly the ones _cast() used to
## compute each time (a Vector2 would round them to 32 bits).
var _step_x := {}
## The y part of each ray's half-cell step, per ray count (see _step_x
## above).
var _step_y := {}


## Remember the grid and make the per-cell mark list. Vision makes this
## part once, in setup(), after it knows the grid size.
func _init(owner: Vision) -> void:
	vision = owner
	_mark.resize(owner.cols * owner.rows)


## The cell numbers a viewer in cell `c` with a sight radius of `rc` cells
## can see. From the cache when we have the answer already; otherwise cast
## the rays and remember the answer.
func cells_seen(c: int, rc: int) -> PackedInt32Array:
	var key := c * 64 + rc
	var cells: PackedInt32Array
	if _cache.has(key):
		cells = _cache[key]
	else:
		var cols := vision.cols
		cells = _cast(c % cols, c / cols, rc)
		# A very full cache is emptied before the new answer goes in. (It was
		# 8,000 answers: in a long match that emptied the cache about every
		# two minutes and every viewer had to cast again. 30,000 answers is
		# at most about 35 MB. Emptying only costs time; the answers cast
		# again are exactly the same.)
		if _cache.size() > CACHE_MAX:
			_cache.clear()
		_cache[key] = cells
	return cells


## Forget every remembered answer (the asteroids changed).
func clear_cache() -> void:
	_cache.clear()


## Make sure the half-cell steps for `rays` rays exist: ray k points at
## angle TAU * k / rays, and its step is (cos, sin) of that angle times 0.5,
## computed exactly as _cast() used to compute it on every cast.
func _steps_for(rays: int) -> void:
	if _step_x.has(rays):
		return
	var sx := PackedFloat64Array()
	var sy := PackedFloat64Array()
	sx.resize(rays)
	sy.resize(rays)
	for k in rays:
		var a := TAU * float(k) / float(rays)
		var dx := cos(a)
		var dy := sin(a)
		sx[k] = dx * 0.5
		sy[k] = dy * 0.5
	_step_x[rays] = sx
	_step_y[rays] = sy


## Cast the rays from cell (cx, cy) with a sight radius of `rc` cells and
## return the cell numbers they reach. Each ray stops at (and includes) the
## first blocked cell.
func _cast(cx: int, cy: int, rc: int) -> PackedInt32Array:
	var cols := vision.cols
	var rows := vision.rows
	var blocked := vision.blocked
	# Step 1: a new cast number; the viewer's own cell is always seen.
	_mark_id += 1
	var out := PackedInt32Array()
	var origin := cx + cy * cols
	_mark[origin] = _mark_id
	out.append(origin)
	# Step 2: how many rays (at least 16), the radius squared (in cells),
	# and each ray's half-cell step (worked out once per ray count, see
	# _steps_for()).
	var rays := maxi(16, int(TAU * float(rc) * 1.5))
	var r2 := rc * rc
	var steps := rc * 2
	_steps_for(rays)
	var hx_all: PackedFloat64Array = _step_x[rays]
	var hy_all: PackedFloat64Array = _step_y[rays]
	var x0 := float(cx) + 0.5
	var y0 := float(cy) + 0.5
	for k in rays:
		# Step 3: this ray's half-cell step; start at the middle of our cell.
		var hx := hx_all[k]
		var hy := hy_all[k]
		var x := x0
		var y := y0
		for st in steps:
			# Step 4: half a cell further. Stop at the map edge, or past the
			# sight radius (measured from our cell, in whole cells; whole
			# numbers, so the squares are exact).
			x += hx
			y += hy
			var ix := int(x)
			var iy := int(y)
			if ix < 0 or iy < 0 or ix >= cols or iy >= rows:
				break
			var ox := ix - cx
			var oy := iy - cy
			if ox * ox + oy * oy > r2:
				break
			# Step 5: list the cell (once per cast), then stop if it is a
			# rock. The viewer's own cell never blocks its sight (a ship
			# beside a big rock would otherwise be blind in every direction).
			var idx := ix + iy * cols
			if _mark[idx] != _mark_id:
				_mark[idx] = _mark_id
				out.append(idx)
			if blocked[idx] == 1 and idx != origin:
				break
	return out
