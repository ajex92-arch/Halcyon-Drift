class_name AurelianPaint
extends RefCounted
## WHAT THIS IS: the painter of Aurelian's steel look. Aurelian is the amber
## team. Its pilot ships are drawn as clean, angular steel hulls (plates, glass
## canopies, engine nozzles, round turret sockets) inside an amber outline. It
## only draws; it changes nothing in the game.
##
## HOW IT WORKS:
##   - The drawings live in AurelianShapes as lists of named pieces. The first
##     time a hull is wanted, prepare() does all the slow work once and keeps the
##     result: it places every piece (the port copy of a mirrored piece too),
##     merges the pieces into the hull's outline (Geometry2D.merge_polygons, so
##     the outline is never kept by hand), cuts every piece and decal into
##     triangles, and keeps the whole picture of the hull as three packed arrays
##     (points, triangle indices, colours).
##   - A frame then draws a whole hull with one command: the points are turned to
##     the ship's place and size with one multiplication (a Transform2D times a
##     packed array, which Godot does in its own fast code) and handed to the
##     renderer already cut into triangles. The amber outline is one more
##     command, and the engine lights are one more.
##   - A ship drawn shorter than TINY_PX screen pixels is only a simple outline
##     (a few points), filled and lined: 2 commands.
##   - The size of every hull is the size of its plain outline in ShipVisual.HULLS
##     to within about a tenth, so hits and ranges read the same; only the
##     picture changes. A hull is drawn longer or wider where a gun mount sits outside the
##     plain outline (see AurelianShapes).
##   - A hit shows on the outline, not on the fill: for a moment after a hit the
##     line round the hull turns toward white and gets thicker (Palette.hit_edge,
##     Palette.hit_width). The fill keeps its colours.
##   - The same painter draws the structures: the Aurelian mothership and the
##     lane towers and Repair Bay of both teams (tables in StructureShapes,
##     through structure()). A structure has two dresses: the Aurelian steel one,
##     and the Vhorr dress of Cinder's towers and bay, the same pieces in the
##     Cinder colours (Palette.VHORR_*) with the extra thorn pieces of the table.
##     A structure is drawn as long as it is wide (its size on the screen is its
##     biggest span, not only its length), and it can be drawn faded while a
##     tower is still being built.
##   - Test only: with DrawParts.outline off, the amber line is left out (and the
##     hit flash with it). The hull gallery test switches the whole look off
##     (set_on) to draw the plain outlines instead, to measure what it costs.
##
## WHO USES IT: ShipVisual (pilot ships and their engine flames) asks on() "is
## this one drawn with the steel look?" and then draws through draw_shape();
## UnitVisual draws the towers, the Repair Bay and the Aurelian mothership
## through structure() and draw_shape(); the hull gallery test flips set_on() and
## reads the prepared hulls (outline(), nozzles(), mount_sockets()) for its
## checks and pictures.

## A hull drawn shorter than this many screen pixels is "tiny".
const TINY_PX := 24.0
## A hull this many screen pixels long or longer is "big" (the tint of the
## smaller ones fades out by then).
const BIG_PX := 44.0
## How much of the amber the fill of the smallest hulls takes on, 0 to 1. It
## fades to 0 at BIG_PX, so a far-away Aurelian ship still reads as amber.
const TINY_TINT := 0.45
## The width of a thin panel seam (a "line" decal), in design units.
const SEAM_WIDTH := 0.1
## Points closer than this (design units) to the line between their neighbours
## are dropped from a merged outline.
const CLEAN_TOLERANCE := 0.03
## How far (design units) the simple outline of a tiny hull may stray from the
## full outline.
const LOW_TOLERANCE := 0.6
## The Aurelian steel look: the dress of the pilot ships and of the Aurelian structures.
const DRESS_AUREL := 0
## The Vhorr dress: the same pieces in the Cinder colours (only Cinder's lane towers and Repair Bay wear it).
const DRESS_VHORR := 1
## How much of the Cinder red the fill of the smallest Vhorr structures takes on
## (the same as the Cinder shapes').
const VHORR_TINY_TINT := 0.6

## The prepared hulls: hull id -> prepared hull (see prepare()).
static var _hulls := {}
## The prepared structures: "<id>|aurelian" or "<id>|vhorr" -> prepared structure.
static var _structs := {}
## A unit hexagon (corners one unit from the middle): the shape of an engine
## nozzle, scaled and moved into place by prepare().
static var _hex := PackedVector2Array()
## 1 = Aurelian is drawn with the steel look (always, in play), 0 = drawn with
## the plain outlines of ShipVisual.HULLS (only while the gallery test compares).
static var _mode := 1


## Is `team` drawn with the steel look? True only for Aurelian, and only while
## the look is on (it always is, except inside the gallery test).
static func on(team: int) -> bool:
	return team == Rules.HALCYON and _mode == 1


## Switch the steel look on or off while the game runs. Tests use it to draw
## both looks in one run.
static func set_on(is_on: bool) -> void:
	_mode = 1 if is_on else 0


# --- prepared hulls ----------------------------------------------------------------------------

## The prepared hull `id` ("fighter" for an unknown id): a dictionary with
##   "sil"     the merged outline (PackedVector2Array)
##   "line"    the outline closed (first point repeated), for draw_polyline
##   "lo"      a simple copy of the outline for tiny hulls, and "lo_line" closed
##   "pts", "idx", "cols"   the whole picture as triangles (see draw_shape())
##   "glow_pts", "glow_idx" the engine lights as triangles
##   "nozzles" every engine nozzle as Vector3(x, y, radius), in design space
##   "sockets" every mount piece as {"id", "weapon", "at", "r"}
##   "pieces"  the placed pieces as {"id", "kind", "pts"} (design space)
##   "jet"     the flame points of the hull (from AurelianShapes)
##   "len"     the length of the outline (for a structure: its biggest span, the
##             length or the width), "hw" its widest half-width
##   "tiny_base", "tiny_to", "tiny_max"  the fill of a tiny drawing: "tiny_base"
##             tinted toward "tiny_to" by up to "tiny_max"
static func hull(id: String) -> Dictionary:
	var rec = _hulls.get(id)
	if rec == null:
		rec = prepare(AurelianShapes.HULLS.get(id, AurelianShapes.HULLS["fighter"]))
		_hulls[id] = rec
	return rec


## The prepared structure `id` ("mothership", "pd_tower", "torp_tower" or
## "repair_bay" of StructureShapes) in the Vhorr dress when `vhorr`, else in the
## Aurelian steel look. The same record as hull() makes.
static func structure(id: String, vhorr: bool) -> Dictionary:
	var key := id + ("|vhorr" if vhorr else "|aurelian")
	var rec = _structs.get(key)
	if rec == null:
		rec = prepare(StructureShapes.SHAPES[id], DRESS_VHORR if vhorr else DRESS_AUREL)
		_structs[key] = rec
	return rec


## The outline of hull `id` as a plain list of points (design space).
static func outline(id: String) -> Array:
	return Array(hull(id)["sil"])


## Where the engine flames of hull `id` come out, in its 36-unit design space:
## [the main flame's point, the side flames' point]. The side point's y is the
## distance from the middle; the other side is its mirror.
static func jets(id: String) -> Array:
	return hull(id)["jet"]


## Every engine nozzle of hull `id` as Vector3(x, y, radius) in its design
## space. The flames can start from each one.
static func nozzles(id: String) -> Array:
	return hull(id)["nozzles"]


## Every mount piece (the round socket under a gun) of hull `id`, as
## {"id", "weapon", "at": Vector2, "r": float} in its design space.
static func mount_sockets(id: String) -> Array:
	return hull(id)["sockets"]


## Do all the slow work for one hull table of AurelianShapes or one structure
## table of StructureShapes (see hull()), in `dress` (DRESS_AUREL, or DRESS_VHORR:
## the Cinder colours, with the table's extra "vhorr" pieces drawn first).
static func prepare(raw: Dictionary, dress: int = DRESS_AUREL) -> Dictionary:
	# Step 1: place every piece (mirrored ones twice) and collect its nozzles.
	var placed: Array = []
	var nozzles: Array = []
	var sockets: Array = []
	var pieces: Array = raw["pieces"]
	if dress == DRESS_VHORR:
		# The thorns go first, so the plates are drawn over their roots.
		pieces = (raw.get("vhorr", []) as Array) + pieces
	for pc: Dictionary in pieces:
		for copy in (2 if bool(pc["mirror"]) else 1):
			# copy 0 is the piece as written (starboard); copy 1 is its port mirror.
			var port := copy == 1
			var at: Vector2 = pc["attach"]
			var rec := {"id": str(pc["id"]) + ("_port" if port else ""), "kind": str(pc["kind"]), "shade": int(pc["shade"]), "pts": _place(pc["pts"], at, port), "marks": []}
			for mk: Dictionary in pc.get("marks", []):
				rec["marks"].append({"kind": str(mk["kind"]), "pts": _place(mk["pts"], at, port)})
			for nz: Vector3 in pc.get("nozzles", []):
				var spot := _place_point(Vector2(nz.x, nz.y), at, port)
				nozzles.append(Vector3(spot.x, spot.y, nz.z))
			if pc["kind"] == "mount" or pc["kind"] == "rear_turret":
				# A mount piece's socket: its attach point and how far its polygon reaches from it.
				var centre := _place_point(Vector2.ZERO, at, port)
				var reach := 0.0
				for p: Vector2 in rec["pts"]:
					reach = maxf(reach, p.distance_to(centre))
				sockets.append({"id": rec["id"], "weapon": str(pc.get("weapon", "")), "at": centre, "r": reach})
			placed.append(rec)
	# Step 2: the outline is the merge of every piece; its length and width.
	var polys: Array = []
	for rec: Dictionary in placed:
		polys.append(rec["pts"])
	var sil := _merge(polys)
	var x_min := INF
	var x_max := -INF
	var hw := 0.0
	for p: Vector2 in sil:
		x_min = minf(x_min, p.x)
		x_max = maxf(x_max, p.x)
		hw = maxf(hw, absf(p.y))
	var line := sil.duplicate()
	line.append(sil[0])
	var lo := _low(sil)
	var lo_line := lo.duplicate()
	lo_line.append(lo[0])
	# Step 3: the whole picture as triangles: the pieces, then their decals.
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	var cols := PackedColorArray()
	for rec: Dictionary in placed:
		_add_poly(rec["pts"], _shade(dress, int(rec["shade"])), pts, idx, cols)
	for rec: Dictionary in placed:
		for mk: Dictionary in rec["marks"]:
			_add_mark(str(mk["kind"]), mk["pts"], pts, idx, cols, dress)
	# Step 4: the engine lights: a dark housing in the picture, a hexagon of light apart.
	if _hex.is_empty():
		for k in 6:
			_hex.append(Vector2.from_angle(TAU * float(k) / 6.0))
	var glow_pts := PackedVector2Array()
	var glow_idx := PackedInt32Array()
	for nz: Vector3 in nozzles:
		_add_hex(Vector2(nz.x, nz.y), nz.z * 1.18, _shade(dress, 0), pts, idx, cols)
		var base := glow_pts.size()
		for k in 6:
			glow_pts.append(Vector2(nz.x, nz.y) + _hex[k] * nz.z * 0.8)
		for k in 4:
			glow_idx.append_array(PackedInt32Array([base, base + k + 1, base + k + 2]))
	# A structure counts as big as its biggest span (a tower is wider than long, a Repair Bay is a plus).
	var span := x_max - x_min
	if raw.has("size"):
		span = maxf(span, hw * 2.0)
	var vhorr := dress == DRESS_VHORR
	return {"sil": sil, "line": line, "lo": lo, "lo_line": lo_line, "pts": pts, "idx": idx, "cols": cols, "glow_pts": glow_pts, "glow_idx": glow_idx,
		"nozzles": nozzles, "sockets": sockets, "pieces": placed, "jet": raw.get("jet", []), "len": span, "hw": hw,
		"tiny_base": Palette.CINDER_HULL if vhorr else Palette.AUREL_HULL, "tiny_to": Palette.CINDER if vhorr else Palette.AMBER,
		"tiny_max": VHORR_TINY_TINT if vhorr else TINY_TINT}


## The colour of plating shade `shade` (0 darkest, 1 hull, 2 lightest) in `dress`.
static func _shade(dress: int, shade: int) -> Color:
	return Palette.VHORR_SHADES[shade] if dress == DRESS_VHORR else Palette.AUREL_SHADES[shade]


## The points `local` (measured from `at`) of a piece, placed on the hull. On
## the port side (`flip`) they are mirrored (y flipped) and run the other way
## round, so the polygon keeps its winding.
static func _place(local: Array, at: Vector2, flip: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in local:
		out.append(_place_point(p, at, flip))
	if flip:
		out.reverse()
	return out


## One point of a piece: `p` from the attach point `at`, mirrored when `flip`.
static func _place_point(p: Vector2, at: Vector2, flip: bool) -> Vector2:
	var q := at + p
	return Vector2(q.x, -q.y) if flip else q


# --- the outline ----------------------------------------------------------------------------------

## The outline of the union of `polys` (a list of polygons that overlap each
## other): the biggest polygon of each merge, with the needless points removed.
static func _merge(polys: Array) -> PackedVector2Array:
	var outer: PackedVector2Array = polys[0]
	var apart: Array = []
	for i in range(1, polys.size()):
		var joined := _union(outer, polys[i])
		if joined.is_empty():
			apart.append(polys[i])
		else:
			outer = joined
	# A piece that touched nothing yet may touch the outline now (a mirrored leg
	# only meets the first one through the hub that comes after them).
	var progress := true
	while progress and not apart.is_empty():
		progress = false
		for j in apart.size():
			var joined := _union(outer, apart[j])
			if not joined.is_empty():
				outer = joined
				apart.remove_at(j)
				progress = true
				break
	return _clean(outer)


## Polygons `a` and `b` merged into one: the biggest polygon of the union (a hole
## the merge leaves is not part of it). An empty polygon when the two are apart
## (the union is two separate polygons).
static func _union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var results: Array = Geometry2D.merge_polygons(a, b)
	var best := PackedVector2Array()
	var best_area := 0.0
	for r: PackedVector2Array in results:
		if absf(_area(r)) > absf(best_area):
			best_area = _area(r)
			best = r
	if best.size() < 3:
		return PackedVector2Array()
	# Holes run the other way round than the outline; two polygons that run the
	# same way as the biggest are two separate pieces of outline.
	for r: PackedVector2Array in results:
		if r != best and (_area(r) > 0.0) == (best_area > 0.0):
			return PackedVector2Array()
	return best


## The area of a polygon (negative when it runs clockwise).
static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## `poly` without points that lie (almost) on the line between their
## neighbours, or on top of the point before.
static func _clean(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	var changed := true
	while changed and out.size() > 3:
		changed = false
		for i in out.size():
			var a := out[(i + out.size() - 1) % out.size()]
			var b := out[i]
			var c := out[(i + 1) % out.size()]
			var span := a.distance_to(c)
			var off := b.distance_to(a) if span < 0.0001 else absf((c.x - a.x) * (a.y - b.y) - (a.x - b.x) * (c.y - a.y)) / span
			if off < CLEAN_TOLERANCE:
				out.remove_at(i)
				changed = true
				break
	return out


## A simple copy of outline `sil` for tiny hulls: its points thinned out so it
## strays at most LOW_TOLERANCE, with a finer tolerance when the thinned
## copy cannot be filled (it crossed itself).
static func _low(sil: PackedVector2Array) -> PackedVector2Array:
	for tol in [LOW_TOLERANCE, LOW_TOLERANCE * 0.65, LOW_TOLERANCE * 0.4, LOW_TOLERANCE * 0.2]:
		var lo := _simplify(sil, float(tol))
		if lo.size() >= 3 and not Geometry2D.triangulate_polygon(lo).is_empty():
			return lo
	return sil


## Douglas-Peucker: the closed polygon `poly` with points thinned out that
## stray less than `tol` from the line between the points kept.
static func _simplify(poly: PackedVector2Array, tol: float) -> PackedVector2Array:
	if poly.size() < 6:
		return poly
	var far := 0
	var far_d := -1.0
	for i in poly.size():
		var d := poly[0].distance_to(poly[i])
		if d > far_d:
			far_d = d
			far = i
	var first := poly.slice(0, far + 1)
	var second := poly.slice(far)
	second.append(poly[0])
	var a := _chain(first, tol)
	var b := _chain(second, tol)
	a.resize(a.size() - 1)
	b.resize(b.size() - 1)
	a.append_array(b)
	return a


## Douglas-Peucker for an open chain of points: the ends and, recursively, the
## farthest point from the line between them when it is more than `tol` away.
static func _chain(chain: PackedVector2Array, tol: float) -> PackedVector2Array:
	if chain.size() < 3:
		return chain
	var a := chain[0]
	var b := chain[chain.size() - 1]
	var span := a.distance_to(b)
	var best := -1.0
	var best_i := 0
	for i in range(1, chain.size() - 1):
		var d := chain[i].distance_to(a) if span < 0.0001 else absf((b.x - a.x) * (a.y - chain[i].y) - (a.x - chain[i].x) * (b.y - a.y)) / span
		if d > best:
			best = d
			best_i = i
	if best <= tol:
		return PackedVector2Array([a, b])
	var left := _chain(chain.slice(0, best_i + 1), tol)
	var right := _chain(chain.slice(best_i), tol)
	left.resize(left.size() - 1)
	left.append_array(right)
	return left


# --- the picture as triangles -------------------------------------------------------------------

## Cut polygon `poly` into triangles and add it, in colour `col`, to the
## picture arrays. A polygon that cannot be cut (it crosses itself) adds
## nothing; the hull gallery's checks report such a piece.
static func _add_poly(poly: PackedVector2Array, col: Color, pts: PackedVector2Array, idx: PackedInt32Array, cols: PackedColorArray) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var base := pts.size()
	pts.append_array(poly)
	for _i in poly.size():
		cols.append(col)
	for t in tri:
		idx.append(base + t)


## Add a regular hexagon (centre `at`, corner distance `r`) in colour `col`.
static func _add_hex(at: Vector2, r: float, col: Color, pts: PackedVector2Array, idx: PackedInt32Array, cols: PackedColorArray) -> void:
	var base := pts.size()
	for k in 6:
		pts.append(at + _hex[k] * r)
		cols.append(col)
	for k in 4:
		idx.append_array(PackedInt32Array([base, base + k + 1, base + k + 2]))


## Add one decal to the picture arrays: glass (a dark window with a lighter
## streak; one violet glow in the Vhorr dress), stripe (amber; Cinder red in the
## Vhorr dress), plate, dark (a vent or door), green (repair plus, the same in
## both dresses), light (a running light), warhead (the red-orange tip of a fixed
## torpedo, the same in both dresses) or line (a thin panel seam, made of one thin
## rectangle for each segment).
static func _add_mark(kind: String, poly: PackedVector2Array, pts: PackedVector2Array, idx: PackedInt32Array, cols: PackedColorArray, dress: int = DRESS_AUREL) -> void:
	var vhorr := dress == DRESS_VHORR
	match kind:
		"glass":
			if vhorr:
				_add_poly(poly, Palette.VHORR_GLASS, pts, idx, cols)
				return
			_add_poly(poly, Palette.AUREL_GLASS_DARK, pts, idx, cols)
			var mid := Vector2.ZERO
			for p: Vector2 in poly:
				mid += p
			mid /= float(poly.size())
			var inner := PackedVector2Array()
			for p: Vector2 in poly:
				inner.append(mid + (p - mid) * 0.55)
			_add_poly(inner, Palette.AUREL_GLASS, pts, idx, cols)
		"stripe":
			_add_poly(poly, Palette.with_alpha(Palette.CINDER if vhorr else Palette.AMBER, 0.85), pts, idx, cols)
		"plate":
			_add_poly(poly, _shade(dress, 2), pts, idx, cols)
		"dark":
			_add_poly(poly, Palette.VHORR_DARK if vhorr else Palette.AUREL_SHADE, pts, idx, cols)
		"green":
			_add_poly(poly, Palette.with_alpha(Palette.REPAIR, 0.9), pts, idx, cols)
		"light":
			_add_poly(poly, Palette.VHORR_LIGHT if vhorr else Palette.AUREL_LIGHT, pts, idx, cols)
		"warhead":
			_add_poly(poly, TurretShapes.ACCENT["torp"], pts, idx, cols)
		"line":
			var seam: Color = Palette.VHORR_SEAM if vhorr else Palette.AUREL_SEAM
			for i in range(poly.size() - 1):
				var d := (poly[i + 1] - poly[i]).normalized().orthogonal() * (SEAM_WIDTH * 0.5)
				_add_poly(PackedVector2Array([poly[i] + d, poly[i + 1] + d, poly[i + 1] - d, poly[i] - d]), Palette.with_alpha(seam, 0.9), pts, idx, cols)


# --- drawing ---------------------------------------------------------------------------------------

## Draw prepared hull `rec` on `ci` (the Visual node whose _draw() is running).
##   u       how big: design units to world units (uniform).
##   rot     the turn of the ship, in radians (the Visual node itself turns the
##           other way, so the hull is turned here, by hand).
##   px      world units per screen pixel: line widths and the size tests use it.
##   edge    the outline colour (amber, or the ace colour).
##   edge_w  the outline width in screen pixels.
##   flash   the hit flash strength: how far the outline turns toward white and
##           how much thicker it gets (Palette.HIT_FLASH; 0 = not hit just now).
##   heat    how hot the engines glow, 0..1.
##   alpha   1 = solid; less = see-through (a tower still being built). The caller
##           fades the outline colour `edge` itself.
static func draw_shape(ci: CanvasItem, rec: Dictionary, u: float, rot: float, px: float, edge: Color, edge_w: float, flash: float, heat: float, alpha: float = 1.0) -> void:
	# Step 1: one turn-and-size for every point, and how long the hull is on the screen.
	var xf := Transform2D(rot, Vector2(u, u), 0.0, Vector2.ZERO)
	var screen_len: float = float(rec["len"]) * u / px
	var line_col := edge
	var line_w := edge_w
	if flash > 0.0:
		line_col = Palette.hit_edge(edge, flash)
		line_w = Palette.hit_width(edge_w, flash)
	# Step 2: tiny hulls: the simple outline, tinted toward amber, filled and lined.
	if screen_len < TINY_PX:
		var tint: float = float(rec["tiny_max"]) * clampf((BIG_PX - screen_len) / (BIG_PX - 12.0), 0.0, 1.0)
		var tiny_fill: Color = (rec["tiny_base"] as Color).lerp(rec["tiny_to"], tint)
		tiny_fill.a = alpha
		ci.draw_colored_polygon(xf * (rec["lo"] as PackedVector2Array), tiny_fill)
		if DrawParts.outline:
			ci.draw_polyline(xf * (rec["lo_line"] as PackedVector2Array), line_col, line_w * px * 0.85, false)
		return
	# Step 3: the whole hull in one command (already cut into triangles).
	var cols: PackedColorArray = rec["cols"]
	if alpha < 1.0:
		cols = cols.duplicate()
		for i in cols.size():
			var c := cols[i]
			c.a *= alpha
			cols[i] = c
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), rec["idx"], xf * (rec["pts"] as PackedVector2Array), cols)
	# Step 4: the amber outline over it (the part that flashes after a hit).
	if DrawParts.outline:
		ci.draw_polyline(xf * (rec["line"] as PackedVector2Array), line_col, line_w * px, true)
	# Step 5: the engine nozzles' light, all in one command, brighter when the engines burn harder.
	var glow_idx: PackedInt32Array = rec["glow_idx"]
	if not glow_idx.is_empty():
		var glow_pts: PackedVector2Array = rec["glow_pts"]
		var glow_cols := PackedColorArray()
		glow_cols.resize(glow_pts.size())
		glow_cols.fill(Palette.with_alpha(Palette.AUREL_GLOW, (0.55 + 0.4 * heat) * alpha))
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), glow_idx, xf * glow_pts, glow_cols)
