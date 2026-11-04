class_name MapBuilderRoute
extends RefCounted
## WHAT THIS IS: step 7 of the map maker (a part of MapBuilder, kept in its
## own file). It draws the "route graph": a road map of dots ("nodes") and
## straight links between them ("edges") that AI ships and drones follow
## to get around the asteroids (see RouteGraph).
##
## HOW IT WORKS: dots are added in this order (no random numbers):
##   1. One base dot just off each mothership's bow (its front).
##   2. Dots along each lane, at most MapBuilder.LANE_NODE_STEP (1,400
##      world units) apart, each linked to the one before. Lane dots inside
##      a mothership's BASE_NODE_OFFSET are moved onto its base dot.
##   3. Dots along the connector, linked the same way, and also linked to
##      every lane dot close by, so the connector joins all three lanes. A
##      dot that would land inside an ore node's field is split into two,
##      one each side of the field, so no route goes through the ore rocks.
##   4. Jungle entrances: a dot on the lane at each entrance (linked to the
##      nearest lane dot) and a jungle dot just inside, linked to it.
##   5. A jungle dot at every camp.
##   6. Dots along the winding jungle paths, at most
##      MapBuilder.PATH_NODE_STEP (450) apart, each linked to the one before.
## Dots in the jungle, and the links that lead into it, are marked "small
## only": only small ships may use them. Two dots that would land in the
## same 20 by 20 square are merged into one (_node_at()); that is how the
## ends of paths, camps and entrances join up.
##
## WHO USES IT: only MapBuilder._run(), which makes one, calls run() once
## and throws it away. The finished graph is World.map.route.

## The map builder this part works for. We read its map (info) and fill
## in info.route.
var mb: MapBuilder


## Remember the builder. MapBuilder makes this part once per map.
func _init(builder: MapBuilder) -> void:
	mb = builder


## Build the whole route graph (see HOW IT WORKS).
func run() -> void:
	var info := mb.info
	var g := info.route
	# Which dot sits in which 20 by 20 square (see _node_at()).
	var by_pos := {}
	# Step 1: the base dot sits just off each mothership's bow, not at its
	# centre. Playtest (2026-10-14): lanes start at the centre, and a route
	# dot inside the hull pinned launching ships against it for minutes.
	var bows: Array = []
	for t in 2:
		var bow: Vector2 = info.mothership_pos[t] + Vector2.from_angle(info.mothership_facing[t]) * MapBuilder.BASE_NODE_OFFSET
		bows.append(bow)
		_node_at(g, by_pos, bow, false)
	# Step 2: the lanes. Each lane is cut into `steps` equal pieces, with a
	# dot at both ends of every piece. `lane_nodes` remembers every lane dot.
	var lane_nodes: Array = []
	for id: String in MapLayout.LANE_ORDER:
		var pts: PackedVector2Array = info.lanes[id]
		var total := Util.polyline_length(pts)
		var steps := int(ceil(total / MapBuilder.LANE_NODE_STEP))
		var prev := -1
		for k in steps + 1:
			var p := Util.polyline_at(pts, total * float(k) / float(steps))
			# Too close to a mothership: use its base dot instead.
			for t in 2:
				if p.distance_to(info.mothership_pos[t]) < MapBuilder.BASE_NODE_OFFSET:
					p = bows[t]
			var nid := _node_at(g, by_pos, p, false)
			lane_nodes.append(nid)
			if prev >= 0:
				g.connect_nodes(prev, nid, false)
			prev = nid
	# Step 3: the connector joins all three lanes. A connector dot that falls
	# inside an ore node's field (The Crossing sits on the connector) would
	# lead ships through the ore rocks, so it becomes two dots, one each side
	# of the field (1,050 world units either side of the node's centre).
	# `cprev` holds the dot(s) of the previous position along the connector.
	var ctotal := Util.polyline_length(info.connector)
	var csteps := int(ceil(ctotal / MapBuilder.LANE_NODE_STEP))
	var cprev: Array = []
	for k in csteps + 1:
		var p := Util.polyline_at(info.connector, ctotal * float(k) / float(csteps))
		var group: Array = [p]
		for nd: Dictionary in info.nodes:
			var np: Vector2 = nd["pos"]
			if p.distance_to(np) < MapLayout.NODE_RADIUS + 300.0:
				group = [Vector2(np.x - 1050.0, p.y), Vector2(np.x + 1050.0, p.y)]
				break
		var ids: Array = []
		for q: Vector2 in group:
			var nid := _node_at(g, by_pos, q, false)
			ids.append(nid)
			for a: int in cprev:
				g.connect_nodes(a, nid, false)
			# Tie into any lane dot close by (within 1.1 times LANE_NODE_STEP).
			for ln: int in lane_nodes:
				if g.pos[ln].distance_to(q) < MapBuilder.LANE_NODE_STEP * 1.1 and ln != nid:
					g.connect_nodes(ln, nid, false)
		cprev = ids
	# Step 4: jungle entrances (both halves). A lane dot at the entrance,
	# linked to the nearest lane dot; then a jungle dot just inside, linked
	# to it by a small-only link.
	for e: Dictionary in info.entrances:
		var ln := _node_at(g, by_pos, e["lane"], false)
		var near := _nearest_of(g, lane_nodes, e["lane"])
		if near >= 0 and near != ln:
			g.connect_nodes(near, ln, false)
		var inside := _node_at(g, by_pos, e["inside"], true)
		g.connect_nodes(ln, inside, true)
	# Step 5: a jungle dot at every camp.
	for c: Dictionary in info.camps:
		_node_at(g, by_pos, c["pos"], true)
	# Step 6: the winding jungle paths. Skip the short 2-point gate paths:
	# the entrance links from step 4 already cover them.
	for pl: PackedVector2Array in info.jungle_paths:
		if pl.size() == 2:
			continue
		var total := Util.polyline_length(pl)
		var steps := maxi(1, int(ceil(total / MapBuilder.PATH_NODE_STEP)))
		var prev := -1
		for k in steps + 1:
			var p := Util.polyline_at(pl, total * float(k) / float(steps))
			var nid := _node_at(g, by_pos, p, true)
			if prev >= 0:
				g.connect_nodes(prev, nid, true)
			prev = nid


## The dot at `p`, making a new one if needed, and return its number. Two
## spots that round to the same 20 by 20 square (world units) share one
## dot. `jungle` marks a new dot as small-ships-only; a dot that already
## exists keeps its old mark.
func _node_at(g: RouteGraph, by_pos: Dictionary, p: Vector2, jungle: bool) -> int:
	var key := Vector2i(roundi(p.x / 20.0), roundi(p.y / 20.0))
	if by_pos.has(key):
		return by_pos[key]
	var id := g.add_node(p, jungle)
	by_pos[key] = id
	return id


## Of the dots listed in `ids`, the one closest to `p` (-1 if the list is
## empty). On a tie, the one listed first wins.
func _nearest_of(g: RouteGraph, ids: Array, p: Vector2) -> int:
	var best := -1
	var bd := INF
	for i: int in ids:
		var d := g.pos[i].distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best
