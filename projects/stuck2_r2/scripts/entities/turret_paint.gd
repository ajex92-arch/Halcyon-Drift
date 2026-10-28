class_name TurretPaint
extends RefCounted
## WHAT THIS IS: the painter of the rotating turrets on pilot ships. Every gun
## that swings (a turret or an automatic mount, such as point defense, flak, the
## heavy cannon, the ion turret and the Bomber's tail gun) is drawn as a small
## turret at its place on the hull, turned the way the gun really points right
## now, with a silhouette that says which weapon it is. It only draws; it changes
## nothing in the game.
##
## HOW IT WORKS:
##   - TurretShapes holds one silhouette per weapon class (point defense, flak,
##     light turret, heavy cannon, ion turret, tail gun, torpedo turret) in two
##     team styles. The first time a turret of a class and team is wanted,
##     prepare() makes it ready: a rim in the team colour, then the barrels, the
##     base, the cap and the coloured tip, all cut into triangles once and kept as
##     three packed arrays (points, indices, colours).
##   - draw_mounts() goes through a ship's guns. A fixed gun (the nose guns, the
##     torpedo, the beams) gets no turret: it never turns. For every other gun it
##     finds the turret's class (from the weapon's id, else its kind), its size
##     (the hull's TurretShapes.HULL_TU times the hull's drawing scale, never
##     smaller than MIN_EXTENT_PX screen pixels so it stays readable on a small
##     ship), turns the prepared points to the gun's place and live angle with one
##     multiplication, and draws the whole turret with one command.
##   - A ship drawn shorter than HIDE_SHIP_PX screen pixels shows no turrets.
##   - A structure (the mothership, a lane tower, the Repair Bay) gets its heads
##     from draw_unit_mounts(): the same silhouettes at the structure's own size,
##     never made bigger than they are (a structure's body is what you see far
##     away) and left out where they would be under STRUCTURE_MIN_PX; the small
##     point-defense heads are drawn last, so they stay on top of a big gun
##     beside them.
##   - Test only: set_on(false) draws no turrets, so the hull gallery can measure
##     what they cost.
##
## WHO USES IT: ShipVisual calls draw_mounts() after it has drawn the hull;
## UnitVisual calls draw_unit_mounts() after it has drawn a structure. The
## hull gallery's turret sheet (tests/lib/gallery_turrets.gd) draws single turrets
## through draw_turret(), and set_on() is flipped by the frame-time measurements.

## A turret is drawn at least this many screen pixels from its middle to the tip
## of its barrel.
const MIN_EXTENT_PX := 6.0
## A ship drawn shorter than this many screen pixels shows no turrets.
const HIDE_SHIP_PX := 22.0
## A structure's head that would reach less than this many screen pixels from
## its middle is not drawn (and one that is drawn is never made bigger).
const STRUCTURE_MIN_PX := 2.5
## How thick the team-coloured rim of a turret is, in turret units.
const RIM := 0.12

## The prepared turrets: "style|class|team" -> prepared turret (see prepare()).
static var _recs := {}
## True = turrets are drawn (always, in play); false only while the gallery test
## measures.
static var _on := true


## Are the turrets drawn?
static func is_on() -> bool:
	return _on


## Switch the turrets on or off while the game runs (tests only).
static func set_on(is_on: bool) -> void:
	_on = is_on


## The weapon class of mount `m` ("pd", "flak", "light", "heavy", "ion", "tail"
## or "torp"): from its weapon id, else from its weapon kind.
static func class_of(m: WeaponMount) -> String:
	var cls: String = TurretShapes.CLASS_BY_WEAPON.get(m.weapon_id, "")
	if cls == "":
		cls = TurretShapes.CLASS_BY_KIND.get(m.kind, "light")
	return cls


## The prepared turret of weapon class `cls` for `team`, in the team's style
## (Vhorr's thorned turrets for Cinder, the clean ones for everyone else).
static func turret(cls: String, team: int) -> Dictionary:
	var style := "vhorr" if team == Rules.CINDER else "aurelian"
	var key := "%s|%s|%d" % [style, cls, team]
	var rec = _recs.get(key)
	if rec == null:
		rec = prepare(TurretShapes.VHORR[cls] if style == "vhorr" else TurretShapes.AURELIAN[cls], style, Palette.team(team), cls)
		_recs[key] = rec
	return rec


## Make one turret ready: the silhouette table `spec` of TurretShapes drawn in
## `style` with a rim of colour `rim` and the tip colour of class `cls`.
## Returns {"pts", "idx", "cols": the triangles, "extent": how far it reaches
## from its middle, in turret units}.
static func prepare(spec: Dictionary, style: String, rim: Color, cls: String) -> Dictionary:
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	var cols := PackedColorArray()
	var vhorr := style == "vhorr"
	var base_col := Palette.CINDER_SHADE if vhorr else Palette.TURRET_AUREL_BASE
	var cap_col := Palette.CINDER_PLATE if vhorr else Palette.TURRET_AUREL_CAP
	var barrel_col := Palette.TURRET_CINDER_BARREL if vhorr else Palette.TURRET_AUREL_BARREL
	# Step 1: the rim: every base and barrel grown by RIM, in the team colour.
	for group: String in ["base", "barrels"]:
		for poly: Array in spec[group]:
			for grown: PackedVector2Array in Geometry2D.offset_polygon(PackedVector2Array(poly), RIM, Geometry2D.JOIN_ROUND):
				_add(grown, Palette.with_alpha(rim, 0.9), pts, idx, cols)
	# Step 2: barrels, then the base over their roots, then the cap, then the tip.
	for poly: Array in spec["barrels"]:
		_add(PackedVector2Array(poly), barrel_col, pts, idx, cols)
	for poly: Array in spec["base"]:
		_add(PackedVector2Array(poly), base_col, pts, idx, cols)
	for poly: Array in spec["cap"]:
		_add(PackedVector2Array(poly), cap_col, pts, idx, cols)
	for poly: Array in spec["accent"]:
		_add(PackedVector2Array(poly), TurretShapes.ACCENT[cls], pts, idx, cols)
	return {"pts": pts, "idx": idx, "cols": cols, "extent": float(spec["extent"])}


## Cut polygon `poly` into triangles and add it, in colour `col`, to the arrays.
static func _add(poly: PackedVector2Array, col: Color, pts: PackedVector2Array, idx: PackedInt32Array, cols: PackedColorArray) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var base := pts.size()
	pts.append_array(poly)
	for _i in poly.size():
		cols.append(col)
	for t in tri:
		idx.append(base + t)


## Draw every turning gun of `ship` on `ci` (the ship's Visual node, whose
## _draw() is running). `k` is the drawing scale of the ship (1 = true size),
## `u` the world units per design unit of its hull (length * k / 36), `px` the
## world units per screen pixel and `rot` the ship's turn.
static func draw_mounts(ci: CanvasItem, ship: Ship, k: float, u: float, px: float, rot: float) -> void:
	if not _on or u * 36.0 / px < HIDE_SHIP_PX:
		return
	var tu: float = float(TurretShapes.HULL_TU.get(ship.hull_id, TurretShapes.DEFAULT_TU))
	for m: WeaponMount in ship.mounts:
		if m.mount_type == WeaponMount.FIXED:
			continue
		var rec := turret(class_of(m), ship.team)
		draw_turret(ci, rec, (m.offset * k).rotated(rot), m.world_angle(), tu * u, px)


## Draw every head of a structure's guns (`mounts`: its WeaponMounts) on `ci` (the
## structure's Visual node, whose _draw() is running), in the style of `team`.
## `size` is world units per turret unit, `px` the world units per screen pixel,
## `rot` the structure's turn and `alpha` how solid (a tower still being built is
## faded). A fixed gun gets no head. Heads too small to read on the screen are
## left out, and the point-defense ones are drawn last.
static func draw_unit_mounts(ci: CanvasItem, mounts: Array, team: int, size: float, px: float, rot: float, alpha: float = 1.0) -> void:
	if not _on:
		return
	for last: bool in [false, true]:
		for m: WeaponMount in mounts:
			if m.mount_type == WeaponMount.FIXED:
				continue
			var cls := class_of(m)
			if (cls == "pd") != last:
				continue
			var rec := turret(cls, team)
			if float(rec["extent"]) * size / px < STRUCTURE_MIN_PX:
				continue
			draw_turret(ci, rec, m.offset.rotated(rot), m.world_angle(), size, px, alpha, 0.0)


## Draw prepared turret `rec` at `pos` (in the Visual node's frame), turned to
## the world angle `ang`, `size` world units per turret unit big (raised so the
## turret reaches at least `min_px` screen pixels, MIN_EXTENT_PX unless told
## otherwise; 0 = never made bigger). `alpha` below 1 draws it see-through.
static func draw_turret(ci: CanvasItem, rec: Dictionary, pos: Vector2, ang: float, size: float, px: float, alpha: float = 1.0, min_px: float = MIN_EXTENT_PX) -> void:
	var extent: float = rec["extent"]
	var s := maxf(size, min_px * px / extent)
	var cols: PackedColorArray = rec["cols"]
	if alpha < 1.0:
		cols = cols.duplicate()
		for i in cols.size():
			var c := cols[i]
			c.a *= alpha
			cols[i] = c
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), rec["idx"], Transform2D(ang, Vector2(s, s), 0.0, pos) * (rec["pts"] as PackedVector2Array), cols)
