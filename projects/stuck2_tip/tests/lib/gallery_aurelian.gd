class_name GalleryAurelian
extends RefCounted
## WHAT THIS IS: the shape checks of the Aurelian steel hulls and the turret
## silhouettes, a part of the hull gallery (tests/hull_gallery.gd). They test the
## tables of AurelianShapes and TurretShapes without drawing anything, so a bad
## table is caught by a pass/fail run (hull_gallery --check) and not by someone
## looking at a picture.
##
## HOW IT WORKS: run() makes these checks, prints one summary line for each (and a
## "FAIL ..." line for every thing that fails) and one "aurelian hull ..." line for
## each hull (its drawn size, pieces, outline points, nozzles and mounts):
##   - every piece and every decal of every hull can be filled (Godot cuts a
##     polygon into triangles to fill it, and cannot for one that crosses itself);
##   - the outline AurelianPaint merges from the pieces is one polygon that can be
##     filled, has at most MAX_OUTLINE_POINTS points and reaches as far as the
##     pieces do (no piece was lost in the merge);
##   - the hull keeps the length and width of its plain outline in
##     ShipVisual.HULLS to within LENGTH_SLACK and WIDTH_SLACK, so a typing mistake
##     shows (a hull may be wider on purpose where a gun mount sits outside the plain
##     outline);
##   - every gun mount of the hull in ships.gd sits inside the outline, and every
##     turret or automatic mount has a mount piece (a socket) at its place;
##   - every engine nozzle lies inside the outline;
##   - the Bomber has its rear turret piece (the room for the tail gun);
##   - every turret silhouette of both team styles can be filled, and every
##     turning gun of every hull has a weapon class in TurretShapes.
## The option hulls of the options sheet (OptionHulls, tests/lib/option_hulls.gd)
## go through the same hull checks, each against the hull of ships.gd it is an
## option for, so a direction the user picks later is already sound.
##
## WHO USES IT: tests/hull_gallery.gd calls run() at the start of every run (with
## --check that is the whole run).

## The most points a merged hull outline may have (every point costs time when a
## tiny hull's outline is filled each frame).
const MAX_OUTLINE_POINTS := 90
## How much longer or shorter than its plain outline a hull may be drawn, as a fraction.
const LENGTH_SLACK := 0.15
## How much wider or narrower than its plain outline a hull may be drawn, as a fraction.
const WIDTH_SLACK := 0.3
## How far (design units) a mount's socket may be from the mount.
const SOCKET_SLACK := 0.3


## Run every check, print the results and return the number of failures.
static func run() -> int:
	var bad := 0
	bad += _polygons()
	bad += _hulls()
	bad += _turrets()
	return bad


## Check 1: every piece, decal and turret polygon can be cut into triangles.
static func _polygons() -> int:
	var total := 0
	var bad := 0
	var tables := _tables()
	for hid: String in tables:
		for pc: Dictionary in tables[hid]["pieces"]:
			total += 1
			if Geometry2D.triangulate_polygon(PackedVector2Array(pc["pts"])).is_empty():
				bad += 1
				print("FAIL polygon aurelian %s piece %s" % [hid, pc["id"]])
			for mk: Dictionary in pc.get("marks", []):
				if mk["kind"] == "line":
					continue
				total += 1
				if Geometry2D.triangulate_polygon(PackedVector2Array(mk["pts"])).is_empty():
					bad += 1
					print("FAIL polygon aurelian %s piece %s decal %s" % [hid, pc["id"], mk["kind"]])
	for style: String in ["aurelian", "vhorr"]:
		var table: Dictionary = TurretShapes.AURELIAN if style == "aurelian" else TurretShapes.VHORR
		for cls: String in TurretShapes.CLASSES:
			for group: String in ["base", "cap", "barrels", "accent"]:
				for poly: Array in table[cls][group]:
					total += 1
					if Geometry2D.triangulate_polygon(PackedVector2Array(poly)).is_empty():
						bad += 1
						print("FAIL polygon turret %s %s %s" % [style, cls, group])
	print("aurelian polygons: %d checked, %d cannot be filled" % [total, bad])
	return bad


## Check 2 to 5: the merged outlines, their size, the mounts and sockets, the nozzles.
static func _hulls() -> int:
	var bad := 0
	var outline_bad := 0
	var size_bad := 0
	var mount_bad := 0
	var nozzle_bad := 0
	var tables := _tables()
	for hid: String in tables:
		# An option hull is checked against the hull of ships.gd it is an option for.
		var base := str(tables[hid].get("for", hid))
		var rec := GalleryOptions.record(hid)
		var sil: PackedVector2Array = rec["sil"]
		var def: Dictionary = Ships.HULLS[base]
		var u := float(def["length"]) / 36.0
		# Check 2: one polygon that can be filled, not too many points, reaching as far as every piece.
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
			outline_bad += 1
			print("FAIL outline %s: %d points, pieces reach %s to %s, outline %s to %s" % [hid, sil.size(), lo, hi, slo, shi])
		# A hole in the hull: a point inside the outline that no piece covers (the outline
		# is the outer edge of the merge, so a hole would show the background through the hull).
		var gaps := _gaps(rec)
		if gaps.size() > 2:
			outline_bad += 1
			print("FAIL outline %s: %d sample points inside the outline are covered by no piece (a hole), for example %s" % [hid, gaps.size(), gaps.slice(0, 3)])
		# Check 3: the drawn size against the plain outline.
		var plain := GalleryChecks.box(ShipVisual.HULLS[base])
		var mine := Vector2(float(rec["len"]), float(rec["hw"]) * 2.0)
		if absf(mine.x / plain.x - 1.0) > LENGTH_SLACK or absf(mine.y / plain.y - 1.0) > WIDTH_SLACK:
			size_bad += 1
			print("FAIL size %s: length %.2f vs %.2f, width %.2f vs %.2f" % [hid, mine.x, plain.x, mine.y, plain.y])
		# Check 4: every mount inside the outline, every turning mount with a socket.
		var inside := 0
		var mounts: Array = def["mounts"]
		for m: Dictionary in mounts:
			var at: Vector2 = (m["off"] as Vector2) / u
			var in_outline := Geometry2D.is_point_in_polygon(at, sil)
			inside += 1 if in_outline else 0
			if not in_outline:
				mount_bad += 1
				print("FAIL mount %s %s at %s is outside the outline" % [hid, m["w"], at])
			if m["type"] != "fixed" and not _has_socket(rec, at):
				mount_bad += 1
				print("FAIL mount %s %s at %s has no socket piece" % [hid, m["w"], at])
			if m["type"] != "fixed" and not TurretShapes.CLASS_BY_WEAPON.has(m["w"]):
				mount_bad += 1
				print("FAIL mount %s %s has no turret class" % [hid, m["w"]])
		# Check 5: every nozzle inside the outline.
		var nozzles: Array = rec["nozzles"]
		for nz: Vector3 in nozzles:
			if not Geometry2D.is_point_in_polygon(Vector2(nz.x, nz.y), sil):
				nozzle_bad += 1
				print("FAIL nozzle %s at (%.2f, %.2f) is outside the outline" % [hid, nz.x, nz.y])
		print("aurelian hull %-13s length %6.1f (plain %6.1f)  half-width %5.1f (plain %5.1f)  pieces %2d  outline points %2d  nozzles %d  mounts inside %d of %d" % [hid, mine.x * u, plain.x * u, mine.y * 0.5 * u, plain.y * 0.5 * u, (rec["pieces"] as Array).size(), sil.size(), nozzles.size(), inside, mounts.size()])
	# Check 6: the Bomber's rear turret piece.
	var rear := 0
	for pc: Dictionary in AurelianShapes.HULLS["bomber"]["pieces"]:
		if pc["kind"] == "rear_turret":
			rear += 1
	var rear_bad := 0 if rear == 1 else 1
	if rear_bad > 0:
		print("FAIL bomber has %d rear turret pieces (one wanted)" % rear)
	print("aurelian outlines: %d hulls, %d not one fillable polygon of the pieces" % [tables.size(), outline_bad])
	print("aurelian sizes: %d hulls, %d outside the slack of the plain outline" % [tables.size(), size_bad])
	print("aurelian mounts: %d problems with mounts and sockets" % mount_bad)
	print("aurelian nozzles: %d outside the outline, rear turret pieces %d" % [nozzle_bad, rear])
	bad += outline_bad + size_bad + mount_bad + nozzle_bad + rear_bad
	return bad


## Every Aurelian drawing that is checked, id -> table: the ten hulls the game
## draws, then the option hulls of the options sheet (OptionHulls).
static func _tables() -> Dictionary:
	var out := {}
	for hid: String in Ships.ORDER:
		out[hid] = AurelianShapes.HULLS[hid]
	for oid: String in OptionHulls.HULLS:
		out[oid] = OptionHulls.HULLS[oid]
	return out


## The points of a grid over hull record `rec` that lie inside its outline but
## outside every piece (the grid is 0.3 design units apart).
static func _gaps(rec: Dictionary) -> Array:
	var sil: PackedVector2Array = rec["sil"]
	var gaps: Array = []
	var x := -20.0
	while x <= 20.0:
		var y := -10.0
		while y <= 10.0:
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
	return gaps


## Does hull record `rec` have a mount piece whose socket is within SOCKET_SLACK
## of design point `at`?
static func _has_socket(rec: Dictionary, at: Vector2) -> bool:
	for s: Dictionary in rec["sockets"]:
		if (s["at"] as Vector2).distance_to(at) <= SOCKET_SLACK:
			return true
	return false


## Check 7: every weapon class has both team styles, and its tip colour.
static func _turrets() -> int:
	var bad := 0
	for cls: String in TurretShapes.CLASSES:
		for table: Dictionary in [TurretShapes.AURELIAN, TurretShapes.VHORR]:
			if not table.has(cls):
				bad += 1
				print("FAIL turret class %s is missing from a team style" % cls)
		if not TurretShapes.ACCENT.has(cls):
			bad += 1
			print("FAIL turret class %s has no accent colour" % cls)
	# Every weapon kind has a class, so a gun that is not listed by id still gets a turret.
	for kind: int in [Rules.W_BOLT, Rules.W_LANCE, Rules.W_TORP, Rules.W_FLAK, Rules.W_PD, Rules.W_SHELL, Rules.W_ION]:
		if not TurretShapes.CLASS_BY_KIND.has(kind):
			bad += 1
			print("FAIL weapon kind %d has no turret class" % kind)
	print("turret shapes: %d classes, %d problems" % [TurretShapes.CLASSES.size(), bad])
	return bad
