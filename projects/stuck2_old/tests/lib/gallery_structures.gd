class_name GalleryStructures
extends RefCounted
## WHAT THIS IS: the shape checks of the drawings of the mothership, the lane
## towers and the Repair Bay (StructureShapes), a part of the hull gallery
## (tests/hull_gallery.gd). They test the tables without drawing anything, so a
## bad table is caught by a pass/fail run (hull_gallery --check) and not by someone
## looking at a picture.
##
## HOW IT WORKS: run() goes through every structure in every dress it has (the
## Aurelian steel one, and the Vhorr dress for the towers and the bay, which adds
## thorn pieces), prints one "structure ..." line for each (its drawn size, pieces,
## outline points, nozzles and gun spots inside) and a "FAIL ..." line for every
## thing that fails, then one summary line for each check:
##   - every piece and every decal can be filled (Godot cuts a polygon into
##     triangles to fill it, and cannot for one that crosses itself);
##   - the outline AurelianPaint merges from the pieces is one polygon that can be
##     filled, has at most MAX_OUTLINE_POINTS points, reaches as far as the pieces
##     do and keeps every piece (a piece the merge dropped, such as a thorn that only
##     touches the hull at a point, would show as a vertex outside the outline);
##   - no hole: no point inside the outline is covered by no piece;
##   - the size: a tower or the Repair Bay is drawn no farther than 15% of its
##     radius past its hit circle (REACH_FACTOR times the radius, thorns included),
##     the mothership no farther than 15% of its radius past its hit capsule;
##   - every gun spot sits inside the outline and has a socket piece at its place (the
##     mothership's 21 spots from Structures.MOTHERSHIP, the middle of a tower or the
##     bay), and every socket lies inside the outline;
##   - every engine nozzle lies inside the outline.
## The hit sizes are read from the game's own data (Structures, TurretData), so a
## number that changes there is checked against the drawing.
##
## WHO USES IT: tests/hull_gallery.gd calls run() at the start of every run (with
## --check that is the whole run).

## The most points a merged structure outline may have.
const MAX_OUTLINE_POINTS := 120
## How far past its hit radius the drawing may reach, as a multiple (15% more).
const REACH_FACTOR := 1.15
## How far (design units) a gun spot's socket may be from the spot.
const SOCKET_SLACK := 0.3
## How close (design units) to the outline a piece's corner must be to count as
## kept by the merge.
const KEEP_SLACK := 0.06
## The structures, in the order they are checked.
const IDS := ["mothership", "pd_tower", "torp_tower", "repair_bay"]


## Run every check, print the results and return the number of failures.
static func run() -> int:
	var polygons := 0
	var outlines := 0
	var holes := 0
	var sizes := 0
	var mounts := 0
	var nozzles := 0
	var count := 0
	for id: String in IDS:
		var raw: Dictionary = StructureShapes.SHAPES[id]
		for vhorr: bool in ([false, true] if raw.has("vhorr") else [false]):
			count += 1
			var label := "%s (%s)" % [id, "vhorr" if vhorr else "aurelian"]
			var rec := AurelianPaint.structure(id, vhorr)
			var size := float(raw["size"])
			var u := size / 36.0
			var sil: PackedVector2Array = rec["sil"]
			polygons += _polygons(label, raw, vhorr)
			outlines += _outline(label, rec)
			holes += _holes(label, rec)
			sizes += _size(label, id, rec, u)
			var found := _mounts(label, id, rec, u)
			mounts += int(found[0])
			nozzles += _nozzles(label, rec)
			print("structure %-22s drawn %5.1f x %5.1f du (%6.1f x %6.1f)  reach %5.2f du  pieces %2d  outline points %3d  nozzles %d  gun spots inside %d of %d" % [
				label, _extent(rec).x, _extent(rec).y, _extent(rec).x * u, _extent(rec).y * u, _reach(rec), (rec["pieces"] as Array).size(), sil.size(), (rec["nozzles"] as Array).size(), int(found[1]), int(found[2])])
	print("structure polygons: %d drawings, %d pieces or decals cannot be filled" % [count, polygons])
	print("structure outlines: %d drawings, %d not one fillable polygon that keeps every piece" % [count, outlines])
	print("structure holes: %d drawings, %d with a hole" % [count, holes])
	print("structure sizes: %d drawings, %d reach too far past the hit shape" % [count, sizes])
	print("structure mounts: %d problems with gun spots and sockets" % mounts)
	print("structure nozzles: %d outside the outline" % nozzles)
	return polygons + outlines + holes + sizes + mounts + nozzles


## Check 1: every piece and decal of a drawing in `vhorr` dress can be filled.
static func _polygons(label: String, raw: Dictionary, vhorr: bool) -> int:
	var bad := 0
	var pieces: Array = raw["pieces"]
	if vhorr:
		pieces = pieces + (raw["vhorr"] as Array)
	for pc: Dictionary in pieces:
		if Geometry2D.triangulate_polygon(PackedVector2Array(pc["pts"])).is_empty():
			bad += 1
			print("FAIL polygon %s piece %s" % [label, pc["id"]])
		for mk: Dictionary in pc.get("marks", []):
			if mk["kind"] != "line" and Geometry2D.triangulate_polygon(PackedVector2Array(mk["pts"])).is_empty():
				bad += 1
				print("FAIL polygon %s piece %s decal %s" % [label, pc["id"], mk["kind"]])
	return bad


## Check 2: the outline is one fillable polygon of a sane size that keeps every piece.
static func _outline(label: String, rec: Dictionary) -> int:
	var bad := 0
	var sil: PackedVector2Array = rec["sil"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pc: Dictionary in rec["pieces"]:
		for p: Vector2 in pc["pts"]:
			lo = lo.min(p)
			hi = hi.max(p)
	var slo := Vector2(INF, INF)
	var shi := Vector2(-INF, -INF)
	for p: Vector2 in sil:
		slo = slo.min(p)
		shi = shi.max(p)
	if sil.size() > MAX_OUTLINE_POINTS or Geometry2D.triangulate_polygon(sil).is_empty() or not (lo - slo).abs().length() < 0.05 or not (hi - shi).abs().length() < 0.05:
		bad += 1
		print("FAIL outline %s: %d points, pieces reach %s to %s, outline %s to %s" % [label, sil.size(), lo, hi, slo, shi])
	# Every corner of every piece is inside the outline or on it: a piece the merge dropped is not.
	var lost := 0
	for pc: Dictionary in rec["pieces"]:
		for p: Vector2 in pc["pts"]:
			if not Geometry2D.is_point_in_polygon(p, sil) and _edge_distance(p, sil) > KEEP_SLACK:
				lost += 1
				if lost <= 3:
					print("FAIL outline %s: corner %s of piece %s is outside the outline (the merge dropped it?)" % [label, p, pc["id"]])
	if lost > 0:
		bad += 1
	return bad


## Check 3: no point inside the outline is covered by no piece (a hole would show
## the background through the structure). The outline is the outer edge of the merge.
static func _holes(label: String, rec: Dictionary) -> int:
	var sil: PackedVector2Array = rec["sil"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in sil:
		lo = lo.min(p)
		hi = hi.max(p)
	var gaps: Array = []
	# The grid starts a little inside the outline's box: a sample exactly on an
	# outer edge is inside the merged outline by a rounding hair and inside no piece.
	var x := lo.x + 0.13
	while x <= hi.x:
		var y := lo.y + 0.13
		while y <= hi.y:
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, sil):
				var covered := false
				for pc: Dictionary in rec["pieces"]:
					if Geometry2D.is_point_in_polygon(p, pc["pts"]):
						covered = true
						break
				if not covered:
					gaps.append(p)
			y += 0.3
		x += 0.3
	if gaps.size() > 2:
		print("FAIL hole %s: %d sample points inside the outline are covered by no piece, for example %s" % [label, gaps.size(), gaps.slice(0, 3)])
		return 1
	return 0


## Check 4: how far the drawing reaches past the structure's hit shape.
static func _size(label: String, id: String, rec: Dictionary, u: float) -> int:
	var sil: PackedVector2Array = rec["sil"]
	if id == "mothership":
		# The hit shape is a capsule of radius beam / 2 and a straight part of the rest of the length.
		var radius := float(Structures.MOTHERSHIP["beam"]) / 2.0
		var half_len := float(Structures.MOTHERSHIP["length"]) / 2.0
		var lim := Vector2(half_len + (REACH_FACTOR - 1.0) * radius, radius * REACH_FACTOR) / u
		var ext := Vector2.ZERO
		for p: Vector2 in sil:
			ext = ext.max(p.abs())
		if ext.x > lim.x or ext.y > lim.y:
			print("FAIL size %s: reaches %.2f x %.2f design units, the most is %.2f x %.2f" % [label, ext.x, ext.y, lim.x, lim.y])
			return 1
		return 0
	var most := REACH_FACTOR * _hit_radius(id) / u
	var reach := _reach(rec)
	if reach > most:
		print("FAIL size %s: reaches %.2f design units from the middle, the most is %.2f" % [label, reach, most])
		return 1
	return 0


## Check 5: every gun spot is inside the outline and has a socket at its place, and
## every socket piece lies inside the outline. Returns [problems, spots inside, spots].
static func _mounts(label: String, id: String, rec: Dictionary, u: float) -> Array:
	var bad := 0
	var sil: PackedVector2Array = rec["sil"]
	var spots: Array = _spots(id)
	var inside := 0
	for s: Dictionary in spots:
		var at: Vector2 = (s["off"] as Vector2) / u
		if Geometry2D.is_point_in_polygon(at, sil):
			inside += 1
		else:
			bad += 1
			print("FAIL mount %s %s at %s is outside the outline" % [label, s["w"], at])
		if not _has_socket(rec, at):
			bad += 1
			print("FAIL mount %s %s at %s has no socket piece" % [label, s["w"], at])
		if not TurretShapes.CLASS_BY_WEAPON.has(s["w"]):
			bad += 1
			print("FAIL mount %s %s has no turret class" % [label, s["w"]])
	for pc: Dictionary in rec["pieces"]:
		if pc["kind"] != "mount":
			continue
		for p: Vector2 in pc["pts"]:
			if not Geometry2D.is_point_in_polygon(p, sil) and _edge_distance(p, sil) > KEEP_SLACK:
				bad += 1
				print("FAIL mount %s socket %s has a corner %s outside the outline" % [label, pc["id"], p])
				break
	return [bad, inside, spots.size()]


## Check 6: every engine nozzle inside the outline.
static func _nozzles(label: String, rec: Dictionary) -> int:
	var bad := 0
	var sil: PackedVector2Array = rec["sil"]
	for nz: Vector3 in rec["nozzles"]:
		if not Geometry2D.is_point_in_polygon(Vector2(nz.x, nz.y), sil):
			bad += 1
			print("FAIL nozzle %s at (%.2f, %.2f) is outside the outline" % [label, nz.x, nz.y])
	return bad


## The gun spots of structure `id` as {"w": weapon id, "off": the offset in world units}.
static func _spots(id: String) -> Array:
	var out: Array = []
	match id:
		"mothership":
			var ms := Structures.MOTHERSHIP
			for key: String in ["pd_mounts", "cannon_mounts", "extra_pd_mounts", "flak_mounts", "heavy_mounts", "ion_mounts"]:
				var wid := {"pd_mounts": "ms_pd", "cannon_mounts": "ms_cannon", "extra_pd_mounts": "ms_pd", "flak_mounts": "ms_flak", "heavy_mounts": "ms_heavy", "ion_mounts": "ms_ion"}[key] as String
				for off: Vector2 in ms[key]:
					out.append({"w": wid, "off": off})
		"pd_tower":
			out.append({"w": "turret_pd_gun", "off": Vector2.ZERO})
		"torp_tower":
			out.append({"w": "turret_torp", "off": Vector2.ZERO})
		"repair_bay":
			out.append({"w": str(Structures.REPAIR_BAY["defense_weapon"]), "off": Vector2.ZERO})
	return out


## The hit radius of tower or bay `id`, from the game's own data.
static func _hit_radius(id: String) -> float:
	match id:
		"pd_tower":
			return float(TurretData.TURRETS["pd"]["radius"])
		"torp_tower":
			return float(TurretData.TURRETS["torp"]["radius"])
	return float(Structures.REPAIR_BAY["radius"])


## Does structure record `rec` have a socket piece within SOCKET_SLACK of design point `at`?
static func _has_socket(rec: Dictionary, at: Vector2) -> bool:
	for s: Dictionary in rec["sockets"]:
		if (s["at"] as Vector2).distance_to(at) <= SOCKET_SLACK:
			return true
	return false


## The drawn length and width (design units) of record `rec`'s outline.
static func _extent(rec: Dictionary) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in rec["sil"]:
		lo = lo.min(p)
		hi = hi.max(p)
	return hi - lo


## How far the outline of `rec` reaches from the middle, in design units.
static func _reach(rec: Dictionary) -> float:
	var far := 0.0
	for p: Vector2 in rec["sil"]:
		far = maxf(far, p.length())
	return far


## How far point `p` is from the nearest edge of polygon `poly`.
static func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best
