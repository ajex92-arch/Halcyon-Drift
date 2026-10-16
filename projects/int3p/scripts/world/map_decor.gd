class_name MapDecor
extends Node2D
## WHAT THIS IS: the background picture of the map, under everything else:
## a starfield, faint bands showing the lane corridors with dashed centre
## lines, the base clearings around the motherships, and big labels for
## the lanes and the ore nodes. It is only decoration: it changes nothing
## in the game.
##
## HOW IT WORKS: setup() scatters the stars once (with its own random
## number maker, Mulberry seeded 99, so the sky is the same every match and
## no other random numbers are disturbed) and asks Godot to draw. Godot
## remembers the drawing, so _draw() runs again only when Godot is asked to
## redraw this node.
##
## WHO USES IT: the World scene has one, the "MapDecor" node; WorldSetup
## calls setup(). It reads World.map (lanes, connector, motherships) and
## World.nodes (each ore node's position and name).

## The world we draw the map of (null until setup()).
var world: World
## The stars: x and y position (world units) and size (1 to 4; a star is
## drawn with a radius of 6 times its size).
var stars := PackedVector3Array()


## Remember the world, scatter 1,400 stars over the whole map, and ask
## Godot to draw. z_index -10 puts this under everything else. With
## --sim-only (Game.sim_only) nothing is drawn, so we make no stars and hide
## ourselves.
func setup(w: World) -> void:
	world = w
	if Game.sim_only:
		visible = false
		return
	z_index = -10
	var rng := Mulberry.new(99)
	# Three random numbers per star: x, then y, then size.
	for i in 1400:
		stars.append(Vector3(rng.next() * MapLayout.W, rng.next() * MapLayout.H, 1.0 + rng.next() * 3.0))
	queue_redraw()


## Draw the whole background (nothing before setup()).
func _draw() -> void:
	if world == null:
		return
	# A faint dark wash over the map, then the stars.
	draw_rect(Rect2(0, 0, MapLayout.W, MapLayout.H), Palette.with_alpha(Palette.INK, 0.25))
	for s: Vector3 in stars:
		draw_circle(Vector2(s.x, s.y), s.z * 6.0, Palette.with_alpha(Palette.ICE, 0.25))
	# The lane corridors (10% see-through colour) with dashed centre lines,
	# then the connector the same way.
	var lane_fill := Palette.with_alpha(Palette.LANE, 0.10)
	var guide := Palette.with_alpha(Palette.LANE, 0.55)
	for id: String in world.map.lanes:
		var pts: PackedVector2Array = world.map.lanes[id]
		var half: float = world.map.lane_half[id]
		_band(pts, half, lane_fill)
		_dashed(pts, guide, 26.0)
	_band(world.map.connector, world.map.connector_half, lane_fill)
	_dashed(world.map.connector, guide, 20.0)
	# Each team's base clearing: a very faint disc in the team colour with
	# a ring around it.
	for t in 2:
		var mp: Vector2 = world.map.mothership_pos[t]
		draw_circle(mp, MapLayout.BASE_CLEAR_RADIUS, Palette.with_alpha(Palette.team(t), 0.025))
		draw_arc(mp, MapLayout.BASE_CLEAR_RADIUS, 0.0, TAU, 128, Palette.with_alpha(Palette.team(t), 0.18), 14.0, true)
	# Lane names, a third of the way along each lane (32%), in capitals.
	var font := ThemeDB.fallback_font
	for id: String in world.map.lanes:
		var pts: PackedVector2Array = world.map.lanes[id]
		var mid := Util.polyline_at(pts, Util.polyline_length(pts) * 0.32)
		draw_string(font, mid + Vector2(-900, -260), str(MapLayout.LANES[id]["label"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 1800, 180, Palette.with_alpha(Palette.MIST, 0.35))
	# Ore node names, just above each node.
	for n in world.nodes:
		draw_string(font, n.global_position + Vector2(-1000, -MapLayout.NODE_RADIUS - 220), n.node_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 2000, 150, Palette.with_alpha(Palette.ORE, 0.34))


## Draw a corridor as a filled band `half` wide on each side of its centre
## line `pts`: a rectangle along every piece of the line, plus a circle at
## every point so the joins and ends are rounded.
func _band(pts: PackedVector2Array, half: float, col: Color) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := (b - a).normalized().orthogonal() * half
		draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), col)
		draw_circle(a, half, col)
	draw_circle(pts[pts.size() - 1], half, col)


## Draw a dashed line `width` wide along every piece of `pts` (dashes 400
## world units long).
func _dashed(pts: PackedVector2Array, col: Color, width: float) -> void:
	for i in pts.size() - 1:
		draw_dashed_line(pts[i], pts[i + 1], col, width, 400.0)
