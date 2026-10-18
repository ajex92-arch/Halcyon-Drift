class_name CommandOverlayDraw
extends RefCounted
## WHAT THIS IS: the drawing half of CommandOverlay (the Admiral's map
## tools): what those tools paint on the map.
##
## HOW IT WORKS: CommandOverlay._draw() calls draw(overlay) every frame.
## It paints, in this order:
##   1. for everyone on a team: the rally waypoint (a ring, a cross and
##      "Rally point (Ns)" with the seconds it has left);
##   2. for the Admiral only: our repair bays' healing range, a ring
##      around each selected minion, and the box being dragged;
##   3. while a tool is armed: a preview at the mouse, a ring as big as
##      what the tool covers, green (repair colour) where it is allowed
##      and red where it isn't, with the reason or the instruction.
## Everything is drawn in world positions. To keep lines and text the same
## size on screen whatever the camera zoom, sizes are multiplied by `px`:
## how many world units one screen pixel covers right now (1 / zoom).
## This is a "static library": plain functions with no state of their own.
## As a part of CommandOverlay it reads the overlay's own fields directly.
##
## WHO USES IT: only CommandOverlay._draw().


## Draw everything (see HOW IT WORKS). The draw_* calls go to `ov`, the
## overlay being drawn.
static func draw(ov: CommandOverlay) -> void:
	var world := ov.world
	if world == null:
		return
	var z := world.camera.zoom.x
	var px := 1.0 / maxf(0.0001, z)
	var vt := world.viewer_team
	# 1. The team waypoint (everyone on the team sees it).
	if vt >= 0 and world.teams[vt].has_waypoint():
		_draw_waypoint(ov, vt, px)
	# 1b. The marks that feature modules add (Barrage circle, bounty
	# diamonds, Fortify shimmer ...); nothing in today's game.
	if not world.command.marks.is_empty():
		CommandOrders.draw_marks(ov, vt, px)
	if not ov.is_admiral():
		return
	# 2. The Admiral's own marks.
	_draw_admiral_marks(ov, px)
	if ov.tool == "":
		return
	# 3. The armed tool's preview at the mouse.
	_draw_tool_preview(ov, px)


## The rally waypoint of team `vt`: a faint ring as big as its area, an
## amber cross 120 world units wide, and its label with the seconds left.
static func _draw_waypoint(ov: CommandOverlay, vt: int, px: float) -> void:
	var world := ov.world
	var wp := world.teams[vt].waypoint
	ov.draw_arc(wp, Rules.WAYPOINT_RADIUS, 0.0, TAU, 64, Palette.with_alpha(Palette.AMBER, 0.55), 2.0 * px, true)
	ov.draw_line(wp + Vector2(-60, 0), wp + Vector2(60, 0), Palette.AMBER, 2.0 * px)
	ov.draw_line(wp + Vector2(0, -60), wp + Vector2(0, 60), Palette.AMBER, 2.0 * px)
	_label(ov, wp + Vector2(0, -Rules.WAYPOINT_RADIUS - 30.0 * px), "Rally point (%ds)" % int(world.teams[vt].waypoint_until - world.time), Palette.AMBER, px)


## The Admiral's marks: our live repair bays' healing range (so the
## Admiral can plan where ships get healed), a ring around each selected
## minion, and the box-select rectangle while dragging.
static func _draw_admiral_marks(ov: CommandOverlay, px: float) -> void:
	var world := ov.world
	for b: RepairBay in world.bays:
		if b.team == ov.team and b.alive:
			ov.draw_arc(b.global_position, float(Structures.REPAIR_BAY["range"]), 0.0, TAU, 48, Palette.with_alpha(Palette.REPAIR, 0.25), 1.5 * px, true)
	# Selected minions (this also tidies the selection list).
	for m in ov._live_selection():
		ov.draw_arc(m.global_position, m.radius + 14.0, 0.0, TAU, 12, Palette.ICE, 1.5 * px, true)
	# The drag box: a faint fill and an outline.
	if ov._drag_from != Vector2.INF:
		var r := Rect2(ov._drag_from, Vector2.ZERO).expand(ov._drag_to)
		ov.draw_rect(r, Palette.with_alpha(Palette.ICE, 0.08))
		ov.draw_rect(r, Palette.ICE, false, 1.5 * px)


## The armed tool's preview at the mouse: a ring as big as the area the
## tool covers (default 300 world units), a dot, and a label: the reason
## it can't go here (red), or the tool's instruction (green).
static func _draw_tool_preview(ov: CommandOverlay, px: float) -> void:
	var world := ov.world
	var p := ov.get_global_mouse_position()
	var b := ov.blocker_at(p)
	var col := Palette.REPAIR if b == "" else Palette.CINDER
	# The ring's size: a bay's healing range, a ward's sight (40% more
	# with the ward upgrade), the waypoint's area, or half the mothership.
	var rad := 300.0
	match ov.tool:
		"bay":
			rad = float(Structures.REPAIR_BAY["range"])
		"ward":
			rad = float(Structures.WARD["vision"]) * (1.4 if world.teams[ov.team].ward_upgrade else 1.0)
		"waypoint":
			rad = Rules.WAYPOINT_RADIUS
		"move":
			rad = float(Structures.MOTHERSHIP["length"]) * 0.5
		_:
			# An order that a feature module added (CommandOrders).
			rad = CommandOrders.radius(world, ov.tool)
	ov.draw_arc(p, rad, 0.0, TAU, 64, Palette.with_alpha(col, 0.8), 2.0 * px, true)
	ov.draw_circle(p, 6.0 * px, col)
	_label(ov, p + Vector2(0, 26.0 * px), b if b != "" else ov.tool_text(), col, px)


## Draw text `t` centred on world point `p`, in colour `col` with a dark
## shadow 1 pixel down-right. The text is scaled by `px` so it is always
## 14 screen pixels tall, whatever the zoom; draw_set_transform moves and
## scales everything drawn after it, so we reset it at the end.
static func _label(ov: CommandOverlay, p: Vector2, t: String, col: Color, px: float) -> void:
	ov.draw_set_transform(p, 0.0, Vector2(px, px))
	var w := ov._font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	ov.draw_string(ov._font, Vector2(-w * 0.5 + 1.0, 1.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.VOID)
	ov.draw_string(ov._font, Vector2(-w * 0.5, 0.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	ov.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
