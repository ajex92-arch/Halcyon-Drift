class_name MapBuilderFill
extends RefCounted
## WHAT THIS IS: step 5 of the map maker (a part of MapBuilder, kept in its
## own file). It fills the rest of the map with asteroids: every spot that
## is not a lane, a base, an ore node, a camp or a jungle path gets rocks.
##
## HOW IT WORKS: we lay a grid of squares MapBuilder.FILL_SPACING (440
## world units) wide over Aurelian's half of the map (one extra row at the
## bottom). Row by row from the top, and left to right in each row, every
## square gets one try:
##   1. Take the square's middle, nudge it by a random amount (up to
##      MapBuilder.FILL_JITTER, 120 units, left/right and up/down) and pick
##      a random radius between FILL_R_MIN (130) and FILL_R_MAX (250).
##      Every square uses exactly 3 random numbers, even when its rock is
##      thrown away, so the sequence never depends on which rocks are kept.
##   2. Throw the rock away if it is too close to the centre line (its
##      mirror copy would overlap it), or if _fill_ok() says it is in the
##      way of open space.
##   3. Otherwise keep it; it gets a mirror copy on Vhorr's half later
##      (MapBuilder._emit_rocks()).
## Fill rocks may overlap lane wall rocks; only open space is protected.
##
## WHO USES IT: only MapBuilder._run(), which makes one, calls run() once
## and throws it away.

## The map builder this part works for. We use its random numbers (rng),
## its map (info) and its lists (corridors, keep_out, rocks).
var mb: MapBuilder


## Remember the builder. MapBuilder makes this part once per map.
func _init(builder: MapBuilder) -> void:
	mb = builder


## Try one fill rock per grid square (see HOW IT WORKS).
func run() -> void:
	# The grid: enough columns to cover Aurelian's half, enough rows (plus
	# one) to cover the map's height.
	var nx := int(ceil(MapLayout.CX / MapBuilder.FILL_SPACING))
	var ny := int(ceil(MapLayout.H / MapBuilder.FILL_SPACING)) + 1
	for gy in ny:
		for gx in nx:
			# Step 1: a random spot near the square's middle (2 random
			# numbers: x first, then y) and a random radius (1 more).
			var p := Vector2((float(gx) + 0.5) * MapBuilder.FILL_SPACING, (float(gy) + 0.5) * MapBuilder.FILL_SPACING)
			p += Vector2(mb.rng.next() - 0.5, mb.rng.next() - 0.5) * 2.0 * MapBuilder.FILL_JITTER
			var r := mb.rng.range_f(MapBuilder.FILL_R_MIN, MapBuilder.FILL_R_MAX)
			# Step 2: not too close to the centre line, and not in the way.
			if p.x > MapLayout.CX - r * 0.3:
				continue
			if not _fill_ok(p, r):
				continue
			# Step 3: keep it.
			mb.rocks.append({"p": p, "r": r, "node": false, "mirror": true})


## May a fill rock of radius `r` sit at `p`? False if it is too far off the
## map, or too close to a corridor (60 units to spare), a base clearing, a
## node or camp (MapBuilder.keep_out), or a jungle path (20 units to spare
## beyond the path's half-width MapLayout.PATH_HALF).
func _fill_ok(p: Vector2, r: float) -> bool:
	# More than a radius off the top, bottom or left edge of the map.
	if p.y < -r or p.y > MapLayout.H + r or p.x < -r:
		return false
	# Lanes and the connector.
	for c: Dictionary in mb.corridors:
		if Util.dist_to_polyline(p, c["pts"]) < float(c["half"]) + r + 60.0:
			return false
	# Base clearings around the motherships.
	for mp: Vector2 in mb.info.mothership_pos:
		if p.distance_to(mp) < MapLayout.BASE_CLEAR_RADIUS + r:
			return false
	# Ore nodes and camps.
	for k: Dictionary in mb.keep_out:
		if p.distance_to(k["c"]) < float(k["r"]) + r:
			return false
	# Jungle paths (Aurelian's and Vhorr's copies alike).
	for pl: PackedVector2Array in mb.info.jungle_paths:
		if Util.dist_to_polyline(p, pl) < JungleBigFeature.path_half() + r + 20.0:
			return false
	return true
