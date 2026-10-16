class_name Minimap
extends Control
## WHAT THIS IS: a small map of the whole battlefield in the bottom-right
## corner of the HUD. DESIGN.md A15.
##
## HOW IT WORKS: 10 times a second it redraws itself, layer by layer:
## lanes and the crossing, derelict camps (once explored), resource nodes
## coloured by who holds them (with a dot per turret), the fog of war (the
## dark cover over places our team can't see: FogView's picture), the
## motherships, every unit our team can see right now, our own ship (ring
## and nose line), the rally waypoint and a box for what the camera shows.
## The whole 40,000 x 26,000 world is shrunk to 300 pixels wide: k is that
## shrink factor (map pixels per world unit, 300 / 40,000 = 0.0075).
## Clicks: the Admiral and spectators left-click (or drag) to move the
## camera there; with an Admiral map tool armed, a left click places it
## there instead (CommandOverlay.apply_at). A right click gives selected
## Fleet Command minions a move order (CommandOverlay.order_at).
##
## WHO USES IT: Hud makes it from scenes/ui/minimap.tscn and calls
## setup(world, overlay). It reads World, MapInfo (world.map), Vision
## (what each team has explored) and CameraRig.

## Width of the minimap (pixels). Its height keeps the world's shape.
const MAP_W := 300.0

## The game world (set by setup()).
var world: World
## The Admiral's map tools, so a click can place an armed tool.
var overlay: CommandOverlay = null
## Shrink factor: minimap pixels per world unit (MAP_W / MapLayout.W).
var k := 1.0
## Seconds until the next redraw (counts down from 0.1).
var _t := 0.0
## The fog-of-war picture from the world's FogView, or null if the fog is
## not shown.
var _fog_tex: Texture2D = null
## True while the left mouse button is held after a camera click, so
## dragging keeps moving the camera.
var _drag := false


## Called once when the node joins the scene: take mouse clicks, and size
## ourselves to MAP_W wide with the world's shape.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	k = MAP_W / MapLayout.W
	custom_minimum_size = Vector2(MAP_W, MapLayout.H * k)
	tooltip_text = ""


## Remember the world and the map-tool layer, and borrow the fog picture
## from the world's "FogView" node (only if it is showing).
func setup(w: World, ov: CommandOverlay) -> void:
	world = w
	overlay = ov
	var fog := w.get_node_or_null("FogView") as Sprite2D
	if fog != null and fog.visible:
		_fog_tex = fog.texture


## Every frame: redraw every 0.1 seconds while we are on screen
## (queue_redraw makes Godot call _draw() again).
func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0.0 and is_visible_in_tree():
		_t = 0.1
		queue_redraw()


## A world position -> the same spot on the minimap (pixels).
func to_map(p: Vector2) -> Vector2:
	return p * k


## A minimap spot (pixels) -> the world position, kept inside the world.
func to_world(m: Vector2) -> Vector2:
	return Vector2(clampf(m.x / k, 0.0, MapLayout.W), clampf(m.y / k, 0.0, MapLayout.H))


## Mouse input on the minimap (see "Clicks" in HOW IT WORKS).
func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			# A left or right press: the click is ours (not the game's).
			accept_event()
			var p := to_world(mb.position)
			# Left: place the armed map tool, or move the camera and start
			# a drag. (CameraRig.look_at_point only moves a free camera,
			# so a pilot's camera stays on their ship.)
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if overlay != null and overlay.tool != "":
					overlay.apply_at(p)
				else:
					world.camera.look_at_point(p)
					_drag = true
			# Right: a move order for the selected minions (or cancel a tool).
			elif overlay != null:
				overlay.order_at(p)
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = false
	elif event is InputEventMouseMotion and _drag:
		world.camera.look_at_point(to_world((event as InputEventMouseMotion).position))


## Draw the minimap, bottom layer first (see HOW IT WORKS). vt is the team
## we see as (-1 = a spectator who sees everything).
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Palette.with_alpha(Palette.VOID, 0.92))
	if world == null:
		return
	var vt := world.viewer_team
	# Lanes and the crossing, drawn as lines as wide as the real lanes
	# (a lane's half-width defaults to 1,800 world units).
	for id: String in world.map.lanes:
		var pts: PackedVector2Array = world.map.lanes[id]
		var half: float = float(world.map.lane_half.get(id, 1800.0))
		_poly(pts, Palette.with_alpha(Palette.LANE, 0.55), half * 2.0 * k)
	_poly(world.map.connector, Palette.with_alpha(Palette.LANE, 0.45), world.map.connector_half * 2.0 * k)
	# Derelict camps, once our team has explored their spot.
	for c: Dictionary in world.map.camps:
		var cp: Vector2 = c["pos"]
		if vt < 0 or world.vision.is_explored(vt, cp):
			var m := to_map(cp)
			draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), Palette.with_alpha(Palette.DERELICT, 0.7), false, 1.0)
	# Resource nodes: a ring in the holder's colour (grey when nobody holds
	# it, or when it is the enemy's and we haven't explored it), with one
	# small square per turret under it.
	for n: ResourceNode in world.nodes:
		var holder := n.owner_team()
		var col := Palette.NEUTRAL
		if holder >= 0 and (holder == vt or vt < 0 or world.vision.is_explored(vt, n.global_position)):
			col = Palette.team(holder)
		var m := to_map(n.global_position)
		draw_arc(m, 5.0, 0.0, TAU, 16, col, 1.5, true)
		var nt := maxi(n.turret_count(0), n.turret_count(1))
		for i in nt:
			draw_rect(Rect2(m + Vector2(-4.0 + float(i) * 3.5, 7.0), Vector2(2.5, 2.5)), col)
	# The fog of war, stretched over the whole minimap (not for spectators).
	if _fog_tex != null and vt >= 0:
		draw_texture_rect(_fog_tex, rect, false)
	# Motherships: a thick line along each hull (faded once destroyed).
	for ms: Mothership in world.motherships:
		if ms == null:
			continue
		var f := Vector2.from_angle(ms.rotation) * ms.half_len
		var col := Palette.team(ms.team)
		if not ms.alive:
			col = Palette.with_alpha(col, 0.3)
		draw_line(to_map(ms.global_position - f), to_map(ms.global_position + f), col, maxf(3.0, ms.beam * k), true)
	_draw_units(vt)
	_draw_feature_marks(vt)
	# The rally waypoint: an amber ring as big as its real area.
	if vt >= 0 and world.teams[vt].has_waypoint():
		var wp := to_map(world.teams[vt].waypoint)
		draw_arc(wp, Rules.WAYPOINT_RADIUS * k, 0.0, TAU, 20, Palette.AMBER, 1.2, true)
	# The camera's view: the part of the world the screen shows right now
	# (window size / zoom), cut to the minimap's edges. Then a border.
	var cam := world.camera
	var view := get_viewport_rect().size / cam.zoom.x
	var cr := Rect2(to_map(cam.global_position - view * 0.5), view * k)
	draw_rect(cr.intersection(rect), Palette.with_alpha(Palette.ICE, 0.7), false, 1.0)
	draw_rect(rect, Palette.LINE, false, 1.0)


## Draw every live unit our team (`vt`) can see, as a small mark in its
## team colour (a different shape per kind), then our own ship on top.
## Enemy structures we saw once stay drawn even when out of sight now
## (seen_mask is a row of on/off switches, one per team: bit 1 << vt is on
## once team vt has seen it).
func _draw_units(vt: int) -> void:
	var me: Ship = null
	if world.human != null and world.human.ship != null and is_instance_valid(world.human.ship):
		me = world.human.ship
	for u: Unit in world.units:
		if not u.alive or u.kind == Unit.K_MOTHERSHIP:
			continue
		# Skip enemies we can't see now (except structures seen before).
		if vt >= 0 and u.team != vt and not u.visible_to(vt):
			if not (u.is_structure() and (u.seen_mask & (1 << vt)) != 0):
				continue
		# A feature module may black a contact out (the beacons variant).
		if not world.features.is_empty() and _feature_hides(u, vt):
			continue
		var m := to_map(u.global_position)
		var col := Palette.team(u.team)
		match u.kind:
			# Ships: a dot that is bigger for bigger ship sizes.
			Unit.K_SHIP:
				var r := 2.2 + float(Rules.size_index(u.size_class)) * 0.8
				draw_circle(m, r, col)
			Unit.K_MINION:
				draw_rect(Rect2(m - Vector2(0.75, 0.75), Vector2(1.5, 1.5)), Palette.with_alpha(col, 0.85))
			Unit.K_TURRET:
				draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), col)
				draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), Palette.VOID, false, 1.0)
			Unit.K_BAY:
				draw_rect(Rect2(m - Vector2(3, 3), Vector2(6, 6)), Palette.REPAIR, false, 1.5)
			Unit.K_WARD:
				draw_circle(m, 1.5, Palette.VEIL)
			Unit.K_MINING_DRONE:
				draw_circle(m, 1.0, Palette.with_alpha(Palette.ORE, 0.9))
			Unit.K_MONSTER, Unit.K_SNUB:
				draw_circle(m, 1.6, Palette.DERELICT)
	# Our own ship: a white ring with a line showing where its nose points.
	if me != null and me.alive:
		var m := to_map(me.global_position)
		draw_arc(m, 5.0, 0.0, TAU, 16, Palette.ICE, 1.5, true)
		draw_line(m, m + Vector2.from_angle(me.rotation) * 8.0, Palette.ICE, 1.5, true)


## Feature hook: does a feature module black unit `u` out of the minimap
## for the team `vt` we see as? Asks every feature in World.features that
## has minimap_hides(u, vt) -> bool (BeaconsFeature, during a blackout).
func _feature_hides(u: Unit, vt: int) -> bool:
	for f: Object in world.features.values():
		if f.has_method("minimap_hides") and f.call("minimap_hides", u, vt):
			return true
	return false


## Feature hook: draw the marks of the feature modules that have
## minimap_marks(vt) -> Array of {pos, color, shape ("ring" or "diamond"),
## r}: the Dreadnought and the salvage beacons.
func _draw_feature_marks(vt: int) -> void:
	if world.features.is_empty():
		return
	for f: Object in world.features.values():
		if not f.has_method("minimap_marks"):
			continue
		for mk: Dictionary in f.call("minimap_marks", vt):
			var m := to_map(mk["pos"])
			var col: Color = mk["color"]
			var r := float(mk.get("r", 4.0))
			if str(mk.get("shape", "ring")) == "diamond":
				draw_colored_polygon(PackedVector2Array([m + Vector2(0, -r), m + Vector2(r, 0), m + Vector2(0, r), m + Vector2(-r, 0)]), col)
			else:
				draw_arc(m, r, 0.0, TAU, 16, col, 1.5, true)


## Draw the line through world points `pts` on the minimap, `width` pixels
## wide (nothing for fewer than 2 points).
func _poly(pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var out := PackedVector2Array()
	for p in pts:
		out.append(to_map(p))
	draw_polyline(out, col, width, true)
