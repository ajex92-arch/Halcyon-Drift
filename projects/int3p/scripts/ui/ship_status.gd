class_name ShipStatus
extends Control
## WHAT THIS IS: the readout of the human's own ship, at the bottom centre
## of the HUD: shields, hull, energy, energy routing, the ship's special
## ability, boost and speed. DESIGN.md A15.
##
## HOW IT WORKS: it draws itself with lines, arcs and text every frame
## while it is visible (no child nodes).
##   Left: the "shield diamond", four arcs around a small ship icon (nose
##   up), one arc per shield zone: front (top), rear (bottom), left, right.
##   An arc's thickness is the share of the shield that the current focus
##   gives that zone; how much of its length is filled is how full that
##   zone is. The focused zone gets an amber outline, and a zone that just
##   broke flashes red. The icon's colour goes from green (full hull) to
##   red (no hull). Under it: the shield focus and its cooldown.
##   Right: hull / shields / energy bars, the four energy routing buttons
##   (keys 1-4) with a thin cooldown bar, the ability's state, then speed,
##   boost and warnings.
##
## WHO USES IT: Hud makes it from scenes/ui/ship_status.tscn and calls
## set_ship() 10 times a second (null while there is no live ship). It
## reads Ship, ShieldZones (ship.shields) and the energy system
## (ship.energy).

## Width of the readout (pixels).
const W := 430.0
## Height of the readout (pixels).
const H := 132.0
## Centre of the shield diamond, from the readout's top-left (pixels).
const DIAMOND_C := Vector2(66, 66)
## Radius of the shield arcs (pixels).
const DIAMOND_R := 46.0
## Screen direction of each zone: front up, rear down, left, right.
## (Angles in radians: a full turn is 2 x PI; 0 points right, PI / 2
## points down.)
const ZONE_ANGLE := [-PI / 2.0, PI / 2.0, PI, 0.0]
## The energy routing modes in button order (keys 1 to 4).
const ROUTE_ORDER := [Rules.ENERGY_WEAPONS, Rules.ENERGY_SHIELDS, Rules.ENERGY_THRUSTERS, Rules.ENERGY_BALANCED]
## The text on each energy routing button.
const ROUTE_SHORT := {Rules.ENERGY_WEAPONS: "1 Weapons", Rules.ENERGY_SHIELDS: "2 Shields", Rules.ENERGY_THRUSTERS: "3 Engines", Rules.ENERGY_BALANCED: "4 Balanced"}

## The ship we show, or null (then only the empty background is drawn).
var ship: Ship = null
## The font for all our text (Godot's built-in default font).
var font: Font


## Called once when the node joins the scene: fix our size, let the mouse
## pass through, and pick the font.
func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


## Show ship `s` (or nothing, with null) and redraw.
func set_ship(s: Ship) -> void:
	ship = s
	queue_redraw()


## Every frame, while visible, ask Godot to redraw us (queue_redraw makes
## Godot call _draw() again).
func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## Draw the readout: the background box, then (with a live ship) the
## shield diamond and the bars.
func _draw() -> void:
	draw_style_box(UiKit.box(Palette.with_alpha(Palette.PANEL, 0.9), Palette.LINE, 0), Rect2(Vector2.ZERO, size))
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return
	_draw_diamond()
	_draw_bars()


## Draw the left half: four shield arcs, the ship icon and the focus line.
func _draw_diamond() -> void:
	var sh := ship.shields
	var c := DIAMOND_C
	for z in 4:
		# Step 1: thickness from this zone's share of the whole shield:
		# 3 px plus up to 14 px more (a zone with half the shield is 17 px).
		var share := sh.cap(z) / maxf(1.0, sh.max_total)
		var thick := 3.0 + 14.0 * share / 0.5
		var mid: float = ZONE_ANGLE[z]
		# Each arc covers 38 degrees either side of its direction.
		var half := deg_to_rad(38.0)
		var r := DIAMOND_R
		# Step 2: a faint full arc, then the filled part, grown from the
		# middle outward by how full the zone is (0..1).
		draw_arc(c, r, mid - half, mid + half, 18, Palette.with_alpha(Palette.SHIELD, 0.16), thick, true)
		var frac := clampf(sh.values[z] / sh.cap(z), 0.0, 1.0) if sh.cap(z) > 0.0 else 0.0
		if frac > 0.0:
			var col := Palette.SHIELD.lerp(Palette.ICE, 0.15)
			draw_arc(c, r, mid - half * frac, mid + half * frac, 18, col, thick, true)
		# Step 3: a red flash on a zone that just broke (flash fades to 0).
		if sh.flash[z] > 0.0:
			draw_arc(c, r, mid - half, mid + half, 18, Palette.with_alpha(Palette.CINDER, sh.flash[z] * 2.0), thick + 2.0, true)
		# Step 4: an amber outline on the focused zone. Focus numbers are
		# zone + 1 (Rules.FOCUS_FRONT = 1 ... FOCUS_RIGHT = 4; 0 = balanced).
		var focused := sh.focus != Rules.FOCUS_BALANCED and sh.focus - 1 == z
		if focused:
			draw_arc(c, r + thick * 0.5 + 3.0, mid - half, mid + half, 18, Palette.AMBER, 2.0, true)
	# Ship icon, nose up. Its colour slides ("lerps", short for linear
	# interpolation: mixes in a straight line) from green to red as the
	# hull drops.
	var pts := PackedVector2Array([c + Vector2(0, -15), c + Vector2(10, 11), c + Vector2(0, 6), c + Vector2(-10, 11)])
	var hull_col := Palette.REPAIR.lerp(Palette.CINDER, 1.0 - ship.hull_frac())
	draw_colored_polygon(pts, Palette.with_alpha(hull_col, 0.85))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Palette.ICE, 1.0, true)
	# The focus line: amber when focus can be changed, grey with the
	# seconds left while it is cooling down.
	var focus_text := "Focus: %s" % Rules.FOCUS_NAMES[sh.focus]
	if ship.focus_cd > 0.0:
		focus_text += " (%.1fs)" % ship.focus_cd
	_text(Vector2(8, H - 8), focus_text, 11, Palette.AMBER if ship.focus_cd <= 0.0 else Palette.MIST)


## Draw the right half, top to bottom: three bars, the energy routing
## buttons, the ability line and the speed line. (x, y) is where the next
## row starts, in pixels.
func _draw_bars() -> void:
	var x := 140.0
	var w := W - x - 10.0
	var y := 10.0
	# Step 1: hull bar. It is green from 62.5% hull up (1 / 1.6 = 0.625)
	# and slides to red as the hull drops toward 0.
	_bar(Rect2(x, y, w, 14), ship.hull_frac(), Palette.REPAIR.lerp(Palette.CINDER, clampf(1.0 - ship.hull_frac() * 1.6, 0.0, 1.0)))
	_text(Vector2(x + 4, y + 11), "Hull %d / %d" % [int(ship.hull), int(ship.hull_max)], 11, Palette.ICE, true)
	y += 17.0
	# Step 2: shield and energy bars.
	_bar(Rect2(x, y, w, 13), ship.shields.fraction(), Palette.SHIELD)
	_text(Vector2(x + 4, y + 10), "Shields %d / %d" % [int(ship.shields.total()), int(ship.shields.max_total)], 10, Palette.ICE, true)
	y += 16.0
	_bar(Rect2(x, y, w, 13), ship.energy.fraction(), Palette.AMBER)
	_text(Vector2(x + 4, y + 10), "Energy %d / %d" % [int(ship.energy.value), int(ship.energy.max_value)], 10, Palette.ICE, true)
	y += 18.0
	# Step 3: energy routing: four buttons with 3-pixel gaps; the active
	# one is filled amber.
	var bw := (w - 9.0) / 4.0
	for i in 4:
		var mode: int = ROUTE_ORDER[i]
		var r := Rect2(x + float(i) * (bw + 3.0), y, bw, 18)
		var on := ship.energy.mode == mode
		draw_rect(r, Palette.AMBER if on else Palette.INK)
		draw_rect(r, Palette.LINE, false, 1.0)
		_text(r.position + Vector2(5, 13), ROUTE_SHORT[mode], 11, Palette.VOID if on else Palette.MIST)
	# Under the buttons, a thin bar shrinks while routing is cooling down.
	# The full cooldown depends on ship size (Rules.ENERGY_COOLDOWN, seconds).
	if ship.energy_cd > 0.0:
		var total := float(Rules.ENERGY_COOLDOWN[Rules.size_index(ship.size_class)])
		var k := clampf(ship.energy_cd / total, 0.0, 1.0)
		draw_rect(Rect2(x, y + 19, w * k, 2), Palette.MIST)
	y += 26.0
	# Step 4: the ability: active (seconds left), cooling down, not enough
	# energy, or ready.
	var sp_label: String = ship.def.get("special_label", "Ability")
	var sp_text: String
	var sp_col := Palette.ICE
	if ship.special_t > 0.0:
		sp_text = "%s: active %.1fs" % [sp_label, ship.special_t]
		sp_col = Palette.AMBER
	elif ship.special_cd > 0.0:
		sp_text = "%s: %.1fs" % [sp_label, ship.special_cd]
		sp_col = Palette.MIST
	elif ship.energy.value < float(ship.def["special_energy"]):
		sp_text = "%s: needs %d energy" % [sp_label, int(ship.def["special_energy"])]
		sp_col = Palette.MIST
	else:
		sp_text = "%s: ready (right-click / G)" % sp_label
	_text(Vector2(x, y + 10), sp_text, 12, sp_col)
	y += 18.0
	# Step 5: speed (world units per second, now / top speed), then boost,
	# flight assist off, the ACE bonus timer and an EMP stall warning.
	var spd := "Speed %d / %d" % [int(ship.velocity.length()), int(ship.f_max)]
	var boost := ""
	if ship.boosting:
		boost = "  ·  BOOST"
	elif ship.can_boost:
		boost = "  ·  Shift boost"
	var extra := ""
	if not ship.assist:
		extra += "  ·  Assist OFF (V)"
	if ship.ace_t > 0.0:
		extra += "  ·  ACE %ds" % int(ship.ace_t)
	if ship.emp_t > 0.0:
		extra += "  ·  ENGINES STALLED"
	_text(Vector2(x, y + 10), spd + boost + extra, 11, Palette.MIST)


## Draw one bar in rectangle `r`: a dark background, the filled part
## (`frac` = 0..1 of the width) in colour `col`, and a thin border.
func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Palette.INK)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Palette.LINE, false, 1.0)


## Draw text `t` at point `p` (its left end, on the text's baseline), size
## `sz` pixels, colour `col`. With `shadow`, a dark copy is drawn 1 pixel
## down-right first so it reads on top of a bar.
func _text(p: Vector2, t: String, sz: int, col: Color, shadow: bool = false) -> void:
	if shadow:
		draw_string(font, p + Vector2(1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Palette.VOID)
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
