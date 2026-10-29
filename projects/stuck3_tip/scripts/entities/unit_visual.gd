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
##   - The lane minions of both teams are drawn plain and solid, so they are
##     never taken for pilot ships: Aurelian's are flat-tailed plates from
##     MinionShapes (the team colour mixed into the hull colour, a bold
##     outline); Cinder's are smooth shells with no blades (CinderShapes.MINIONS,
##     with a solid body tint).
##   - Cinder (the red team) wears an alien look: its minions, drones, wards
##     and mothership are drawn by CinderPaint from the tables in CinderShapes
##     (dark, bladed shapes with glowing veins) in the same size as the plain
##     outlines below. Bars, rings, beams and the other extras are drawn as
##     before. Derelicts and snub fighters are neutral and keep their look.
##   - The lane towers (point defense and torpedo), the Repair Bay and the
##     Aurelian mothership are drawn by AurelianPaint from the tables in
##     StructureShapes, for both teams: the towers and the bay in the Aurelian
##     steel dress or the Vhorr dress (Cinder's colours and thorns), the mothership
##     in steel. TurretPaint draws the head of each of their guns on top (the
##     Cinder mothership keeps its citadel and its gun dots).
##   - With --sim-only (Game.sim_only) it draws nothing at all: it hides
##     itself and does no per-frame work.
##   - Test only: the switches of DrawParts (--bench-off=...) can leave out the
##     hull outline (_poly(), the mothership's line, CinderPaint), the bars
##     (_bar()) and the every-frame redraw, so a test can measure what they
##     cost. With no switch given everything is drawn as always.
##
## WHO USES IT: Godot runs it as part of the minion, mining_drone,
## repair_drone, ward, turret, repair_bay, derelict, snub_fighter and
## mothership scenes. It reads each unit's own fields (cargo, build timer,
## target, anchor...). CinderPaint draws the Cinder shapes. DrawParts holds
## the test-only switches it reads.

## Small-craft outlines by type, nose pointing right (+x), 1 unit long (scaled
## by the unit's size). The jungle's snub fighters ("fighter") and derelict
## camps ("corvette") use them; the lane minions have their own, MinionShapes.
## Unknown types use "fighter".
const MINION_SHAPES := {
	"fighter": [Vector2(1, 0), Vector2(-0.6, 0.55), Vector2(-0.3, 0), Vector2(-0.6, -0.55)],
	"bomber": [Vector2(1, 0), Vector2(0.2, 0.45), Vector2(-0.8, 0.5), Vector2(-0.5, 0), Vector2(-0.8, -0.5), Vector2(0.2, -0.45)],
	"corvette": [Vector2(1, 0), Vector2(0.4, 0.55), Vector2(-0.8, 0.55), Vector2(-1, 0), Vector2(-0.8, -0.55), Vector2(0.4, -0.55)],
}
## The mining drone's outline (same scale as MINION_SHAPES).
const DRONE := [Vector2(1, 0), Vector2(0.3, 0.75), Vector2(-0.8, 0.6), Vector2(-0.8, -0.6), Vector2(0.3, -0.75)]
## The plain outline of the mothership, in world units for a ship 510 long and
## 140 wide (stretched to the real length and beam). Nothing is drawn with it any
## more; the hull gallery's size check keeps the Cinder citadel the size of it.
const MOTHER := [Vector2(260, 0), Vector2(80, 70), Vector2(-220, 48), Vector2(-180, 0), Vector2(-220, -48), Vector2(80, -70)]
## The plain mothership's engine block at the tail (same scale as MOTHER).
const MOTHER_ENGINE := [Vector2(-200, 0), Vector2(-250, 16), Vector2(-250, -16)]

## The unit we draw (our parent node).
var unit: Unit
## True once _draw() has drawn this unit at least once. With the test switch
## DrawParts.redraw off we ask for a new picture only until this is true.
var _drawn := false


## Find our unit. The mothership is drawn one layer lower (z_index -1) so
## the small ships around it are drawn on top. With --sim-only (Game.sim_only)
## nothing is ever drawn, so we hide ourselves and stop our per-frame work
## for good: the simulation never reads this node.
func _ready() -> void:
	unit = get_parent() as Unit
	if Game.sim_only:
		visible = false
		set_process(false)
		return
	DrawParts.read_options()
	if unit is Mothership:
		z_index = -1


## Every frame: counter-rotate and ask for a redraw. (Test only: with
## DrawParts.redraw off we ask for a redraw just until the first picture is
## drawn; Godot keeps that picture.)
func _process(_dt: float) -> void:
	if unit == null or not unit.alive:
		return
	rotation = -unit.rotation
	if DrawParts.redraw or not _drawn:
		queue_redraw()


## World units per screen pixel at the current camera zoom (zoom limited
## to at least 0.02).
func _px() -> float:
	var cam := get_viewport().get_camera_2d()
	return 1.0 / maxf(0.02, cam.zoom.x if cam != null else 1.0)


## Draw `shape` (a list of corner points) scaled by `size` and turned with
## the unit: filled with `fill` and outlined in `edge`, `width` thick. A hit
## shows on the outline, not on the fill: for a moment after it the line turns
## toward white and gets thicker (Palette.hit_edge, Palette.hit_width). (Test
## only: the outline, and the hit flash with it, is left out when
## DrawParts.outline is off.)
func _poly(shape: Array, size: float, fill: Color, edge: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in shape:
		pts.append((p * size).rotated(unit.rotation))
	draw_colored_polygon(pts, fill)
	if DrawParts.outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		if unit.flash > 0.0:
			edge = Palette.hit_edge(edge, Palette.HIT_FLASH)
			width = Palette.hit_width(width, Palette.HIT_FLASH)
		draw_polyline(closed, edge, width, true)


## The hit flash strength of this unit: Palette.HIT_FLASH for the first moments
## after a hit, else 0. CinderPaint takes it as a number (how far its outline
## turns toward white and how much thicker it gets); the plain outlines do the
## same in _poly(). The fill never changes.
func _flash() -> float:
	return Palette.HIT_FLASH if unit.flash > 0.0 else 0.0


## A number that is different for every unit (its id times 1.7), so the veins
## of different Cinder units do not all pulse at the same moment.
func _phase() -> float:
	return float(unit.uid) * 1.7


## A bar `w` wide at height `y`: a dark background and a `frac` (0..1)
## filled part in colour `col`. (Test only: nothing is drawn when DrawParts.bars
## is off.)
func _bar(y: float, w: float, frac: float, col: Color, px: float) -> void:
	if not DrawParts.bars:
		return
	draw_rect(Rect2(-w / 2.0, y, w, 3.0 * px), Palette.with_alpha(Palette.VOID, 0.75))
	draw_rect(Rect2(-w / 2.0, y, w * clampf(frac, 0.0, 1.0), 3.0 * px), col)


## Draw the unit (Godot calls this after queue_redraw()): work out the
## shared colours, then hand over to the drawing function for its kind.
func _draw() -> void:
	if unit == null or not unit.alive:
		return
	_drawn = true
	var px := _px()
	var col := Palette.team(unit.team)
	# The dark fill inside the plain unit shapes. A hit does not change it: only
	# the outline flashes (see _poly() and _flash()).
	var fill := Palette.HULL_FILL
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
			_draw_turret(px, col)
		Unit.K_BAY:
			_draw_bay(px, col)
		Unit.K_MONSTER:
			_draw_derelict(px, fill)
		Unit.K_SNUB:
			# A snub fighter: a fighter outline in the derelict colour.
			_poly(MINION_SHAPES["fighter"], maxf(unit.radius * 1.4, 6.0 * px), fill, Palette.DERELICT, 1.2 * px)
		Unit.K_MOTHERSHIP:
			_draw_mothership(px, col)


## A minion: its type's outline, plus a hull bar once it is damaged (only when
## zoomed in enough: px below 3). Both teams' minions are plain and solid, so
## they are never taken for pilot ships: Aurelian's is a flat-tailed plate from
## MinionShapes, filled with the team colour mixed into the hull colour and
## outlined boldly (the outline flashes after a hit); Cinder's is a smooth
## shell from CinderShapes.MINIONS with a solid body tint.
func _draw_minion(px: float, col: Color, fill: Color) -> void:
	var m := unit as Minion
	var size := maxf(m.radius * 1.3, 6.0 * px)
	if CinderPaint.alien(m.team):
		CinderPaint.draw_shape(self, CinderPaint.minion(m.mtype), Vector2(size, size), m.rotation, px, Palette.with_alpha(col, 0.85), 1.0, _flash(), 0.5, _phase())
	else:
		_poly(MinionShapes.aurelian(m.mtype), size, fill.lerp(col, MinionShapes.FILL_MIX), Palette.with_alpha(col, 0.95), MinionShapes.EDGE_PX * px)
	if px < 3.0 and unit.hull < unit.hull_max:
		_bar(-size - 6.0 * px, maxf(20.0 * px, size * 2.0), unit.hull_frac(), col, px)


## A mining drone: its outline (a Cinder drone is a dark scarab with grabbing
## claws), an ore dot that grows with its cargo, and while mining a thin beam
## to the rock it is mining.
func _draw_mining_drone(px: float, col: Color, fill: Color) -> void:
	var d := unit as MiningDrone
	var size := maxf(d.radius * 1.2, 6.0 * px)
	if CinderPaint.alien(d.team):
		CinderPaint.draw_shape(self, CinderPaint.unit_shape("mining_drone"), Vector2(size, size), d.rotation, px, col, 1.2, _flash(), 0.5, _phase())
	else:
		_poly(DRONE, size, fill, col, 1.2 * px)
	if d.cargo > 1.0:
		draw_circle(Vector2.ZERO, size * 0.35 * (d.cargo / d.capacity), Palette.ORE)
	if d.state == "mine" and d.rock >= 0:
		var n := d.world.node_by_id(d.node_id)
		if n != null:
			draw_line(Vector2.ZERO, (n.ore_pos[d.rock] - d.global_position).rotated(0.0), Palette.with_alpha(col, 0.5), 1.0 * px)


## A repair drone: a green plus sign (on a Cinder drone: a small green plus
## on a dark spinning thorn star), and a line to the unit it is healing.
func _draw_repair_drone(px: float) -> void:
	var r := unit as RepairDrone
	var s := maxf(6.0, 4.0 * px)
	if CinderPaint.alien(r.team):
		CinderPaint.draw_shape(self, CinderPaint.unit_shape("repair_drone"), Vector2(s, s), r.rotation, px, Palette.CINDER, 1.0, _flash(), 0.5, _phase())
		draw_line(Vector2(-s * 0.5, 0), Vector2(s * 0.5, 0), Palette.REPAIR, 1.6 * px)
		draw_line(Vector2(0, -s * 0.5), Vector2(0, s * 0.5), Palette.REPAIR, 1.6 * px)
	else:
		draw_line(Vector2(-s, 0), Vector2(s, 0), Palette.REPAIR, 2.0 * px)
		draw_line(Vector2(0, -s), Vector2(0, s), Palette.REPAIR, 2.0 * px)
	if r.healing and r.target != null and is_instance_valid(r.target):
		draw_line(Vector2.ZERO, r.target.global_position - r.global_position, Palette.with_alpha(Palette.REPAIR, 0.6), 1.5 * px)


## A ward: a diamond (a Cinder ward is a dark thorn star with a glowing
## pupil), and once anchored a faint ring showing how far it sees.
func _draw_ward(px: float, col: Color) -> void:
	var w := unit as Ward
	var s := maxf(10.0, 5.0 * px)
	if CinderPaint.alien(w.team):
		CinderPaint.draw_shape(self, CinderPaint.unit_shape("ward"), Vector2(s, s), w.rotation, px, col, 1.2, _flash(), 0.8, _phase())
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)]), Palette.with_alpha(col, 0.8))
	if w.is_anchored():
		draw_arc(Vector2.ZERO, w.vision_radius, 0.0, TAU, 64, Palette.with_alpha(col, 0.12), 1.5 * px, true)


## A turret: a lane tower, faded while still being built, with its gun head on
## top (the head turns to the way it shoots), hull and shield bars, a line to
## what it is shooting, and a "BUILDING" countdown while unfinished. The point-defense
## tower is the "Anchor" (a hub with three legs, the stem leg toward its node) and
## the torpedo tower the "Rampart" (a wide bar across the lane with three fixed
## torpedo cells on each side); both teams use the same drawing, Cinder's in the
## Vhorr dress (StructureShapes, AurelianPaint).
func _draw_turret(px: float, col: Color) -> void:
	var t := unit as Turret
	var s := maxf(t.radius, 10.0 * px)
	# Body and head.
	var built_a := 1.0 if t.is_built() else 0.45
	var id := "torp_tower" if t.ttype == "torp" else "pd_tower"
	var u := s * 2.0 / 36.0
	AurelianPaint.draw_shape(self, AurelianPaint.structure(id, t.team == Rules.CINDER), u, t.rotation, px, Palette.with_alpha(col, built_a), 2.0, _flash(), 0.5, built_a)
	TurretPaint.draw_unit_mounts(self, t.mounts, t.team, float(TurretShapes.HULL_TU[id]) * u, px, t.rotation, built_a)
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


## A repair bay: the "Clover", four berth pads with a green end each round a hub
## (the repair plus as a body; both teams, Cinder's in the Vhorr dress, StructureShapes
## and AurelianPaint), the head of its defense gun on the hub once Bay Defenses
## research gives it one, and a hull bar. Once anchored, a ring shows its repair
## range (fainter when it can't repair right now); before that, a faint line
## points to its `anchor` point.
func _draw_bay(px: float, col: Color) -> void:
	var b := unit as RepairBay
	var s := maxf(b.radius, 9.0 * px)
	var u := s * 2.0 / 36.0
	AurelianPaint.draw_shape(self, AurelianPaint.structure("repair_bay", b.team == Rules.CINDER), u, b.rotation, px, col, 1.6, _flash(), 0.5)
	TurretPaint.draw_unit_mounts(self, b.mounts, b.team, float(TurretShapes.HULL_TU["repair_bay"]) * u, px, b.rotation)
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


## The mothership, with wide hull and shield bars and a line to where it is
## moving (if it has a move order). The Aurelian mothership is the "Slipway" (two
## parallel hulls with a dark slip between them, two cross-decks, a V prow, StructureShapes
## and AurelianPaint, drawn as long as its real length; its outline flashes for a
## moment after a hit, more gently than a ship's) with a socket under each of its 21
## gun spots and the head of every gun it has on top. The Cinder mothership is an
## alien citadel (CinderPaint, stretched to its real length and beam) with a dot for
## each gun; its engines are lights in the shape.
func _draw_mothership(px: float, col: Color) -> void:
	var ms := unit as Mothership
	var hit := Palette.HIT_FLASH_MOTHER if ms.flash > 0.0 else 0.0
	if CinderPaint.alien(ms.team):
		# The alien hull is drawn for a 1600 x 340 ship; stretch it to the real size.
		CinderPaint.draw_shape(self, CinderPaint.mothership(), Vector2(float(ms.def["length"]) / 1600.0, ms.beam / 340.0), ms.rotation, px, col, 3.0, hit, 0.7, 0.0)
		# Gun dots.
		for m in ms.mounts:
			draw_circle(m.offset.rotated(ms.rotation), 10.0, Palette.with_alpha(col, 0.7))
	else:
		var u := float(ms.def["length"]) / 36.0
		AurelianPaint.draw_shape(self, AurelianPaint.structure("mothership", false), u, ms.rotation, px, col, 3.0, hit, 0.6)
		TurretPaint.draw_unit_mounts(self, ms.mounts, ms.team, float(TurretShapes.HULL_TU["mothership"]) * u, px, ms.rotation)
	# Bars (900 world units wide) and the move line.
	var w := 900.0
	_bar(ms.beam * 0.5 + 40.0, w, ms.hull_frac(), col, px * 2.0)
	_bar(ms.beam * 0.5 + 40.0 + 9.0 * px, w, ms.shields.fraction(), Palette.SHIELD, px * 2.0)
	if ms.move_target != Vector2.INF:
		draw_line(Vector2.ZERO, ms.move_target - ms.global_position, Palette.with_alpha(col, 0.3), 2.0 * px)
