class_name ShipVisual
extends Node2D
## WHAT THIS IS: the "painter" of a pilot ship. It draws the ship's shape in
## its team colour, its four shield arcs, an arrow showing where it is
## drifting, its hull and shield bars and its name, plus the engine flames.
## It changes nothing in the game; it only draws.
##
## HOW IT WORKS:
##   - It is the "Visual" child node of every Ship (scenes/entities/
##     ship.tscn). Each frame, _process() updates the flames and asks Godot
##     to redraw; Godot then calls _draw().
##   - The ship node turns with the ship, and so would this child. To keep
##     the arrow, the bars and the name upright, this node turns itself back
##     the other way ("counter-rotates"), so its drawing frame always lines
##     up with the world. The ship's shape is then turned by hand.
##   - The camera can zoom far out (a "Homeworld" zoom, after the space game
##     of that name). Ships are drawn bigger than life when needed so they
##     are always at least MIN_PX screen pixels long, and lines are
##     multiplied by `px` (world units per screen pixel) so they keep the
##     same thickness on screen at any zoom.
##   - The flames are CPUParticles2D nodes (small dots of light fired out by
##     Godot): one for the main engine and one for each side thruster.
##   - With --sim-only (Game.sim_only) it draws nothing at all: it hides
##     itself, makes no flames and does no per-frame work. One detail keeps
##     the match exactly the same: making a CPUParticles2D takes one number
##     from the game's shared random sequence, so _ready() takes the same
##     three numbers itself (see there).
##
## WHO USES IT: Godot runs it as part of ship.tscn. It reads the Ship's
## thrust_* values, boosting, ace_t, flash, shields, velocity and f_max,
## and the pilot profile's is_human. Ships.HULLS points here (HULLS below)
## for each hull's silhouette.

## Each hull's outline: a list of corner points, nose pointing right (+x),
## for a ship 36 units long (they are scaled to the hull's real length).
## Hulls not listed here use the "fighter" shape.
const HULLS := {
	"scout": [Vector2(18, 0), Vector2(-10, 5), Vector2(-14, 0), Vector2(-10, -5)],
	"fighter": [Vector2(18, 0), Vector2(-8, 7), Vector2(-4, 0), Vector2(-8, -7)],
	"lance": [Vector2(20, 0), Vector2(2, 3), Vector2(-10, 8), Vector2(-6, 0), Vector2(-10, -8), Vector2(2, -3)],
	"bomber": [Vector2(16, 0), Vector2(4, 6), Vector2(-12, 8), Vector2(-8, 0), Vector2(-12, -8), Vector2(4, -6)],
	"logistics": [Vector2(14, 0), Vector2(8, 9), Vector2(-12, 9), Vector2(-14, 0), Vector2(-12, -9), Vector2(8, -9)],
	"support": [Vector2(12, 0), Vector2(-2, 5), Vector2(-10, 4), Vector2(-6, 0), Vector2(-10, -4), Vector2(-2, -5)],
	"flak": [Vector2(16, 0), Vector2(6, 10), Vector2(-14, 9), Vector2(-16, 0), Vector2(-14, -9), Vector2(6, -10)],
	"ion": [Vector2(18, 0), Vector2(14, 4), Vector2(-12, 7), Vector2(-16, 0), Vector2(-12, -7), Vector2(14, -4)],
	"destroyer": [Vector2(18, 0), Vector2(10, 4), Vector2(-2, 4.5), Vector2(-6, 6), Vector2(-17, 5), Vector2(-18, 0), Vector2(-17, -5), Vector2(-6, -6), Vector2(-2, -4.5), Vector2(10, -4)],
	"battlecruiser": [Vector2(18, 0), Vector2(12, 5), Vector2(0, 5), Vector2(-4, 7), Vector2(-16, 6), Vector2(-18, 0), Vector2(-16, -6), Vector2(-4, -7), Vector2(0, -5), Vector2(12, -5)],
}
## Minimum drawn length of a ship, in screen pixels.
const MIN_PX := 16.0

## The ship we draw (our parent node).
var ship: Ship
## Flames of the main engine.
var main_jet: CPUParticles2D
## Flames of the port (left-pushing) thruster.
var port_jet: CPUParticles2D
## Flames of the starboard (right-pushing) thruster.
var star_jet: CPUParticles2D
## True when the human player flies this ship (drawn bolder, named "YOU").
var is_human := false


## Find our ship and make the three flame emitters. With --sim-only
## (Game.sim_only) nothing is ever drawn, so we make no flames, hide
## ourselves and stop our per-frame work for good: the simulation never reads
## this node. One thing must still happen: Godot's CPUParticles2D picks its
## own random seed from the game's shared random sequence when it is made (it
## takes one number from it), and that is the very sequence the AI and the
## guns use. So the three flames cost three numbers of the sequence, and we
## take the same three here, or every later dice roll would be different and
## the match would no longer be the same match.
func _ready() -> void:
	ship = get_parent() as Ship
	if Game.sim_only:
		visible = false
		set_process(false)
		for _i in 3:
			randi()
		return
	main_jet = _jet(Color(1.0, 0.85, 0.6))
	port_jet = _jet(Palette.SIDE_JET)
	star_jet = _jet(Palette.SIDE_JET)


## Make one flame emitter in colour `col`: 24 dots that live 0.35 s and fade
## out. It is "top level", so it ignores our turning and we place it in
## world coordinates ourselves.
func _jet(col: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	# How many dots, how long they live, how they fly.
	p.amount = 24
	p.lifetime = 0.35
	p.local_coords = false
	p.emitting = false
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 140.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	# Fade from 90% to fully see-through over each dot's life.
	var grad := Gradient.new()
	grad.set_color(0, Palette.with_alpha(col, 0.9))
	grad.set_color(1, Palette.with_alpha(col, 0.0))
	p.color_ramp = grad
	p.top_level = true
	add_child(p)
	return p


## Every frame: counter-rotate, refresh the flames and ask for a redraw.
func _process(_dt: float) -> void:
	if ship == null or not ship.alive:
		return
	rotation = -ship.rotation
	is_human = ship.profile != null and ship.profile.is_human
	_update_jets()
	queue_redraw()


## How much bigger than life to draw the ship (1 = true size) so it is at
## least MIN_PX screen pixels long at the current camera zoom.
func _scale() -> float:
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	var length := float(ship.def.get("length", 26.0))
	return maxf(1.0, MIN_PX / maxf(0.001, length * z))


## Place and switch the three flame emitters: the main flame at the tail
## (bigger and faster while boosting), the side flames on each flank.
func _update_jets() -> void:
	# Zoom helpers: px = world units per screen pixel; k = drawing scale.
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	var px := 1.0 / maxf(0.02, z)
	var k := _scale()
	var length := float(ship.def.get("length", 26.0)) * k
	var f := Vector2.from_angle(ship.rotation)
	var port := Util.port_of(ship.rotation)
	var g := ship.global_position
	# Main engine: behind the ship, blowing backwards.
	main_jet.global_position = g - f * length * 0.45
	main_jet.direction = -f
	main_jet.emitting = ship.thrust_main > 0.1
	main_jet.initial_velocity_min = (90.0 if not ship.boosting else 180.0) * px * 0.4
	main_jet.initial_velocity_max = (150.0 if not ship.boosting else 260.0) * px * 0.4
	main_jet.scale_amount_min = 2.0 * px
	main_jet.scale_amount_max = 3.5 * px * (1.5 if ship.boosting else 1.0)
	# Port thrust pushes the hull to port, so its exhaust vents starboard.
	port_jet.global_position = g - port * length * 0.25
	port_jet.direction = -port
	port_jet.emitting = ship.thrust_port > 0.1
	star_jet.global_position = g + port * length * 0.25
	star_jet.direction = port
	star_jet.emitting = ship.thrust_star > 0.1
	# Both side flames: smaller and slower than the main one.
	for j: CPUParticles2D in [port_jet, star_jet]:
		j.initial_velocity_min = 60.0 * px * 0.4
		j.initial_velocity_max = 100.0 * px * 0.4
		j.scale_amount_min = 1.5 * px
		j.scale_amount_max = 2.5 * px


## Draw the ship (Godot calls this after queue_redraw()). Some extras only
## show for the human's own ship or when zoomed in close enough.
func _draw() -> void:
	if ship == null or not ship.alive:
		return
	# Zoom helpers: z = camera zoom (bigger = closer), px = world units per
	# screen pixel, k = drawing scale, u = shape scale.
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	var px := 1.0 / maxf(0.02, z)
	var k := _scale()
	var length := float(ship.def.get("length", 26.0))
	var u := length * k / 36.0
	var col := Palette.team(ship.team)
	var rot := ship.rotation
	_draw_hull(u, rot, col, px)
	# Shield arcs sit on a ring around the ship.
	var sr := maxf(length * k * 0.62, ship.radius * 1.3)
	_draw_shield_arcs(sr, rot, px)
	# Velocity arrow (always for the human, others when zoomed in).
	if is_human or z > 0.4:
		_velocity_arrow(px)
	# Bars and callsign.
	if is_human or z > 0.3:
		_draw_bars_and_name(sr, length * k, col, px, z)


## The ship's shape at scale `u`, turned to `rot`: filled (lighter for a
## moment after a hit) and outlined in the team colour (Palette.ACE while "ace";
## thicker for the human).
func _draw_hull(u: float, rot: float, col: Color, px: float) -> void:
	var edge := Palette.ACE if ship.ace_t > 0.0 else col
	var pts := PackedVector2Array()
	for p: Vector2 in HULLS.get(ship.hull_id, HULLS["fighter"]):
		pts.append((p * u).rotated(rot))
	# "lerp" mixes two colours: here 60% of the way from HULL_FILL to ICE.
	var fill := Palette.HULL_FILL.lerp(Palette.ICE, 0.6) if ship.flash > 0.0 else Palette.HULL_FILL
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, edge, (2.2 if is_human else 1.4) * px, true)


## Shield arcs on a ring of radius `sr`: one per zone (front, rear, left,
## right), brighter and thicker when full, extra bright just after a hit,
## and hidden when the zone is empty or has no share.
func _draw_shield_arcs(sr: float, rot: float, px: float) -> void:
	var sh := ship.shields
	for zone in 4:
		var cap := sh.cap(zone)
		if cap <= 0.0:
			continue
		var frac := sh.values[zone] / cap
		# Each zone's arc is centred on its side and spans 0.7 rad each way.
		var center_a: float = rot + float([0.0, PI, -PI / 2.0, PI / 2.0][zone])
		var a := 0.12 + 0.45 * frac
		if sh.since_hit < 0.25:
			a += 0.35
		if frac <= 0.01:
			continue
		draw_arc(Vector2.ZERO, sr, center_a - 0.7, center_a + 0.7, 12, Palette.with_alpha(Palette.SHIELD, a), (1.0 + 2.0 * frac) * px, true)


## The hull bar (team colour), the thin shield bar above it, and (when
## close enough, or for the human) the name above them. `drawn_len` is the
## ship's drawn length; the bars sit just above the shield ring `sr`.
func _draw_bars_and_name(sr: float, drawn_len: float, col: Color, px: float, z: float) -> void:
	var bw := maxf(34.0 * px, minf(140.0 * px, drawn_len * 0.9))
	var by := -sr - 10.0 * px
	draw_rect(Rect2(-bw / 2.0, by, bw, 3.0 * px), Palette.with_alpha(Palette.VOID, 0.75))
	draw_rect(Rect2(-bw / 2.0, by, bw * ship.hull_frac(), 3.0 * px), col)
	draw_rect(Rect2(-bw / 2.0, by - 4.0 * px, bw * ship.shields.fraction(), 2.0 * px), Palette.SHIELD)
	if is_human or z > 0.45:
		var font := ThemeDB.fallback_font
		var label := "YOU" if is_human else ship.display_name.to_upper()
		draw_string(font, Vector2(-60.0 * px, by - 8.0 * px), label, HORIZONTAL_ALIGNMENT_CENTER, 120.0 * px, int(11.0 * px), Palette.ICE if is_human else Palette.NEUTRAL)


## An arrow showing which way and how fast the ship drifts (its velocity),
## up to 1.45x its top-speed length. Over top speed (by more than 4%) it
## turns the Palette.ACE colour. When the nose points away from the drift, a small "slip" line
## joins the two directions.
func _velocity_arrow(px: float) -> void:
	var v := ship.velocity
	var sp := v.length()
	if sp < 12.0:
		return
	# Arrow length and colour.
	var cap := maxf(80.0, ship.f_max)
	var length := minf(1.45, sp / cap) * 80.0 * px
	var n := v / sp
	var over := sp > cap * 1.04
	var col := Palette.ACE if over else Palette.with_alpha(Palette.ICE, 0.9)
	# The line and its triangle tip.
	var tip := n * length
	draw_line(Vector2.ZERO, tip, col, (2.0 if is_human else 1.2) * px, true)
	var perp := Vector2(-n.y, n.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - n * 7.0 * px + perp * 4.0 * px, tip - n * 7.0 * px - perp * 4.0 * px]), col)
	# Nose-vs-velocity slip tick.
	var f := Vector2.from_angle(ship.rotation)
	if absf(f.angle_to(n)) > 0.18 and sp > 40.0:
		draw_line(f * 18.0 * px, n * 18.0 * px, Palette.with_alpha(Palette.VEIL, 0.8), 1.0 * px)
