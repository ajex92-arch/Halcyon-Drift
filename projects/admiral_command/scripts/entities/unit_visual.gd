class_name UnitVisual
extends Node2D
## WHAT THIS IS: the "painter" for every unit that is not a pilot ship:
## minions, mining and repair drones, wards, turrets, repair bays, derelict
## camps, snub fighters and the mothership. It changes nothing in the game;
## it only draws. (Pilot ships have their own painter, ShipVisual.)
##
## HOW IT WORKS:
##   - It is the "Visual" child node in each of those units' scenes
##     (scenes/entities/*.tscn). Each frame, _process() asks Godot to redraw;
##     Godot then calls _draw(), which picks a drawing function by the
##     unit's kind (Unit.K_*).
##   - Like ShipVisual, it turns itself back against the unit's turning
##     ("counter-rotates"), so bars and text stay upright; shapes are turned
##     by hand.
##   - Lines are multiplied by `px` (world units per screen pixel) so they
##     keep the same thickness on screen at any zoom, and small units are
##     never drawn smaller than a few screen pixels.
##
## WHO USES IT: Godot runs it as part of the minion, mining_drone,
## repair_drone, ward, turret, repair_bay, derelict, snub_fighter and
## mothership scenes. It reads each unit's own fields (cargo, build timer,
## target, anchor...).

## Minion outlines by minion type, nose pointing right (+x), 1 unit long
## (scaled by the minion's size). Unknown types use "fighter".
const MINION_SHAPES := {
	"fighter": [Vector2(1, 0), Vector2(-0.6, 0.55), Vector2(-0.3, 0), Vector2(-0.6, -0.55)],
	"bomber": [Vector2(1, 0), Vector2(0.2, 0.45), Vector2(-0.8, 0.5), Vector2(-0.5, 0), Vector2(-0.8, -0.5), Vector2(0.2, -0.45)],
	"corvette": [Vector2(1, 0), Vector2(0.4, 0.55), Vector2(-0.8, 0.55), Vector2(-1, 0), Vector2(-0.8, -0.55), Vector2(0.4, -0.55)],
}
## The mining drone's outline (same scale as MINION_SHAPES).
const DRONE := [Vector2(1, 0), Vector2(0.3, 0.75), Vector2(-0.8, 0.6), Vector2(-0.8, -0.6), Vector2(0.3, -0.75)]
## The mothership's outline, in world units for a ship 510 long and 140 wide
## (stretched to the real mothership's length and beam).
const MOTHER := [Vector2(260, 0), Vector2(80, 70), Vector2(-220, 48), Vector2(-180, 0), Vector2(-220, -48), Vector2(80, -70)]
## The mothership's engine block at the tail (same scale as MOTHER).
const MOTHER_ENGINE := [Vector2(-200, 0), Vector2(-250, 16), Vector2(-250, -16)]

## The unit we draw (our parent node).
var unit: Unit


## Find our unit. The mothership is drawn one layer lower (z_index -1) so
## the small ships around it are drawn on top.
func _ready() -> void:
	unit = get_parent() as Unit
	if unit is Mothership:
		z_index = -1


## Every frame: counter-rotate and ask for a redraw.
func _process(_dt: float) -> void:
	if unit == null or not unit.alive:
		return
	rotation = -unit.rotation
	queue_redraw()


## World units per screen pixel at the current camera zoom (zoom limited
## to at least 0.02).
func _px() -> float:
	var cam := get_viewport().get_camera_2d()
	return 1.0 / maxf(0.02, cam.zoom.x if cam != null else 1.0)


## Draw `shape` (a list of corner points) scaled by `size` and turned with
## the unit: filled with `fill` and outlined in `edge`, `width` thick.
func _poly(shape: Array, size: float, fill: Color, edge: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in shape:
		pts.append((p * size).rotated(unit.rotation))
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, edge, width, true)


## A bar `w` wide at height `y`: a dark background and a `frac` (0..1)
## filled part in colour `col`.
func _bar(y: float, w: float, frac: float, col: Color, px: float) -> void:
	draw_rect(Rect2(-w / 2.0, y, w, 3.0 * px), Palette.with_alpha(Palette.VOID, 0.75))
	draw_rect(Rect2(-w / 2.0, y, w * clampf(frac, 0.0, 1.0), 3.0 * px), col)


## Draw the unit (Godot calls this after queue_redraw()): work out the
## shared colours, then hand over to the drawing function for its kind.
func _draw() -> void:
	if unit == null or not unit.alive:
		return
	var px := _px()
	var col := Palette.team(unit.team)
	# "lerp" mixes two colours: just after a hit the fill is 60% of the way
	# from HULL_FILL to ICE (a flash).
	var fill := Palette.HULL_FILL.lerp(Palette.ICE, 0.6) if unit.flash > 0.0 else Palette.HULL_FILL
	match unit.kind:
		Unit.K_MINION:
			_draw_minion(px, col, fill)
		Unit.K_MINING_DRONE:
			_draw_mining_drone(px, col, fill)
		Unit.K_REPAIR_DRONE:
			_draw_repair_drone(px)
		Unit.K_WARD:
			_draw_ward(px, col)
		Unit.K_TURRET:
			_draw_turret(px, col, fill)
		Unit.K_BAY:
			_draw_bay(px, col, fill)
		Unit.K_MONSTER:
			_draw_derelict(px, fill)
		Unit.K_SNUB:
			# A snub fighter: a fighter outline in the derelict colour.
			_poly(MINION_SHAPES["fighter"], maxf(unit.radius * 1.4, 6.0 * px), fill, Palette.DERELICT, 1.2 * px)
		Unit.K_MOTHERSHIP:
			_draw_mothership(px, col)


## A minion: its type's outline, plus a hull bar once it is damaged (only
## when zoomed in enough: px below 3).
func _draw_minion(px: float, col: Color, fill: Color) -> void:
	var m := unit as Minion
	var size := maxf(m.radius * 1.3, 6.0 * px)
	_poly(MINION_SHAPES.get(m.mtype, MINION_SHAPES["fighter"]), size, fill, Palette.with_alpha(col, 0.85), 1.0 * px)
	if px < 3.0 and unit.hull < unit.hull_max:
		_bar(-size - 6.0 * px, maxf(20.0 * px, size * 2.0), unit.hull_frac(), col, px)


## A mining drone: its outline, an ore dot that grows with its cargo, and
## while mining a thin beam to the rock it is mining.
func _draw_mining_drone(px: float, col: Color, fill: Color) -> void:
	var d := unit as MiningDrone
	var size := maxf(d.radius * 1.2, 6.0 * px)
	_poly(DRONE, size, fill, col, 1.2 * px)
	if d.cargo > 1.0:
		draw_circle(Vector2.ZERO, size * 0.35 * (d.cargo / d.capacity), Palette.ORE)
	if d.state == "mine" and d.rock >= 0:
		var n := d.world.node_by_id(d.node_id)
		if n != null:
			draw_line(Vector2.ZERO, (n.ore_pos[d.rock] - d.global_position).rotated(0.0), Palette.with_alpha(col, 0.5), 1.0 * px)


## A repair drone: a plus sign, and a line to the unit it is healing.
func _draw_repair_drone(px: float) -> void:
	var r := unit as RepairDrone
	var s := maxf(6.0, 4.0 * px)
	draw_line(Vector2(-s, 0), Vector2(s, 0), Palette.REPAIR, 2.0 * px)
	draw_line(Vector2(0, -s), Vector2(0, s), Palette.REPAIR, 2.0 * px)
	if r.healing and r.target != null and is_instance_valid(r.target):
		draw_line(Vector2.ZERO, r.target.global_position - r.global_position, Palette.with_alpha(Palette.REPAIR, 0.6), 1.5 * px)


## A ward: a diamond, and once anchored a faint ring showing how far it sees.
func _draw_ward(px: float, col: Color) -> void:
	var w := unit as Ward
	var s := maxf(10.0, 5.0 * px)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)]), Palette.with_alpha(col, 0.8))
	if w.is_anchored():
		draw_arc(Vector2.ZERO, w.vision_radius, 0.0, TAU, 64, Palette.with_alpha(col, 0.12), 1.5 * px, true)


## A turret: a square (a diamond for torpedo turrets), faded while still
## being built, its gun barrel, hull and shield bars, a line to what it is
## shooting, and a "BUILDING" countdown while unfinished.
func _draw_turret(px: float, col: Color, fill: Color) -> void:
	var t := unit as Turret
	var s := maxf(t.radius, 10.0 * px)
	# Body and barrel.
	var box := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	if t.ttype == "torp":
		box = [Vector2(1.2, 0), Vector2(0, 1.2), Vector2(-1.2, 0), Vector2(0, -1.2)]
	var built_a := 1.0 if t.is_built() else 0.45
	_poly(box, s, Palette.with_alpha(fill, built_a), Palette.with_alpha(col, built_a), 2.0 * px)
	var gun := Vector2.from_angle(t.mounts[0].world_angle()) * s * 1.4
	draw_line(Vector2.ZERO, gun, col, 3.0 * px)
	# Bars.
	_bar(s + 6.0 * px, s * 2.4, t.hull_frac(), col, px)
	if t.shields != null:
		_bar(s + 11.0 * px, s * 2.4, t.shields.fraction(), Palette.SHIELD, px)
	# Aggro tether: who this turret is shooting (brighter for pilot ships).
	if t.target != null and is_instance_valid(t.target) and t.target.alive and t.is_built():
		var tc := Palette.CINDER if t.target.kind == Unit.K_SHIP else Palette.with_alpha(col, 0.35)
		draw_line(Vector2.ZERO, t.target.global_position - t.global_position, Palette.with_alpha(tc, 0.5), 1.5 * px)
	if not t.is_built():
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-60.0 * px, -s - 8.0 * px), "BUILDING %ds" % int(ceil(t.build_left)), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * px, int(10.0 * px), col)


## A repair bay: a box with a plus sign and a hull bar. Once anchored, a
## ring shows its repair range (fainter when it can't repair right now);
## before that, a faint line points to its `anchor` point.
func _draw_bay(px: float, col: Color, fill: Color) -> void:
	var b := unit as RepairBay
	var s := maxf(b.radius, 9.0 * px)
	_poly([Vector2(-1, -0.7), Vector2(1, -0.7), Vector2(1, 0.7), Vector2(-1, 0.7)], s, fill, col, 1.6 * px)
	draw_line(Vector2(-s * 0.4, 0), Vector2(s * 0.4, 0), Palette.REPAIR, 2.0 * px)
	draw_line(Vector2(0, -s * 0.4), Vector2(0, s * 0.4), Palette.REPAIR, 2.0 * px)
	if b.is_anchored():
		draw_arc(Vector2.ZERO, float(Structures.REPAIR_BAY["range"]), 0.0, TAU, 64, Palette.with_alpha(Palette.REPAIR, 0.15 if b.can_repair() else 0.05), 2.0 * px, true)
	else:
		draw_line(Vector2.ZERO, b.anchor - b.global_position, Palette.with_alpha(col, 0.25), 1.0 * px)
	_bar(s + 6.0 * px, s * 2.4, b.hull_frac(), col, px)


## A derelict camp: a corvette outline in the derelict colour, a dot for
## each gun, and a hull bar once damaged.
func _draw_derelict(px: float, fill: Color) -> void:
	var d := unit as Derelict
	var s := d.radius
	_poly(MINION_SHAPES["corvette"], s, Palette.with_alpha(fill, 0.9), Palette.DERELICT, 2.0 * px)
	for m in d.mounts:
		draw_circle((m.offset).rotated(d.rotation), 6.0 * px, Palette.DERELICT)
	if d.hull < d.hull_max:
		_bar(s + 8.0 * px, s * 2.0, d.hull_frac(), Palette.DERELICT, px)


## The mothership: its long hull stretched to its real length and beam
## (width), the engine block, a dot for each gun, wide hull and shield bars,
## and a line to where it is moving (if it has a move order).
func _draw_mothership(px: float, col: Color) -> void:
	var ms := unit as Mothership
	# Stretch factors from the 510 x 140 outline to the real size.
	var sx := float(ms.def["length"]) / 510.0
	var sy := ms.beam / 140.0
	# The hull, filled (lighter for a moment after a hit) and outlined.
	var shape := PackedVector2Array()
	for p: Vector2 in MOTHER:
		shape.append(Vector2(p.x * sx, p.y * sy).rotated(ms.rotation))
	draw_colored_polygon(shape, Palette.MOTHER_FILL.lerp(Palette.ICE, 0.25) if ms.flash > 0.0 else Palette.MOTHER_FILL)
	var closed := shape.duplicate()
	closed.append(shape[0])
	draw_polyline(closed, col, 3.0 * px, true)
	# Engine block and gun dots.
	var eng := PackedVector2Array()
	for p: Vector2 in MOTHER_ENGINE:
		eng.append(Vector2(p.x * sx, p.y * sy).rotated(ms.rotation))
	draw_colored_polygon(eng, Palette.with_alpha(col, 0.85))
	for m in ms.mounts:
		draw_circle(m.offset.rotated(ms.rotation), 10.0, Palette.with_alpha(col, 0.7))
	# Bars (900 world units wide) and the move line.
	var w := 900.0
	_bar(ms.beam * 0.5 + 40.0, w, ms.hull_frac(), col, px * 2.0)
	_bar(ms.beam * 0.5 + 40.0 + 9.0 * px, w, ms.shields.fraction(), Palette.SHIELD, px * 2.0)
	if ms.move_target != Vector2.INF:
		draw_line(Vector2.ZERO, ms.move_target - ms.global_position, Palette.with_alpha(col, 0.3), 2.0 * px)
