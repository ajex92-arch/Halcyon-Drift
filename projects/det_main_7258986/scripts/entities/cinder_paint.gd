class_name CinderPaint
extends RefCounted
## WHAT THIS IS: the painter of Cinder's alien look. Cinder is the red team.
## Its ships and units are drawn as dark, bladed shapes with a red outline,
## glowing "veins" and engine lights, instead of the plain amber-style
## outlines Aurelian uses. It only draws; it changes nothing in the game.
##
## HOW IT WORKS:
##   - The shapes live in CinderShapes as plain lists of points. The first
##     time a shape is wanted, prepare() turns it into packed arrays (Godot's
##     fast lists) and keeps them, so a frame never loops over the points in
##     script code: draw_shape() turns a whole shape to its place and size
##     with one multiplication (a Transform2D times a packed array), which
##     Godot does in its own fast code.
##   - Every drawing command costs real time (each one is a "draw call", and a
##     smooth, antialiased line costs three), so a shape is drawn with as few
##     commands as its size on the screen deserves:
##       tiny  (under TINY_PX pixels long): its simple outline filled, and a
##             plain thin line round it: 2 commands, cheaper than the plain
##             Aurelian outline. The fill is tinted red, so a far-away
##             Cinder ship reads as a red glyph and not a dark smudge.
##       small (under BIG_PX): the full outline filled, a smooth red line
##             round it, and one engine light.
##       big   (BIG_PX or more): also the layered plates (each its own command),
##             the glowing veins (a few long lines; the shapes are built so a
##             whole ship's veins are one or two lines) and every engine light.
##   - The size of every shape is the size the Aurelian outline would have, so
##     hits and ranges read the same. Only the picture changes.
##   - A shape may carry a "body" tint (a number in its table): its fill is never
##     less red than that, at any size. The lane minions use it, so they read as
##     solid bodies where the pilot hulls are dark.
##   - The alien look is always on in play. Only the gallery test switches it
##     off (set_alien), to compare the two looks and to measure what the new
##     drawing costs.
##   - A hit shows on the outline, not on the fill: for a moment after a hit the
##     line round a shape turns toward white and gets thicker (Palette.hit_edge,
##     Palette.hit_width); the fill and the plates keep their colours.
##   - Test only: with DrawParts.outline off, the red line round a shape is
##     left out (every size of shape, and with it the hit flash); the fill,
##     plates, veins and lights stay.
##
## WHO USES IT: ShipVisual (pilot ships, their engine flames) and UnitVisual
## (minions, drones, wards, turrets, repair bays and the mothership) call
## alien() to ask "is this one Cinder's?" and then draw through it. The
## gallery test (tests/hull_gallery.gd) flips set_alien() to compare the looks.

## A shape drawn shorter than this many screen pixels is "tiny".
const TINY_PX := 24.0
## A shape drawn this many screen pixels long or longer is "big": it also gets
## plates, veins and every engine light.
const BIG_PX := 44.0
## A shape this long (screen pixels) or longer also gets a glow round each
## engine light (only the capital ships and the mothership are that big).
const HALO_PX := 150.0
## How red the fill of the smallest shapes gets: 0 = the dark hull colour,
## 1 = the team red. It fades to 0 at BIG_PX.
const TINY_TINT := 0.6
## How fast the veins pulse, in radians per millisecond (about one pulse a
## second and a half).
const PULSE_RATE := 0.0045

## The prepared pilot hulls: hull id -> prepared shape (see prepare()).
static var _hulls := {}
## The prepared minions, drones, wards, turrets and bays, by name.
static var _units := {}
## The prepared mothership (an empty dictionary until first wanted).
static var _mother := {}
## A unit hexagon (corners one unit from the middle): the shape of an engine
## light, scaled and moved into place with a Transform2D.
static var _hex := PackedVector2Array()
## 1 = Cinder is drawn alien (always, in play), 0 = drawn plain (only while
## the gallery test compares the two looks).
static var _mode := 1


## Is `team` drawn with the alien look? True only for Cinder, and only while
## the alien look is on (it always is, except inside the gallery test).
static func alien(team: int) -> bool:
	return team == Rules.CINDER and _mode == 1


## Switch the alien look on or off while the game runs. Tests use it to draw
## both looks in one run.
static func set_alien(on: bool) -> void:
	_mode = 1 if on else 0


# --- prepared shapes -----------------------------------------------------------------------------

## Turn one shape table of CinderShapes (plain lists) into a prepared shape:
## the same things as packed arrays, plus a closed copy of the two outlines
## (the first point repeated at the end, which draw_polyline needs), "len", the
## shape's length along its nose direction (in the shape's own units), and
## "body", the least red its fill may be (0 when the table has none).
static func prepare(raw: Dictionary) -> Dictionary:
	# Step 1: the full outline, and how long it is.
	var sil := PackedVector2Array(raw["sil"])
	var x_min := INF
	var x_max := -INF
	for p: Vector2 in sil:
		x_min = minf(x_min, p.x)
		x_max = maxf(x_max, p.x)
	var line := sil.duplicate()
	line.append(sil[0])
	# Step 2: the simple outline for tiny shapes.
	var lo := PackedVector2Array(raw["lo"])
	var lo_line := lo.duplicate()
	lo_line.append(lo[0])
	# Step 3: the plates and the veins.
	var parts: Array = []
	for pt: Dictionary in raw["parts"]:
		parts.append({"fill": PackedVector2Array(pt["pts"]), "shade": int(pt["shade"])})
	var veins: Array = []
	for v: Array in raw["veins"]:
		veins.append(PackedVector2Array(v))
	return {"sil": sil, "line": line, "lo": lo, "lo_line": lo_line, "parts": parts, "veins": veins, "glow": raw["glow"], "jet": raw.get("jet", []), "len": x_max - x_min, "body": float(raw.get("body", 0.0))}


## The prepared shape of pilot hull `id` ("fighter" for an unknown id).
static func hull(id: String) -> Dictionary:
	var rec = _hulls.get(id)
	if rec == null:
		rec = prepare(CinderShapes.HULLS.get(id, CinderShapes.HULLS["fighter"]))
		_hulls[id] = rec
	return rec


## The prepared shape of minion type `type_id` ("fighter" for an unknown type).
static func minion(type_id: String) -> Dictionary:
	var key := "minion_" + type_id
	var rec = _units.get(key)
	if rec == null:
		rec = prepare(CinderShapes.MINIONS.get(type_id, CinderShapes.MINIONS["fighter"]))
		_units[key] = rec
	return rec


## The prepared shape of a small unit: "mining_drone", "repair_drone", "ward",
## "repair_bay", or a turret type ("pd" or "torp").
static func unit_shape(name: String) -> Dictionary:
	var rec = _units.get(name)
	if rec == null:
		rec = prepare(CinderShapes.UNITS[name])
		_units[name] = rec
	return rec


## The prepared shape of the mothership (drawn for a 1600 x 340 ship; the
## caller stretches it to the real length and beam).
static func mothership() -> Dictionary:
	if _mother.is_empty():
		_mother = prepare(CinderShapes.MOTHERSHIP)
	return _mother


## Where the engine flames of hull `id` come out, in the hull's 36-unit design
## space: [the main flame's point, the side flames' point]. The side point's y
## is the distance from the middle; the other side is its mirror.
static func jets(id: String) -> Array:
	return hull(id)["jet"]


# --- drawing -------------------------------------------------------------------------------------------

## Draw prepared shape `rec` on `ci` (the Visual node whose _draw() is running).
##   scale   how big: the shape's units to world units (uniform for ships).
##   rot     the turn of the unit, in radians (the Visual node itself turns the
##           other way, so shapes are turned here, by hand).
##   px      world units per screen pixel: line widths and the size tests use it.
##   edge    the outline colour (team red, or the ace colour).
##   edge_w  the outline width in screen pixels.
##   flash   the hit flash strength: how far the outline turns toward white and
##           how much thicker it gets (Palette.HIT_FLASH; 0 = not hit just now).
##           The fill and the plates are not touched by it.
##   heat    how hot the engines glow, 0..1.
##   phase   a number that is different for every unit, so veins do not all
##           pulse at the same moment.
##   alpha   1 = solid; less = see-through (a turret still being built).
static func draw_shape(ci: CanvasItem, rec: Dictionary, scale: Vector2, rot: float, px: float, edge: Color, edge_w: float, flash: float, heat: float, phase: float, alpha: float = 1.0) -> void:
	# Step 1: one turn-and-size for every point of the shape, and how long the
	# shape is on the screen (that decides how much is drawn).
	var xf := Transform2D(rot, scale, 0.0, Vector2.ZERO)
	var screen_len: float = float(rec["len"]) * scale.x / px
	# Step 2: the hull fill: the smaller the shape on the screen, the redder it
	# is (never less red than the shape's own "body" tint). A hit does not touch it.
	var tint := maxf(TINY_TINT * clampf((BIG_PX - screen_len) / (BIG_PX - 12.0), 0.0, 1.0), float(rec["body"]))
	var fill: Color = Palette.CINDER_HULL.lerp(Palette.CINDER, tint)
	fill.a = alpha
	# The outline: a hit turns it toward white and makes it thicker.
	var line_col := Color(edge.r, edge.g, edge.b, edge.a * alpha)
	var line_w := edge_w
	if flash > 0.0:
		line_col = Palette.hit_edge(line_col, flash)
		line_w = Palette.hit_width(edge_w, flash)
	# Step 3: tiny shapes: the simple outline, filled and lined, and nothing else.
	if screen_len < TINY_PX:
		var lo: PackedVector2Array = rec["lo"]
		var lo_line: PackedVector2Array = rec["lo_line"]
		ci.draw_colored_polygon(xf * lo, fill)
		if DrawParts.outline:
			ci.draw_polyline(xf * lo_line, line_col, line_w * px * 0.85, false)
		return
	# Step 4: the full outline, filled.
	var sil: PackedVector2Array = rec["sil"]
	ci.draw_colored_polygon(xf * sil, fill)
	var big := screen_len >= BIG_PX
	# Step 5: big shapes: the layered plates, back to front.
	if big:
		for part: Dictionary in rec["parts"]:
			var shade: Color = Palette.CINDER_SHADES[int(part["shade"])]
			shade.a = alpha
			var plate: PackedVector2Array = part["fill"]
			ci.draw_colored_polygon(xf * plate, shade)
	# Step 6: the red outline over the plates (a smooth line; it is the part that
	# flashes after a hit). (Test only: left out when DrawParts.outline is off; the
	# fill, plates, veins and lights stay.)
	if DrawParts.outline:
		var outline: PackedVector2Array = rec["line"]
		ci.draw_polyline(xf * outline, line_col, line_w * px, true)
	# Step 7: big shapes: the glowing veins (plain lines).
	if big:
		var pulse := 0.8 + 0.2 * sin(float(Time.get_ticks_msec()) * PULSE_RATE + phase)
		var vein := Palette.CINDER_VEIN
		var vein_col := Color(vein.r, vein.g, vein.b, 0.95 * pulse * alpha)
		for v: PackedVector2Array in rec["veins"]:
			ci.draw_polyline(xf * v, vein_col, 1.4 * px, false)
	# Step 8: the engine lights: a small bright hexagon each (a small shape
	# only shows its first), and on the biggest ships a faint, larger one
	# round it. Never smaller than a pixel.
	if _hex.is_empty():
		for k in 6:
			_hex.append(Vector2.from_angle(TAU * float(k) / 6.0))
	var spark := Palette.CINDER_GLOW
	var halo := Palette.CINDER_VEIN
	var lights: Array = rec["glow"]
	var shown := lights.size() if big else mini(1, lights.size())
	for i in shown:
		var g: Vector3 = lights[i]
		var at := xf * Vector2(g.x, g.y)
		var r := maxf(g.z * scale.x * 0.7, 1.0 * px)
		if screen_len >= HALO_PX:
			ci.draw_colored_polygon(Transform2D(0.0, Vector2(r * 2.1, r * 2.1), 0.0, at) * _hex, Color(halo.r, halo.g, halo.b, (0.04 + 0.1 * heat) * alpha))
		ci.draw_colored_polygon(Transform2D(0.0, Vector2(r, r), 0.0, at) * _hex, Color(spark.r, spark.g, spark.b, (0.55 + 0.4 * heat) * alpha))


## Draw a turret's gun as a fang: a dark blade with a red edge and a glowing
## vein down its middle, from the middle of the turret out along direction
## `dir` (a length-1 arrow), `length` long and `width` wide at its root. `col`
## is the outline colour (its alpha is how solid the fang is) and `px` is world
## units per screen pixel.
static func draw_fang(ci: CanvasItem, dir: Vector2, length: float, width: float, col: Color, px: float) -> void:
	var side := dir.orthogonal() * width
	var blade := PackedVector2Array([side, dir * length, -side])
	var plate := Palette.CINDER_PLATE
	ci.draw_colored_polygon(blade, Color(plate.r, plate.g, plate.b, col.a))
	blade.append(side)
	ci.draw_polyline(blade, col, 1.6 * px, true)
	var vein := Palette.CINDER_VEIN
	ci.draw_line(dir * length * 0.15, dir * length * 0.9, Color(vein.r, vein.g, vein.b, 0.9 * col.a), 1.2 * px)


# --- engine flames ---------------------------------------------------------------------------------

## Give a Cinder ship's three flame emitters their own colours: a hot orange
## main flame and warm side flames (the Aurelian flames are pale yellow and
## pale teal). It only changes each emitter's colour ramp; no emitter is made
## or removed. ShipVisual calls it once, when it first sees a Cinder ship.
static func tint_jets(main_jet: CPUParticles2D, port_jet: CPUParticles2D, star_jet: CPUParticles2D) -> void:
	_recolor(main_jet, Palette.CINDER_JET)
	_recolor(port_jet, Palette.CINDER_SIDE_JET)
	_recolor(star_jet, Palette.CINDER_SIDE_JET)


## Fade emitter `p`'s dots from colour `col` (90% solid) to see-through, the
## same way ShipVisual makes them.
static func _recolor(p: CPUParticles2D, col: Color) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Palette.with_alpha(col, 0.9))
	grad.set_color(1, Palette.with_alpha(col, 0.0))
	p.color_ramp = grad
