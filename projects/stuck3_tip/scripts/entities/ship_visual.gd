class_name ShipVisual
extends Node2D
## WHAT THIS IS: the "painter" of a pilot ship. It draws the ship's shape in
## its team colour, its four shield arcs, its hull and shield bars and its
## name, plus the engine flames, and (on the ship the human flies, and on no
## other) an arrow showing where it is drifting. It changes nothing in the
## game; it only draws.
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
##   - Cinder (the red team) wears an alien look: a Cinder ship's shape is
##     drawn by CinderPaint from the tables in CinderShapes (dark, bladed hulls
##     with glowing veins) instead of from HULLS below, and its flames come
##     out of the alien hull's own engines, a quarter smaller than Aurelian's
##     (CINDER_JET_SIZE). Each Cinder hull keeps the length and width of its
##     Aurelian hull; shield arcs, bars, name and the arrow are drawn as
##     before.
##   - Aurelian (the amber team) wears a steel look: a hull is drawn by
##     AurelianPaint from the named pieces in AurelianShapes (armour plates,
##     glass canopies, engine nozzles) inside an amber outline, and its flames
##     come out of the hull's own engines. The plain outlines of HULLS below are
##     drawn only while the steel look is off (the hull gallery's measurements).
##   - Every gun that turns (a turret or an automatic mount) is drawn as a small
##     turret on the hull by TurretPaint, turned the way the gun points; a fixed
##     gun gets none.
##   - With --sim-only (Game.sim_only) it draws nothing at all: it hides
##     itself, makes no flames and does no per-frame work. One detail keeps
##     the match exactly the same: making a CPUParticles2D takes one number
##     from the game's shared random sequence, so _ready() takes the same
##     three numbers itself (see there).
##   - Test only: the switches of DrawParts (--bench-off=flames,arcs,arrow,
##     bars,name,outline,redraw) turn one part of all this off, so a test can
##     measure what that part costs. With no switch given every part is
##     drawn as always. The three flame emitters are still made with "flames"
##     off, for the same random-number reason as above.
##
## WHO USES IT: Godot runs it as part of ship.tscn. It reads the Ship's
## thrust_* values, boosting, ace_t, flash, shields, velocity and f_max,
## and the pilot profile's is_human, and the ship's mounts. AurelianPaint draws
## the Aurelian hulls, CinderPaint the Cinder hulls (and tints their flames),
## TurretPaint the turrets. DrawParts holds the test-only switches it reads.

## Each hull's plain outline: a list of corner points, nose pointing right (+x),
## for a ship 36 units long (they are scaled to the hull's real length). The
## Aurelian steel hulls (AurelianShapes) keep these sizes to within about a
## tenth (more only where a gun mount sits outside the plain outline: the
## Bomber's torpedo mount, the Destroyer's and Battlecruiser's point-defense
## mounts); this table is drawn only while the steel look is off, and is the size
## the hull gallery checks the Cinder shapes against. Hulls not listed here use
## the "fighter" shape.
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
## How big a Cinder ship's engine flames are next to Aurelian's: 0.75 = a
## quarter smaller (smaller dots, and plumes a quarter shorter and narrower),
## so they do not drown out the alien hull itself (the user, Sun 2026-10-18:
## "The engine effects are too large and overwhelm the design").
const CINDER_JET_SIZE := 0.75

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
## True once the flames of a Cinder ship have been given their own colours
## (CinderPaint.tint_jets). It happens on the first frame, because the ship's
## team is not known yet when _ready() runs.
var _tinted := false
## True once _draw() has drawn this ship at least once. With the test switch
## DrawParts.redraw off we ask for a new picture only until this is true.
var _drawn := false
## True while the three flame emitters are parked (stopped and hidden) because
## the test switch DrawParts.flames is off.
var _jets_hidden := false


## Find our ship and make the three flame emitters. With --sim-only
## (Game.sim_only) nothing is ever drawn, so we make no flames, hide
## ourselves and stop our per-frame work for good: the simulation never reads
## this node. One thing must still happen: Godot's CPUParticles2D picks its
## own random seed from the game's shared random sequence when it is made (it
## takes one number from it), and that is the very sequence the AI and the
## guns use. So the three flames cost three numbers of the sequence, and we
## take the same three here, or every later dice roll would be different and
## the match would no longer be the same match. For the same reason the three
## emitters are made even when the test switch DrawParts.flames is off (it
## only stops and hides them, in _update_jets()).
func _ready() -> void:
	ship = get_parent() as Ship
	if Game.sim_only:
		visible = false
		set_process(false)
		for _i in 3:
			randi()
		return
	DrawParts.read_options()
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


## Every frame: counter-rotate, refresh the flames and ask for a redraw. (Test
## only: with DrawParts.redraw off we ask for a redraw just until the first
## picture is drawn; Godot keeps that picture.)
func _process(_dt: float) -> void:
	if ship == null or not ship.alive:
		return
	rotation = -ship.rotation
	is_human = ship.profile != null and ship.profile.is_human
	_update_jets()
	if DrawParts.redraw or not _drawn:
		queue_redraw()


## How much bigger than life to draw the ship (1 = true size) so it is at
## least MIN_PX screen pixels long at the current camera zoom.
func _scale() -> float:
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	var length := float(ship.def.get("length", 26.0))
	return maxf(1.0, MIN_PX / maxf(0.001, length * z))


## Place and switch the three flame emitters: the main flame at the tail
## (bigger and faster while boosting), the side flames on each flank. (Test
## only: with DrawParts.flames off the emitters are parked instead, stopped and
## hidden, and none of the work below is done; they come back when it is on.)
func _update_jets() -> void:
	# Step 0: the test switch for the flames (normally on).
	if not DrawParts.flames:
		if not _jets_hidden:
			_jets_hidden = true
			for j: CPUParticles2D in [main_jet, port_jet, star_jet]:
				j.emitting = false
				j.visible = false
		return
	if _jets_hidden:
		_jets_hidden = false
		for j: CPUParticles2D in [main_jet, port_jet, star_jet]:
			j.visible = true
	# Zoom helpers: px = world units per screen pixel; k = drawing scale.
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	var px := 1.0 / maxf(0.02, z)
	var k := _scale()
	var length := float(ship.def.get("length", 26.0)) * k
	var f := Vector2.from_angle(ship.rotation)
	var port := Util.port_of(ship.rotation)
	var g := ship.global_position
	# Where the flames start: the main flame behind the middle (45% of the
	# length), the side flames 25% of the length out to each side.
	var main_at := g - f * length * 0.45
	var side := port * length * 0.25
	var side_shift := Vector2.ZERO
	# How big the flames are: 1 = Aurelian's size. Their dots and their speed
	# are both multiplied by it, so a plume shrinks the same way in length and
	# width (a dot's distance is its speed times its fixed life).
	var jet_size := 1.0
	# Both teams' hulls have their engines in places of their own: the flames
	# follow them (each hull's own points, in its 36-unit design space). Cinder's
	# flames also get their own colours the first time we see a Cinder ship, and
	# are a quarter smaller (CINDER_JET_SIZE).
	var jets: Array = []
	if CinderPaint.alien(ship.team):
		if not _tinted:
			_tinted = true
			CinderPaint.tint_jets(main_jet, port_jet, star_jet)
		jets = CinderPaint.jets(ship.hull_id)
		jet_size = CINDER_JET_SIZE
	elif AurelianPaint.on(ship.team):
		jets = AurelianPaint.jets(ship.hull_id)
	if not jets.is_empty():
		var un := length / 36.0
		var main_spot: Vector2 = jets[0]
		var side_spot: Vector2 = jets[1]
		main_at = g + f * (main_spot.x * un) - port * (main_spot.y * un)
		side = port * (side_spot.y * un)
		side_shift = f * (side_spot.x * un)
	# Main engine: behind the ship, blowing backwards.
	main_jet.global_position = main_at
	main_jet.direction = -f
	main_jet.emitting = ship.thrust_main > 0.1
	main_jet.initial_velocity_min = (90.0 if not ship.boosting else 180.0) * px * 0.4 * jet_size
	main_jet.initial_velocity_max = (150.0 if not ship.boosting else 260.0) * px * 0.4 * jet_size
	main_jet.scale_amount_min = 2.0 * px * jet_size
	main_jet.scale_amount_max = 3.5 * px * (1.5 if ship.boosting else 1.0) * jet_size
	# Port thrust pushes the hull to port, so its exhaust vents starboard.
	port_jet.global_position = g - side + side_shift
	port_jet.direction = -port
	port_jet.emitting = ship.thrust_port > 0.1
	star_jet.global_position = g + side + side_shift
	star_jet.direction = port
	star_jet.emitting = ship.thrust_star > 0.1
	# Both side flames: smaller and slower than the main one.
	for j: CPUParticles2D in [port_jet, star_jet]:
		j.initial_velocity_min = 60.0 * px * 0.4 * jet_size
		j.initial_velocity_max = 100.0 * px * 0.4 * jet_size
		j.scale_amount_min = 1.5 * px * jet_size
		j.scale_amount_max = 2.5 * px * jet_size


## Draw the ship (Godot calls this after queue_redraw()). The drift arrow is
## only for the human's own ship, at any zoom; the bars and the name also show
## on other ships when zoomed in close enough. (Test only: DrawParts can leave
## out the shield arcs, the arrow, the bars, the name and the hull outline;
## each is drawn as always when its switch is on.)
func _draw() -> void:
	if ship == null or not ship.alive:
		return
	_drawn = true
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
	# The guns that turn, as small turrets on the hull (a fixed gun gets none).
	TurretPaint.draw_mounts(self, ship, k, u, px, rot)
	# Shield arcs sit on a ring around the ship.
	var sr := maxf(length * k * 0.62, ship.radius * 1.3)
	if DrawParts.arcs:
		_draw_shield_arcs(sr, rot, px)
	# Velocity arrow: only on the ship the human flies, at any zoom.
	if DrawParts.arrow and is_human:
		_velocity_arrow(px)
	# Bars and callsign.
	if (DrawParts.bars or DrawParts.name_tag) and (is_human or z > 0.3):
		_draw_bars_and_name(sr, length * k, col, px, z)


## The ship's shape at scale `u`, turned to `rot`: filled and outlined in the
## team colour (Palette.ACE while "ace"; thicker for the human). A hit shows on
## the outline, not on the fill: for a moment after it the line turns toward
## white and gets thicker (Palette.hit_edge, Palette.hit_width). A Cinder ship
## is drawn by CinderPaint instead: a dark bladed hull with the same outline
## rules, glowing veins and engine lights (its engines glow harder the harder
## they burn). (Test only: the outline is left out when DrawParts.outline is
## off, and the hit flash with it; the fill stays.)
func _draw_hull(u: float, rot: float, col: Color, px: float) -> void:
	var edge := Palette.ACE if ship.ace_t > 0.0 else col
	var edge_w := 2.2 if is_human else 1.4
	# The hit flash strength (0 = not hit just now).
	var hit := Palette.HIT_FLASH if ship.flash > 0.0 else 0.0
	# How hot the engines glow, 0..1.
	var heat := clampf(0.35 + 0.65 * ship.thrust_main + (0.3 if ship.boosting else 0.0), 0.0, 1.0)
	if CinderPaint.alien(ship.team):
		CinderPaint.draw_shape(self, CinderPaint.hull(ship.hull_id), Vector2(u, u), rot, px, edge, edge_w, hit, heat, float(ship.uid) * 1.7)
		return
	if AurelianPaint.on(ship.team):
		AurelianPaint.draw_shape(self, AurelianPaint.hull(ship.hull_id), u, rot, px, edge, edge_w, hit, heat)
		return
	var pts := PackedVector2Array()
	for p: Vector2 in HULLS.get(ship.hull_id, HULLS["fighter"]):
		pts.append((p * u).rotated(rot))
	draw_colored_polygon(pts, Palette.HULL_FILL)
	if DrawParts.outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		if hit > 0.0:
			edge = Palette.hit_edge(edge, hit)
			edge_w = Palette.hit_width(edge_w, hit)
		draw_polyline(closed, edge, edge_w * px, true)


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
## ship's drawn length; the bars sit just above the shield ring `sr`. (Test
## only: DrawParts.bars and DrawParts.name_tag can each leave their part out.)
func _draw_bars_and_name(sr: float, drawn_len: float, col: Color, px: float, z: float) -> void:
	var bw := maxf(34.0 * px, minf(140.0 * px, drawn_len * 0.9))
	var by := -sr - 10.0 * px
	if DrawParts.bars:
		draw_rect(Rect2(-bw / 2.0, by, bw, 3.0 * px), Palette.with_alpha(Palette.VOID, 0.75))
		draw_rect(Rect2(-bw / 2.0, by, bw * ship.hull_frac(), 3.0 * px), col)
		draw_rect(Rect2(-bw / 2.0, by - 4.0 * px, bw * ship.shields.fraction(), 2.0 * px), Palette.SHIELD)
	if DrawParts.name_tag and (is_human or z > 0.45):
		var font := ThemeDB.fallback_font
		var label := "YOU" if is_human else ship.display_name.to_upper()
		draw_string(font, Vector2(-60.0 * px, by - 8.0 * px), label, HORIZONTAL_ALIGNMENT_CENTER, 120.0 * px, int(11.0 * px), Palette.ICE if is_human else Palette.NEUTRAL)


## An arrow showing which way and how fast the ship drifts (its velocity),
## up to 1.45x its top-speed length. Over top speed (by more than 4%) it
## turns the Palette.ACE colour. When the nose points away from the drift, a small "slip" line
## joins the two directions. Only the human's own ship gets one (_draw() asks).
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
	draw_line(Vector2.ZERO, tip, col, 2.0 * px, true)
	var perp := Vector2(-n.y, n.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - n * 7.0 * px + perp * 4.0 * px, tip - n * 7.0 * px - perp * 4.0 * px]), col)
	# Nose-vs-velocity slip tick.
	var f := Vector2.from_angle(ship.rotation)
	if absf(f.angle_to(n)) > 0.18 and sp > 40.0:
		draw_line(f * 18.0 * px, n * 18.0 * px, Palette.with_alpha(Palette.VEIL, 0.8), 1.0 * px)
