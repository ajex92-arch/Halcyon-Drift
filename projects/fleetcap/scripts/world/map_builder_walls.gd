class_name MapBuilderWalls
extends RefCounted
## WHAT THIS IS: step 4 of the map maker (a part of MapBuilder, kept in its
## own file). It builds the lane walls: rows of rocks along both edges of
## every corridor (the three lanes and the connector), so the jungle is
## sealed off from the lanes except at the gates.
##
## HOW IT WORKS: for each corridor, in MapBuilder.corridors order, and for
## each of its two edges (side +1, then side -1):
##   1. _walk_side() walks along the edge from start to end, dropping one
##      rock after another with random sizes and small random gaps (this
##      uses random numbers). Where a jungle entrance opens on this edge it
##      puts a "gate" instead: two big rocks (MapBuilder.GATE_R) with a gap
##      of MapLayout.CHOKE_GAP (86 world units) between their edges (on a
##      straight stretch), which only strike craft fit through.
##   2. _corner_fill() plugs the wedge-shaped holes the straight walk leaves
##      on the outside of each bend, with a fan of rocks (no random numbers).
## Every rock goes through _try_rock(), which throws it away if it would
## poke into a corridor, a base clearing or an ore node, or if it is on
## Cinder's half (that half gets mirror copies in MapBuilder._emit_rocks()).
##
## Sides: a corridor's centre line runs from its first point to its last.
## Side +1 is the edge on your right as you walk it that way on screen
## (where +Y points down), side -1 the edge on your left. "s" always means a
## distance measured along the centre line from its first point (world
## units).
##
## WHO USES IT: only MapBuilder._run(), which makes one, calls run() once
## and throws it away.

## The map builder this part works for. We use its random numbers (rng),
## its map (info) and its lists (corridors, gates, node_keep, rocks).
var mb: MapBuilder


## Remember the builder. MapBuilder makes this part once per map.
func _init(builder: MapBuilder) -> void:
	mb = builder


## Wall in every corridor: both edges, each walked and then corner-filled.
func run() -> void:
	for c: Dictionary in mb.corridors:
		var pts: PackedVector2Array = c["pts"]
		var half: float = c["half"]
		for side: float in [1.0, -1.0]:
			_walk_side(c["id"], pts, half, side)
			_corner_fill(pts, half, side)


## Place wall rocks along one edge (`side`) of corridor `cid`, inserting a
## gate at every jungle entrance that opens on this edge. `pts` is the
## corridor's centre line and `half` half its width (world units).
func _walk_side(cid: String, pts: PackedVector2Array, half: float, side: float) -> void:
	var total := Util.polyline_length(pts)
	# Step 1: the gates on this edge, nearest the start first. A gate
	# belongs to the side its entrance opens to (its direction into the
	# jungle points out through this edge).
	var my_gates: Array = []
	for g: Dictionary in mb.gates:
		if g["corridor"] != cid:
			continue
		var at := _offset_point(pts, float(g["s"]), half, side)
		if ((at["normal"] as Vector2) * side).dot(g["dir"]) > 0.5:
			my_gates.append(g)
	my_gates.sort_custom(func(x, y): return float(x["s"]) < float(y["s"]))
	# Step 2: walk the edge. `s` is the centre of the next rock and `r` its
	# radius; `gi` is the next gate to place.
	var s := 0.0
	var gi := 0
	var r := mb.rng.range_f(MapBuilder.EDGE_R_MIN, MapBuilder.EDGE_R_MAX)
	s += r
	while s < total + r:
		if gi < my_gates.size():
			# The next gate: its first rock is centred at `gate_left`, its
			# second one CHOKE_GAP + 2 * GATE_R further on.
			var gs: float = float(my_gates[gi]["s"])
			var gate_left := gs - JungleBigFeature.choke_gap() * 0.5 - MapBuilder.GATE_R
			if s + r > gate_left - MapBuilder.GATE_R:
				# The next rock would bump into the gate. Instead: if there is
				# a big hole between the last rock (about where it ended,
				# counting the smallest gap) and the gate, plug it with one
				# rock sized to fit; then place the gate pair.
				var prev_end := s - r - MapBuilder.EDGE_GAP_MIN
				var room := (gate_left - MapBuilder.GATE_R) - prev_end
				if room > MapBuilder.EDGE_GAP_MAX:
					var fr := room * 0.5 + 10.0
					_wall_rock(pts, prev_end + room * 0.5, half, side, fr)
				_wall_rock(pts, gate_left, half, side, MapBuilder.GATE_R)
				_wall_rock(pts, gs + JungleBigFeature.choke_gap() * 0.5 + MapBuilder.GATE_R, half, side, MapBuilder.GATE_R)
				# Carry on just past the gate's second rock with a new random
				# radius (first) and gap (second).
				s = gs + JungleBigFeature.choke_gap() * 0.5 + 2.0 * MapBuilder.GATE_R
				gi += 1
				r = mb.rng.range_f(MapBuilder.EDGE_R_MIN, MapBuilder.EDGE_R_MAX)
				s += mb.rng.range_f(MapBuilder.EDGE_GAP_MIN, MapBuilder.EDGE_GAP_MAX) + r
				continue
		# An ordinary wall rock. Then pick the next rock's radius (first) and
		# the gap to it (second), and move on to its centre.
		_wall_rock(pts, s, half, side, r)
		var nr := mb.rng.range_f(MapBuilder.EDGE_R_MIN, MapBuilder.EDGE_R_MAX)
		s += r + mb.rng.range_f(MapBuilder.EDGE_GAP_MIN, MapBuilder.EDGE_GAP_MAX) + nr
		r = nr


## Where a corridor bends, the two straight walks leave a wedge-shaped hole
## on the outside of the bend; fill it with a fan of rocks (of the average
## wall radius) around the bend point. This runs on both edges: on the
## inside of a bend, fan rocks that land in the corridor are thrown away by
## _try_rock().
func _corner_fill(pts: PackedVector2Array, half: float, side: float) -> void:
	for i in range(1, pts.size() - 1):
		# The edge's outward direction before (n0) and after (n1) the bend
		# point pts[i], and the angle `d` between them.
		var t0 := (pts[i] - pts[i - 1]).normalized()
		var t1 := (pts[i + 1] - pts[i]).normalized()
		var n0 := Vector2(-t0.y, t0.x) * side
		var n1 := Vector2(-t1.y, t1.x) * side
		var a0 := n0.angle()
		var d := Util.ang_diff(a0, n1.angle())
		# Nearly straight (under 0.05 radians): no hole to fill.
		if absf(d) < 0.05:
			continue
		# Rocks on an arc of radius `half + r` around the bend point, spaced
		# so neighbours are about EDGE_GAP_MIN apart, from n0 round to n1.
		var r := (MapBuilder.EDGE_R_MIN + MapBuilder.EDGE_R_MAX) * 0.5
		var arc_r := half + r
		var step := (2.0 * r + MapBuilder.EDGE_GAP_MIN) / arc_r
		var n := int(ceil(absf(d) / step))
		for k in range(0, n + 1):
			var a := a0 + d * float(k) / float(maxi(1, n))
			_try_rock(pts[i] + Vector2.from_angle(a) * arc_r, r, false)


## The spot `s` world units along a centre line `pts`, as a Dictionary:
## "center" = that point on the centre line, "normal" = the direction
## straight out to the right of the line there (length 1; multiply by
## `side` for the edge you want), "point" = the matching spot on the
## `side` edge, `half` away. Past the end it uses the last segment's end
## (a negative `s` gives the first point). If the line has fewer than two
## points it returns the first point.
func _offset_point(pts: PackedVector2Array, s: float, half: float, side: float) -> Dictionary:
	var left := s
	for i in pts.size() - 1:
		# Find the segment that `s` falls on (or the last one).
		var seg := pts[i].distance_to(pts[i + 1])
		if left <= seg or i == pts.size() - 2:
			var t := (pts[i + 1] - pts[i]).normalized()
			var n := Vector2(-t.y, t.x)
			var c := pts[i] + t * clampf(left, 0.0, seg)
			return {"center": c, "normal": n, "point": c + n * side * half}
		left -= seg
	return {"center": pts[0], "normal": Vector2.UP, "point": pts[0]}


## Try to place a wall rock of radius `r` whose centre is `s` along the
## centre line: it sits just outside the `side` edge, touching it.
func _wall_rock(pts: PackedVector2Array, s: float, half: float, side: float, r: float) -> void:
	var o := _offset_point(pts, s, half, side)
	var p: Vector2 = (o["center"] as Vector2) + (o["normal"] as Vector2) * side * (half + r)
	_try_rock(p, r, false)


## Keep a wall rock at `p` (radius `r`) unless it would intrude on open
## space. (`_is_node` is not used; every caller passes false.)
func _try_rock(p: Vector2, r: float, _is_node: bool) -> void:
	# Cinder's half gets mirror copies instead (1 unit of slack).
	if p.x > MapLayout.CX + 1.0:
		return
	# Too far off the map's left, top or bottom edge.
	if p.x < -r * 0.5 or p.y < -r * 0.5 or p.y > MapLayout.H + r * 0.5:
		return
	# Inside a corridor (a wall rock may poke in by up to 0.4 of its radius).
	for c: Dictionary in mb.corridors:
		if Util.dist_to_polyline(p, c["pts"]) < float(c["half"]) + r * 0.6:
			return
	# Inside a base clearing (it may poke in by up to half its radius).
	for mp: Vector2 in mb.info.mothership_pos:
		if p.distance_to(mp) < MapLayout.BASE_CLEAR_RADIUS + r * 0.5:
			return
	# Touching an ore node's area.
	for k: Dictionary in mb.node_keep:
		if p.distance_to(k["c"]) < float(k["r"]) + r:
			return
	mb.rocks.append({"p": p, "r": r, "node": false, "mirror": true})
