extends RefCounted
## WHAT THIS IS: the "plan" half of the map check (tests/map_check.gd): the
## checks that compare the finished map (MapInfo) with the plan it was built
## from (MapLayout). The map's size and frame, the width of every lane as the
## game itself reads it, clear space around ore nodes and monster camps, and
## the left-right mirror (Aurelian's half against Cinder's).
##
## HOW IT WORKS: every expected number is read from MapLayout or MapInfo, never
## written into this file, so a new map layout (a taller map, narrower lanes,
## different nodes) is checked against its own plan without touching the test.
## Each check adds rows to the list it is given (a row is {level, name,
## detail}; the level is "pass", "fail", "warn" or "info") and puts its
## numbers into a dictionary that the test prints as the MAP_JSON line.
## "Static" functions: they belong to the class itself and keep no state.
##
## Which rocks are used: the plan's rules (the clear space around nodes and
## camps, the mirror) are checked on MapInfo's rock lists, which are exactly
## what MapBuilder made. What a ship can physically pass is checked on the
## AsteroidField instead (tests/lib/map_check_choke.gd), whose rocks were
## resized after the build (AsteroidField.seal_tight_gaps).
##
## WHO USES IT: tests/map_check.gd. The other two parts (map_check_choke.gd,
## map_check_routes.gd) use add() and check() from here.

## Two positions closer than this (world units) count as the same place; this
## is the slack of the mirror checks (a mirrored position is worked out in
## 32-bit numbers, so it can be a hair off).
const SAME := 0.05
## Slack (world units) for "at least this far apart" checks.
const EPS := 0.5
## A rock at least this far (world units) from the centre line is "left" or
## "right"; closer than that it counts as standing on the line (the map
## builder makes no mirror copy of such a rock).
const ON_LINE := 1.0


## Add a row to `rows`. `level` is "pass", "fail", "warn" or "info".
static func add(rows: Array, level: String, name: String, detail: String = "") -> void:
	rows.append({"level": level, "name": name, "detail": detail})


## Add a "pass" row when `ok`, else a "fail" row. Returns `ok`.
static func check(rows: Array, name: String, ok: bool, detail: String = "") -> bool:
	add(rows, "pass" if ok else "fail", name, detail)
	return ok


## A constant of MapLayout by name, or null when the plan has no such thing
## (the plan of a new layout may drop the Crossing, for example). This lets
## the test run on a plan that no longer has a part the old plan had.
static func plan_const(const_name: String) -> Variant:
	var script: GDScript = load("res://scripts/data/map_layout.gd")
	return script.get_script_constant_map().get(const_name)


# --- the frame ----------------------------------------------------------------------------------

## The map's size and frame: the centre line is in the middle, the two
## motherships are the plan's, mirror images of each other and on the map's
## horizontal middle, and everything the plan places lies inside the map.
static func frame(w: World, rows: Array, nums: Dictionary) -> void:
	var info := w.map
	var mw := MapLayout.W
	var mh := MapLayout.H
	nums["map"] = {"w": mw, "h": mh, "cx": MapLayout.CX, "rocks": info.rock_pos.size()}
	check(rows, "map size and centre line", absf(MapLayout.CX - mw * 0.5) < SAME,
		"%d x %d world units, centre line x=%d" % [int(mw), int(mh), int(MapLayout.CX)])
	# The motherships: as planned, mirrored, on the horizontal middle.
	var ms_ok := info.mothership_pos.size() == 2
	var ms_detail := ""
	if ms_ok:
		var m0: Vector2 = info.mothership_pos[0]
		var m1: Vector2 = info.mothership_pos[1]
		ms_ok = m0.distance_to(MapLayout.MOTHERSHIPS[0]["pos"]) < SAME and m1.distance_to(MapLayout.MOTHERSHIPS[1]["pos"]) < SAME
		ms_ok = ms_ok and MapLayout.mirror(m0).distance_to(m1) < SAME
		ms_ok = ms_ok and absf(m0.y - mh * 0.5) < SAME and absf(m1.y - mh * 0.5) < SAME
		ms_detail = "Aurelian (%d, %d), Cinder (%d, %d)" % [int(m0.x), int(m0.y), int(m1.x), int(m1.y)]
	check(rows, "motherships on the plan, mirrored, on the map's middle line", ms_ok, ms_detail)
	# Everything the plan places lies inside the map.
	var outside: Array = []
	for id: String in info.lanes:
		for p: Vector2 in info.lanes[id]:
			if p.x < 0.0 or p.y < 0.0 or p.x > mw or p.y > mh:
				outside.append("lane %s point (%d,%d)" % [id, int(p.x), int(p.y)])
	for n: Dictionary in info.nodes:
		var np: Vector2 = n["pos"]
		if np.x - MapLayout.NODE_RADIUS < 0.0 or np.y - MapLayout.NODE_RADIUS < 0.0 or np.x + MapLayout.NODE_RADIUS > mw or np.y + MapLayout.NODE_RADIUS > mh:
			outside.append("node %s" % n["id"])
	for c: Dictionary in info.camps:
		var cp: Vector2 = c["pos"]
		if cp.x < 0.0 or cp.y < 0.0 or cp.x > mw or cp.y > mh:
			outside.append("camp %s" % c["id"])
	for e: Dictionary in info.entrances:
		for key in ["lane", "inside"]:
			var ep: Vector2 = e[key]
			if ep.x < 0.0 or ep.y < 0.0 or ep.x > mw or ep.y > mh:
				outside.append("entrance %s point (%d,%d)" % [key, int(ep.x), int(ep.y)])
	# Rocks may reach a little past the edge (the rim), by their own size.
	var stray := 0
	for i in info.rock_pos.size():
		var rp := info.rock_pos[i]
		var r := info.rock_r[i]
		if rp.x < -r or rp.y < -r or rp.x > mw + r or rp.y > mh + r:
			stray += 1
	if stray > 0:
		outside.append("%d rocks outside the map" % stray)
	check(rows, "everything the plan places lies inside the map", outside.is_empty(), "" if outside.is_empty() else "; ".join(outside.slice(0, 6)))


# --- lane widths --------------------------------------------------------------------------------

## The width of every lane (and of the Crossing, if the plan has one), as the
## game reads it: the open-lane lookup (MapInfo.in_open_lane, a grid of
## OPEN_CELL-wide squares that the AI asks "is this open space?"). At a few
## clean places along each lane we walk across it, away from the centre line
## in small steps, until the lookup says "not open", and add the two distances.
## A lane's measured width must match its plan (2 x half) to within the grid's
## own resolution (one square across, a bit more on a diagonal lane).
static func lanes(w: World, rows: Array, nums: Dictionary) -> void:
	var info := w.map
	var widths := {}
	for c: Dictionary in _corridors(info):
		var id: String = c["id"]
		var half: float = c["half"]
		var plan_half: Variant = c["plan_half"]
		var ok := plan_half != null and absf(float(plan_half) - half) < SAME
		var samples := _lane_samples(info, c)
		var measured: Array = []
		var worst := 0.0
		var skipped := 0
		for s: Dictionary in samples:
			var n: Vector2 = s["normal"]
			var plus := _open_run(info, s["at"], n, half + 600.0)
			var minus := _open_run(info, s["at"], -n, half + 600.0)
			if plus < 0.0 or minus < 0.0:
				skipped += 1
				continue
			var width := plus + minus
			var tol := MapInfo.OPEN_CELL * (absf(n.x) + absf(n.y)) + 40.0
			measured.append(roundi(width))
			worst = maxf(worst, absf(width - 2.0 * half) - tol)
		var detail := "plan %d (half %d), measured %s (%d places)" % [roundi(2.0 * half), roundi(half), str(measured), measured.size()]
		if plan_half == null or not ok:
			detail += "; the built map's half-width differs from the plan's"
		if measured.is_empty():
			detail += "; no clean place to measure"
		widths[id] = {"plan": roundi(2.0 * half), "measured": measured, "skipped": skipped, "length": roundi(Util.polyline_length(c["pts"]))}
		check(rows, "lane %s width" % id, ok and not measured.is_empty() and worst <= 0.0, detail)
	nums["lane_widths"] = widths


## The corridors to measure: every lane of the plan, then the Crossing if
## both the plan and the built map still have one. Each is {id, half, pts,
## plan_half} (plan_half = the plan's own half-width, or null).
static func _corridors(info: MapInfo) -> Array:
	var out: Array = []
	for id: String in MapLayout.LANES:
		out.append({"id": id, "half": float(info.lane_half.get(id, 0.0)), "pts": info.lanes.get(id, PackedVector2Array()),
			"plan_half": float(MapLayout.LANES[id]["half"])})
	var conn: Variant = info.get("connector")
	var conn_half: Variant = info.get("connector_half")
	var plan_conn: Variant = plan_const("CONNECTOR")
	if conn is PackedVector2Array and (conn as PackedVector2Array).size() >= 2 and conn_half != null and plan_conn != null:
		out.append({"id": "connector", "half": float(conn_half), "pts": conn, "plan_half": float((plan_conn as Dictionary)["half"])})
	return out


## Up to three clean places on each long straight stretch of corridor `c`:
## [{at, normal}], where `normal` points across the corridor. "Clean" = well
## clear of the segment's ends (where the bends are), and nothing else that is
## open (a base clearing, another corridor) comes within a square's width of
## the line we will walk across it.
static func _lane_samples(info: MapInfo, c: Dictionary) -> Array:
	var pts: PackedVector2Array = c["pts"]
	var half: float = c["half"]
	var out: Array = []
	for i in pts.size() - 1:
		var a := pts[i]
		var seg := a.distance_to(pts[i + 1])
		var margin := 2.0 * half + 400.0
		if seg < 2.0 * margin + 200.0:
			continue
		var t := (pts[i + 1] - a) / seg
		var n := Vector2(-t.y, t.x)
		for f: float in [0.25, 0.5, 0.75]:
			var p := a + t * (margin + (seg - 2.0 * margin) * f)
			if _line_is_clean(info, c["id"], p - n * (half + 600.0), p + n * (half + 600.0)):
				out.append({"at": p, "normal": n})
	return out


## True when the line from `from` to `to` stays clear of every other open
## area: the base clearings, and all corridors except the one named `own`.
static func _line_is_clean(info: MapInfo, own: String, from: Vector2, to: Vector2) -> bool:
	var steps := int(from.distance_to(to) / 100.0) + 1
	for k in steps + 1:
		var p := from.lerp(to, float(k) / float(steps))
		for mp: Vector2 in info.mothership_pos:
			if p.distance_to(mp) < MapLayout.BASE_CLEAR_RADIUS + MapInfo.OPEN_CELL:
				return false
		for id: String in info.lanes:
			if id != own and Util.dist_to_polyline(p, info.lanes[id]) < float(info.lane_half[id]) + MapInfo.OPEN_CELL:
				return false
		var conn: Variant = info.get("connector")
		if own != "connector" and conn is PackedVector2Array and (conn as PackedVector2Array).size() >= 2:
			if Util.dist_to_polyline(p, conn) < float(info.get("connector_half")) + MapInfo.OPEN_CELL:
				return false
	return true


## How far from `at`, going in direction `dir`, the open-lane lookup stays
## "open": the distance of the first probe (every 20 units) that is not open.
## -1 when it never closes within `cap` units (it ran into some other open
## area, so this is no measure of one lane's width).
static func _open_run(info: MapInfo, at: Vector2, dir: Vector2, cap: float) -> float:
	var d := 0.0
	while d <= cap:
		if not info.in_open_lane(at + dir * d):
			return d
		d += 20.0
	return -1.0


# --- clear space around nodes and camps -------------------------------------------------------

## No ordinary rock inside an ore node's area (MapLayout.NODE_RADIUS), every
## ore rock inside its own node's area, each node's ore list matching the
## rocks of the map, and every monster camp kept MapLayout.CAMP_CLEAR_RADIUS
## clear of rocks. A rock's edge, not its centre, counts.
static func clearances(w: World, rows: Array, nums: Dictionary) -> void:
	var info := w.map
	var nr := MapLayout.NODE_RADIUS
	# Nodes: the closest an ordinary rock's edge comes to each node's centre.
	var worst_node := INF
	var node_bad: Array = []
	for n: Dictionary in info.nodes:
		var np: Vector2 = n["pos"]
		var closest := INF
		for i in info.rock_pos.size():
			if info.rock_node[i] == 0:
				closest = minf(closest, info.rock_pos[i].distance_to(np) - info.rock_r[i])
		worst_node = minf(worst_node, closest)
		if closest < nr - EPS:
			node_bad.append("%s (%.0f)" % [n["id"], closest])
	check(rows, "no ordinary rock inside a node's area", node_bad.is_empty(),
		"%d nodes, area radius %d, closest ordinary rock edge %.0f from a node centre%s" % [info.nodes.size(), int(nr), worst_node, "" if node_bad.is_empty() else "; too close: " + ", ".join(node_bad)])
	nums["node_rock_clearance"] = snappedf(worst_node, 0.1)
	# Ore rocks: each inside its own node's area, and the node's ore list is
	# made of exactly those rocks (the world's ResourceNodes hold the lists).
	var ore_total := 0
	var ore_outside := 0
	for i in info.rock_pos.size():
		if info.rock_node[i] == 0:
			continue
		ore_total += 1
		var inside := false
		for n: Dictionary in info.nodes:
			if info.rock_pos[i].distance_to(n["pos"]) + info.rock_r[i] <= nr + EPS:
				inside = true
		if not inside:
			ore_outside += 1
	var listed := 0
	var count_ok := true
	for rn: ResourceNode in w.nodes:
		listed += rn.ore_pos.size()
		count_ok = count_ok and rn.ore_pos.size() >= 1
	check(rows, "ore rocks sit inside their node's area", ore_outside == 0 and listed == ore_total and count_ok,
		"%d ore rocks, %d listed by the %d nodes, %d outside every node area" % [ore_total, listed, w.nodes.size(), ore_outside])
	nums["ore_rocks"] = ore_total
	# Camps: the closest any rock's edge comes to a camp's spot.
	var worst_camp := INF
	var camp_bad: Array = []
	for c: Dictionary in info.camps:
		var cp: Vector2 = c["pos"]
		var closest := INF
		for i in info.rock_pos.size():
			closest = minf(closest, info.rock_pos[i].distance_to(cp) - info.rock_r[i])
		worst_camp = minf(worst_camp, closest)
		if closest < MapLayout.CAMP_CLEAR_RADIUS - EPS:
			camp_bad.append("%s (%.0f)" % [c["id"], closest])
	check(rows, "camps keep their clear radius", camp_bad.is_empty(),
		"%d camps, clear radius %d, closest rock edge %.0f%s" % [info.camps.size(), int(MapLayout.CAMP_CLEAR_RADIUS), worst_camp, "" if camp_bad.is_empty() else "; too close: " + ", ".join(camp_bad)])
	nums["camp_rock_clearance"] = snappedf(worst_camp, 0.1)


# --- the mirror -------------------------------------------------------------------------------------

## Aurelian's half and Cinder's half are mirror images (flip across the
## centre line, MapLayout.mirror): every Aurelian node, camp and entrance has
## its mirror with the same facts; anything on the centre line exists exactly
## once; the rocks pair up one for one (same size, same kind) and the two
## halves hold the same number.
static func mirror(w: World, rows: Array, nums: Dictionary) -> void:
	var info := w.map
	_mirror_nodes(info, rows)
	_mirror_camps(info, rows)
	_mirror_entrances(info, rows)
	_mirror_rocks(info, rows, nums)


## Nodes: side 0 (Aurelian) pairs with side 1 (Cinder) at the mirrored spot,
## with the same lane, kind, richness, number of turret slots, and ore and slot
## positions mirrored; a shared node (side -1) must stand on the centre line,
## once, with ore that is symmetric about it.
static func _mirror_nodes(info: MapInfo, rows: Array) -> void:
	var problems: Array = []
	var used := {}
	var pairs := 0
	var shared := 0
	for a: Dictionary in info.nodes:
		var side := int(a["side"])
		var ap: Vector2 = a["pos"]
		if side == 0:
			var b := _find_node(info, MapLayout.mirror(ap), 1, used)
			if b.is_empty():
				problems.append("%s has no mirror" % a["id"])
				continue
			used[b["id"]] = true
			pairs += 1
			for key in ["lane", "kind", "value"]:
				if a[key] != b[key]:
					problems.append("%s and %s differ in %s" % [a["id"], b["id"], key])
			if (a["slot_pos"] as PackedVector2Array).size() != (b["slot_pos"] as PackedVector2Array).size():
				problems.append("%s and %s differ in turret slots" % [a["id"], b["id"]])
			elif not _lists_mirror(a["slot_pos"], b["slot_pos"]):
				problems.append("%s and %s: slots are not mirrored" % [a["id"], b["id"]])
			if not _ore_mirrors(a["ore"], b["ore"]):
				problems.append("%s and %s: ore rocks are not mirrored" % [a["id"], b["id"]])
		elif side < 0:
			shared += 1
			if absf(ap.x - MapLayout.CX) > ON_LINE:
				problems.append("shared node %s is not on the centre line" % a["id"])
			elif not _ore_mirrors(a["ore"], a["ore"]):
				problems.append("shared node %s: ore is not symmetric" % a["id"])
	for b: Dictionary in info.nodes:
		if int(b["side"]) == 1 and not used.has(b["id"]):
			problems.append("%s has no mirror" % b["id"])
	# Anything twice at one spot?
	for i in info.nodes.size():
		for j in range(i + 1, info.nodes.size()):
			if (info.nodes[i]["pos"] as Vector2).distance_to(info.nodes[j]["pos"]) < ON_LINE:
				problems.append("%s and %s stand on the same spot" % [info.nodes[i]["id"], info.nodes[j]["id"]])
	check(rows, "nodes mirror, shared nodes once on the centre line", problems.is_empty(),
		"%d mirrored pairs, %d shared%s" % [pairs, shared, "" if problems.is_empty() else "; " + "; ".join(problems.slice(0, 6))])


## The node of side `side` standing at `at` that is not yet in `used`, or {}.
static func _find_node(info: MapInfo, at: Vector2, side: int, used: Dictionary) -> Dictionary:
	for n: Dictionary in info.nodes:
		if int(n["side"]) == side and not used.has(n["id"]) and (n["pos"] as Vector2).distance_to(at) < SAME:
			return n
	return {}


## Are the positions in `b` the mirror of those in `a` (same count, same
## order)? Both are PackedVector2Array.
static func _lists_mirror(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if MapLayout.mirror(a[i]).distance_to(b[i]) >= SAME:
			return false
	return true


## Is every ore rock of `a` ([{pos, r}]) matched by one of `b` at the mirrored
## spot with the same radius, and the other way round?
static func _ore_mirrors(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for pass_no in 2:
		var from: Array = a if pass_no == 0 else b
		var to: Array = b if pass_no == 0 else a
		for o: Dictionary in from:
			var found := false
			for q: Dictionary in to:
				if MapLayout.mirror(o["pos"]).distance_to(q["pos"]) < SAME and absf(float(o["r"]) - float(q["r"])) < 0.001:
					found = true
			if not found:
				return false
	return true


## Camps: each Aurelian-side camp (quarter tl or bl) pairs with a Cinder-side
## one (tr or br) of the same type at the mirrored spot; no two camps share a
## spot (a camp on the centre line would be made twice, once as itself and
## once as its mirror).
static func _mirror_camps(info: MapInfo, rows: Array) -> void:
	var problems: Array = []
	var used := {}
	var pairs := 0
	for a: Dictionary in info.camps:
		var q: String = a["quad"]
		if q != "tl" and q != "bl":
			continue
		var want := MapLayout.mirror(a["pos"])
		var hit := ""
		for b: Dictionary in info.camps:
			if (b["quad"] == "tr" or b["quad"] == "br") and not used.has(b["id"]) and (b["pos"] as Vector2).distance_to(want) < SAME and b["type"] == a["type"]:
				hit = b["id"]
				break
		if hit == "":
			problems.append("%s has no mirror" % a["id"])
		else:
			used[hit] = true
			pairs += 1
	for b: Dictionary in info.camps:
		if (b["quad"] == "tr" or b["quad"] == "br") and not used.has(b["id"]):
			problems.append("%s has no mirror" % b["id"])
	for i in info.camps.size():
		for j in range(i + 1, info.camps.size()):
			if (info.camps[i]["pos"] as Vector2).distance_to(info.camps[j]["pos"]) < ON_LINE:
				problems.append("camps %s and %s stand on the same spot" % [info.camps[i]["id"], info.camps[j]["id"]])
	check(rows, "camps mirror, none twice on one spot", problems.is_empty(),
		"%d camps in %d mirrored pairs%s" % [info.camps.size(), pairs, "" if problems.is_empty() else "; " + "; ".join(problems.slice(0, 6))])


## Entrances: each one on Aurelian's side (quarter tl or bl) pairs with one on
## Cinder's side whose lane point, inside point and edge point are mirrored.
static func _mirror_entrances(info: MapInfo, rows: Array) -> void:
	var problems: Array = []
	var used := {}
	var pairs := 0
	for i in info.entrances.size():
		var a: Dictionary = info.entrances[i]
		if a["quad"] != "tl" and a["quad"] != "bl":
			continue
		var hit := -1
		for j in info.entrances.size():
			var b: Dictionary = info.entrances[j]
			if (b["quad"] == "tr" or b["quad"] == "br") and not used.has(j) \
					and MapLayout.mirror(a["lane"]).distance_to(b["lane"]) < SAME and MapLayout.mirror(a["inside"]).distance_to(b["inside"]) < SAME \
					and MapLayout.mirror(a["edge"]).distance_to(b["edge"]) < SAME:
				hit = j
				break
		if hit < 0:
			problems.append("entrance at (%d,%d) has no mirror" % [int((a["lane"] as Vector2).x), int((a["lane"] as Vector2).y)])
		else:
			used[hit] = true
			pairs += 1
	check(rows, "entrances mirror", problems.is_empty() and pairs * 2 == info.entrances.size(),
		"%d entrances in %d mirrored pairs%s" % [info.entrances.size(), pairs, "" if problems.is_empty() else "; " + "; ".join(problems.slice(0, 6))])


## Rocks: the number on each half matches, every rock on the left has a rock on
## the right at the mirrored spot with the same radius and kind (ore or not),
## and a rock standing on the centre line exists once.
static func _mirror_rocks(info: MapInfo, rows: Array, nums: Dictionary) -> void:
	var cx := MapLayout.CX
	var left := 0
	var right := 0
	var line := 0
	var left_ore := 0
	var right_ore := 0
	# Rocks filed by 8-unit square, so a partner can be found without
	# looking at every rock.
	var grid := {}
	for i in info.rock_pos.size():
		var p := info.rock_pos[i]
		if p.x < cx - ON_LINE:
			left += 1
			left_ore += info.rock_node[i]
		elif p.x > cx + ON_LINE:
			right += 1
			right_ore += info.rock_node[i]
		else:
			line += 1
		var key := Vector2i(int(floorf(p.x / 8.0)), int(floorf(p.y / 8.0)))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	# Every left rock needs a partner (a right rock not yet taken).
	var taken := {}
	var unpaired := 0
	var example := ""
	for i in info.rock_pos.size():
		var p := info.rock_pos[i]
		if p.x >= cx - ON_LINE:
			continue
		var want := MapLayout.mirror(p)
		var found := -1
		var key := Vector2i(int(floorf(want.x / 8.0)), int(floorf(want.y / 8.0)))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cell: Array = grid.get(Vector2i(key.x + dx, key.y + dy), [])
				for j: int in cell:
					if found < 0 and not taken.has(j) and info.rock_pos[j].distance_to(want) < SAME \
							and absf(info.rock_r[j] - info.rock_r[i]) < 0.001 and info.rock_node[j] == info.rock_node[i]:
						found = j
		if found < 0:
			unpaired += 1
			if example == "":
				example = "(%d,%d) r%d" % [int(p.x), int(p.y), int(info.rock_r[i])]
		else:
			taken[found] = true
	# Rocks on the centre line: any two on top of each other?
	var doubled := 0
	for i in info.rock_pos.size():
		var p := info.rock_pos[i]
		if absf(p.x - cx) > ON_LINE:
			continue
		var key := Vector2i(int(floorf(p.x / 8.0)), int(floorf(p.y / 8.0)))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cell: Array = grid.get(Vector2i(key.x + dx, key.y + dy), [])
				for j: int in cell:
					if j > i and info.rock_pos[j].distance_to(p) < 0.5:
						doubled += 1
	var ok := left == right and left_ore == right_ore and unpaired == 0 and doubled == 0
	check(rows, "rocks mirror: same count each half, every rock paired, centre line once", ok,
		"left %d, right %d, on the line %d; ore %d / %d; unpaired %d%s; doubled on the line %d" % [left, right, line, left_ore, right_ore,
			unpaired, "" if example == "" else " (e.g. " + example + ")", doubled])
	nums["rocks_by_half"] = {"left": left, "right": right, "line": line, "left_ore": left_ore, "right_ore": right_ore}


# --- distances ------------------------------------------------------------------------------------------

## The smallest distances between the things the plan places (centre to
## centre, world units), for MAP_JSON: node-node, node-camp, camp-camp, how
## close nodes and camps lie to a lane's centre line, and to a mothership.
static func distances(w: World, nums: Dictionary) -> void:
	var info := w.map
	var nn := INF
	var nc := INF
	var cc := INF
	for i in info.nodes.size():
		var a: Vector2 = info.nodes[i]["pos"]
		for j in range(i + 1, info.nodes.size()):
			nn = minf(nn, a.distance_to(info.nodes[j]["pos"]))
		for c: Dictionary in info.camps:
			nc = minf(nc, a.distance_to(c["pos"]))
	for i in info.camps.size():
		for j in range(i + 1, info.camps.size()):
			cc = minf(cc, (info.camps[i]["pos"] as Vector2).distance_to(info.camps[j]["pos"]))
	var node_lane := INF
	var camp_lane := INF
	for id: String in info.lanes:
		for n: Dictionary in info.nodes:
			node_lane = minf(node_lane, Util.dist_to_polyline(n["pos"], info.lanes[id]) - float(info.lane_half[id]))
		for c: Dictionary in info.camps:
			camp_lane = minf(camp_lane, Util.dist_to_polyline(c["pos"], info.lanes[id]) - float(info.lane_half[id]))
	var node_ms := INF
	var camp_ms := INF
	for mp: Vector2 in info.mothership_pos:
		for n: Dictionary in info.nodes:
			node_ms = minf(node_ms, mp.distance_to(n["pos"]))
		for c: Dictionary in info.camps:
			camp_ms = minf(camp_ms, mp.distance_to(c["pos"]))
	nums["min_dist"] = {"node_node": snappedf(nn, 1.0), "node_camp": snappedf(nc, 1.0), "camp_camp": snappedf(cc, 1.0),
		"node_to_lane_edge": snappedf(node_lane, 1.0), "camp_to_lane_edge": snappedf(camp_lane, 1.0),
		"node_to_mothership": snappedf(node_ms, 1.0), "camp_to_mothership": snappedf(camp_ms, 1.0)}
