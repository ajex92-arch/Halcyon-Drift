class_name AsteroidFieldQueries
extends RefCounted
## WHAT THIS IS: the "rock finder" of the AsteroidField (a part of it, kept
## in its own file). It answers "which rocks are near this spot?", "does
## this line hit a rock, and where first?" and "is this circle touching a
## rock?" quickly, without checking every rock on the map.
##
## HOW IT WORKS: a grid of squares GRID (400) world units wide is laid over
## the map. Each square keeps a list of the rocks that overlap it (a big
## rock is listed in every square it touches). A search only looks in the
## squares it covers. Because one rock can be listed in several of those
## squares, each search gets a new "stamp" number, and a rock is marked
## with it the first time it is seen, so it is never counted twice. Dead
## rocks are always skipped.
##
## A second, finer map answers "is any rock close to this spot at all?"
## even faster: clear_at() (see there). Units dodging rocks ask it first and
## skip the rock search in open space, where the answer is always "no push".
##
## WHO USES IT: AsteroidField makes one (AsteroidField.queries). Its
## _add() files each new rock (add_rock(); seal_tight_gaps() files a rock
## again when it has grown) and its build() calls make_room() once all
## rocks are in. AsteroidField.nearby(),
## segment_hit(), segment_blocked(), blocked() and clear_at() forward here;
## see AsteroidField for who asks those.

## Size (world units) of one grid square.
const GRID := 400.0
## The "clear space" map (see clear_at()): its squares are CLEAR_CELL (100)
## world units wide, and it records distances up to CLEAR_REACH (400)
## world units; anything further away is just "at least 400".
const CLEAR_CELL := 100.0
## The farthest distance the clear-space map records (world units).
const CLEAR_REACH := 400.0
## Per square of the clear-space map: how far its centre is from the
## nearest rock's edge (world units; negative inside a rock), at most
## CLEAR_REACH. Built on the first clear_at() call (empty before that).
var _clear := PackedFloat32Array()
## Columns of the clear-space map.
var _clear_cols := 0
## Rows of the clear-space map.
var _clear_rows := 0

## The asteroid field this part searches (we read its pos, rad and alive).
var field: AsteroidField
## How many grid squares across (enough for the map, plus one).
var cols := 1
## How many grid squares down (enough for the map, plus one).
var rows := 1
## The grid: one PackedInt32Array of rock numbers per square. Row by row
## from the top; square (cx, cy) is entry cx + cy * cols.
var grid: Array = []
## For every rock, the number of the last search that saw it (so a search
## counts each rock once). Sized by make_room().
var stamp := PackedInt32Array()
## The current search's number; goes up by one for every search.
var stamp_id := 0


## Remember the field and make an empty grid that covers the whole map.
func _init(owner_field: AsteroidField) -> void:
	field = owner_field
	cols = int(ceil(MapLayout.W / GRID)) + 1
	rows = int(ceil(MapLayout.H / GRID)) + 1
	grid.resize(cols * rows)
	for i in grid.size():
		grid[i] = PackedInt32Array()


## File rock number `i` (centre `p`, radius `r`) in every grid square its
## bounding square overlaps. Rocks near or past the map's edge go into the
## edge squares.
func add_rock(i: int, p: Vector2, r: float) -> void:
	var x0 := clampi(int((p.x - r) / GRID), 0, cols - 1)
	var x1 := clampi(int((p.x + r) / GRID), 0, cols - 1)
	var y0 := clampi(int((p.y - r) / GRID), 0, rows - 1)
	var y1 := clampi(int((p.y + r) / GRID), 0, rows - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			# Take the square's list, add the rock, and put it back.
			var cell: PackedInt32Array = grid[cx + cy * cols]
			cell.append(i)
			grid[cx + cy * cols] = cell


## Get ready for `count` rocks (one stamp per rock). Called once all rocks
## are in.
func make_room(count: int) -> void:
	stamp.resize(count)


## Rock indices whose grid cells overlap the circle (deduplicated).
## That is: every live rock listed in a grid square that the square around
## the circle (centre `p`, radius `r`) touches, each once. Some may be a
## little outside the circle; callers check the exact distance. Fills and
## returns `out` (it is cleared first).
func nearby(p: Vector2, r: float, out: PackedInt32Array) -> PackedInt32Array:
	var alive := field.alive
	out.clear()
	stamp_id += 1
	# The grid squares the circle's bounding square covers.
	var x0 := clampi(int((p.x - r) / GRID), 0, cols - 1)
	var x1 := clampi(int((p.x + r) / GRID), 0, cols - 1)
	var y0 := clampi(int((p.y - r) / GRID), 0, rows - 1)
	var y1 := clampi(int((p.y + r) / GRID), 0, rows - 1)
	# Every live rock in them, once (the stamp marks the ones already seen).
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			for i in (grid[cx + cy * cols] as PackedInt32Array):
				if alive[i] == 1 and stamp[i] != stamp_id:
					stamp[i] = stamp_id
					out.append(i)
	return out


## First rock the segment a->b (thickened by pad) touches:
## {"index": i, "t": 0..1} or {} if clear. `t` is how far along a->b the
## line first touches the rock (0 = at a, 1 = at b); "thickened by pad"
## means each rock counts as 95% of its radius plus `pad` (for example a
## bullet's radius). A long line (more than 12 grid squares in its bounding box) is
## handed to _segment_hit_long() instead.
func segment_hit(a: Vector2, b: Vector2, pad: float) -> Dictionary:
	var pos := field.pos
	var rad := field.rad
	var alive := field.alive
	var best_t := 2.0
	var best := -1
	# The grid squares the line's (padded) bounding box covers.
	var x0 := clampi(int((minf(a.x, b.x) - pad) / GRID), 0, cols - 1)
	var x1 := clampi(int((maxf(a.x, b.x) + pad) / GRID), 0, cols - 1)
	var y0 := clampi(int((minf(a.y, b.y) - pad) / GRID), 0, rows - 1)
	var y1 := clampi(int((maxf(a.y, b.y) + pad) / GRID), 0, rows - 1)
	# Long segments (beams, line of sight) walk cells along the line instead.
	if (x1 - x0 + 1) * (y1 - y0 + 1) > 12:
		return _segment_hit_long(a, b, pad)
	# Test every live rock in those squares once; keep the earliest hit.
	stamp_id += 1
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			for i in (grid[cx + cy * cols] as PackedInt32Array):
				if alive[i] == 0 or stamp[i] == stamp_id:
					continue
				stamp[i] = stamp_id
				var t := Util.seg_circle_t(a, b, pos[i], rad[i] * 0.95 + pad)
				if t >= 0.0 and t < best_t:
					best_t = t
					best = i
	if best < 0:
		return {}
	return {"index": best, "t": best_t}


## segment_hit() for long lines. Instead of every square in the bounding
## box, it walks along the line in steps of half a square, and at each step
## checks the 3 by 3 squares around that point. It stops early once the
## best hit so far lies before the point it has reached (nothing further on
## can be earlier).
func _segment_hit_long(a: Vector2, b: Vector2, pad: float) -> Dictionary:
	var pos := field.pos
	var rad := field.rad
	var alive := field.alive
	var length := a.distance_to(b)
	var steps := int(ceil(length / (GRID * 0.5))) + 1
	stamp_id += 1
	var best_t := 2.0
	var best := -1
	for s in steps + 1:
		# The point `s` steps along the line, and its grid square.
		var p := a.lerp(b, float(s) / float(steps))
		var cx := clampi(int(p.x / GRID), 0, cols - 1)
		var cy := clampi(int(p.y / GRID), 0, rows - 1)
		# That square and its 8 neighbours (skipping any off the grid).
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var gx := cx + dx
				var gy := cy + dy
				if gx < 0 or gy < 0 or gx >= cols or gy >= rows:
					continue
				# Test each live rock there once; keep the earliest hit.
				for i in (grid[gx + gy * cols] as PackedInt32Array):
					if alive[i] == 0 or stamp[i] == stamp_id:
						continue
					stamp[i] = stamp_id
					var t := Util.seg_circle_t(a, b, pos[i], rad[i] * 0.95 + pad)
					if t >= 0.0 and t < best_t:
						best_t = t
						best = i
		# A hit before this point can't be beaten by rocks further on.
		if best >= 0 and best_t <= float(s) / float(steps):
			break
	if best < 0:
		return {}
	return {"index": best, "t": best_t}


## True if a rock blocks the straight line between a and b.
func segment_blocked(a: Vector2, b: Vector2) -> bool:
	return not segment_hit(a, b, 0.0).is_empty()


## True if a circle at p overlaps any rock. Unlike segment_hit(), this
## uses each live rock's full radius. It searches 300 world units wider
## than the circle, then checks the exact distance.
func blocked(p: Vector2, r: float) -> bool:
	var pos := field.pos
	var rad := field.rad
	var tmp := PackedInt32Array()
	nearby(p, r + 300.0, tmp)
	for i in tmp:
		if p.distance_to(pos[i]) < rad[i] + r:
			return true
	return false


## True when the edge of EVERY rock is at least `need` world units from
## point `p`: a quick, safe "nothing to dodge here" test. (Units that steer
## around rocks ask this first; in open space it saves the rock search.)
## It reads the clear-space map (built the first time it is needed):
## for each 100-unit square, how far its centre is from the nearest rock's
## edge. A point is at most 70.8 world units (half a square's diagonal)
## from its square's centre, so we take that off, plus 1 more for rounding.
## Rocks never move, and destroyed rocks only make space clearer, so the map
## can underestimate the distance but never overestimate it: when this
## says "clear", the rock search would have found nothing. Points off the
## map always get "not clear" (the map doesn't cover them).
func clear_at(p: Vector2, need: float) -> bool:
	if _clear.is_empty():
		_build_clear()
	if p.x < 0.0 or p.y < 0.0:
		return false
	var cx := int(p.x / CLEAR_CELL)
	var cy := int(p.y / CLEAR_CELL)
	if cx >= _clear_cols or cy >= _clear_rows:
		return false
	return _clear[cx + cy * _clear_cols] - 71.8 >= need


## Throw the clear-space map away, so that the next clear_at() builds it
## again. AsteroidField.seal_tight_gaps() calls it after it has made rocks
## bigger (the map would otherwise keep the old, larger distances).
func reset_clear() -> void:
	_clear = PackedFloat32Array()


## Build the clear-space map: start every square at CLEAR_REACH, then let
## every rock (living or dead: counting dead ones only makes the map more
## careful) lower the squares within CLEAR_REACH of its edge to their real
## distance from it.
func _build_clear() -> void:
	_clear_cols = int(ceil(MapLayout.W / CLEAR_CELL)) + 1
	_clear_rows = int(ceil(MapLayout.H / CLEAR_CELL)) + 1
	_clear.resize(_clear_cols * _clear_rows)
	_clear.fill(CLEAR_REACH)
	var pos := field.pos
	var rad := field.rad
	for i in pos.size():
		var c := pos[i]
		var r := rad[i]
		# The squares that can be within CLEAR_REACH of this rock's edge.
		var span := r + CLEAR_REACH
		var x0 := clampi(int((c.x - span) / CLEAR_CELL), 0, _clear_cols - 1)
		var x1 := clampi(int((c.x + span) / CLEAR_CELL), 0, _clear_cols - 1)
		var y0 := clampi(int((c.y - span) / CLEAR_CELL), 0, _clear_rows - 1)
		var y1 := clampi(int((c.y + span) / CLEAR_CELL), 0, _clear_rows - 1)
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				# Distance from the square's centre to this rock's edge; keep
				# the smallest.
				var centre := Vector2((float(cx) + 0.5) * CLEAR_CELL, (float(cy) + 0.5) * CLEAR_CELL)
				var edge := centre.distance_to(c) - r
				var k := cx + cy * _clear_cols
				if edge < _clear[k]:
					_clear[k] = edge
