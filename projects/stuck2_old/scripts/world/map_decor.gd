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
## redraw this node. The labels are written in world units, so close up they
## would grow to hundreds of screen pixels; they are therefore never drawn
## taller than LABEL_MAX_PX on the screen. They are drawn on a child node of
## their own (_names), because drawing the stars, bands and lines again takes
## far longer than a frame can spare: _process() reads the camera's zoom each
## frame, works out the size the labels may have, and asks the child for a
## redraw only when that size changes (never while the camera is zoomed out,
## where the labels keep their full world size).
##
## WHO USES IT: the World scene has one, the "MapDecor" node; WorldSetup
## calls setup(). It reads World.map (lanes, connector, motherships) and
## World.nodes (each ore node's position and name), and the camera's zoom.

## The tallest a label is drawn on the screen, in the game's own pixels (the
## pixels every `px` in the painters counts: the window is stretched from a
## 1280 x 720 picture). Zoomed out the labels are smaller than this and keep
## their world size.
const LABEL_MAX_PX := 60.0
## The font size of a lane label at full size, in world units.
const LANE_LABEL_SIZE := 180
## Where a lane label's text box starts, from the spot on the lane it names
## (world units, at full size): the box is LANE_LABEL_BOX wide and the text is
## centred in it, so the label is centred on that spot.
const LANE_LABEL_OFFSET := Vector2(-900, -260)
## The width of a lane label's text box at full size, in world units.
const LANE_LABEL_BOX := 1800.0
## The font size of an ore node's label at full size, in world units.
const NODE_LABEL_SIZE := 150
## Where an ore node's label box starts, from the node's middle (world units,
## at full size): just above the node's rim.
const NODE_LABEL_OFFSET := Vector2(-1000, -MapLayout.NODE_RADIUS - 220)
## The width of an ore node's label box at full size, in world units.
const NODE_LABEL_BOX := 2000.0
## About how far above its baseline the middle of a capital letter is, as a
## fraction of the font size. A smaller label moves its baseline so that this
## middle stays where it is at full size.
const LABEL_CAP_MID := 0.36

## The world we draw the map of (null until setup()).
var world: World
## The stars: x and y position (world units) and size (1 to 4; a star is
## drawn with a radius of 6 times its size).
var stars := PackedVector3Array()
## The font size, in world units, the lane labels were last drawn at.
var _lane_size := LANE_LABEL_SIZE
## The font size, in world units, the node labels were last drawn at.
var _node_size := NODE_LABEL_SIZE
## The child node the lane and node names are drawn on (made by setup(); null
## with --sim-only). It draws on top of this node's own picture, so the names
## look as if they were part of it, but a new label size redraws only this
## node.
var _names: Node2D


## Remember the world, scatter 1,400 stars over the whole map, make the child
## node the names are drawn on, and ask Godot to draw. z_index -10 puts this
## under everything else. With --sim-only (Game.sim_only) nothing is drawn, so
## we make no stars and no child, hide ourselves and stop the per-frame label
## check.
func setup(w: World) -> void:
	world = w
	if Game.sim_only:
		visible = false
		set_process(false)
		return
	z_index = -10
	var rng := Mulberry.new(99)
	# Three random numbers per star: x, then y, then size.
	for i in 1400:
		stars.append(Vector3(rng.next() * MapLayout.W, rng.next() * MapLayout.H, 1.0 + rng.next() * 3.0))
	# The names: a child node that draws them through _draw_names().
	_names = Node2D.new()
	add_child(_names)
	_names.draw.connect(_draw_names)
	_names.queue_redraw()
	queue_redraw()


## Every frame: work out how big the labels may be at the camera's zoom (the
## font size, in world units, that is LABEL_MAX_PX tall on the screen, or the
## full size when that is smaller) and draw the names again only if it
## changed. Zoomed out nothing changes, so no redraw is asked for.
func _process(_dt: float) -> void:
	if world == null or _names == null:
		return
	# Step 1: the zoom. With no camera, one world unit is one pixel.
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	# Step 2: the font size that is LABEL_MAX_PX tall on the screen, at least 1.
	var cap := maxi(1, roundi(LABEL_MAX_PX / maxf(0.02, z)))
	# Step 3: each kind of label keeps its full size unless the cap is smaller.
	var lane := mini(LANE_LABEL_SIZE, cap)
	var node := mini(NODE_LABEL_SIZE, cap)
	if lane != _lane_size or node != _node_size:
		_lane_size = lane
		_node_size = node
		_names.queue_redraw()


## Draw the whole background, apart from the names (nothing before setup()).
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


## Draw the lane and node names on the `_names` child (Godot calls this when
## that node draws, through its `draw` signal; nothing before setup()).
func _draw_names() -> void:
	if world == null:
		return
	# Lane names, a third of the way along each lane (32%), in capitals. Each
	# label is drawn at _lane_size (full size, or smaller close up).
	var font := ThemeDB.fallback_font
	var lane_k := float(_lane_size) / float(LANE_LABEL_SIZE)
	for id: String in world.map.lanes:
		var pts: PackedVector2Array = world.map.lanes[id]
		var mid := Util.polyline_at(pts, Util.polyline_length(pts) * 0.32)
		var at := mid + _label_shift(LANE_LABEL_OFFSET, LANE_LABEL_SIZE, _lane_size)
		_names.draw_string(font, at, str(MapLayout.LANES[id]["label"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, LANE_LABEL_BOX * lane_k, _lane_size, Palette.with_alpha(Palette.MIST, 0.35))
	# Ore node names, just above each node, at _node_size.
	var node_k := float(_node_size) / float(NODE_LABEL_SIZE)
	for n in world.nodes:
		var at := n.global_position + _label_shift(NODE_LABEL_OFFSET, NODE_LABEL_SIZE, _node_size)
		_names.draw_string(font, at, Rules.display_label(n.node_name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, NODE_LABEL_BOX * node_k, _node_size, Palette.with_alpha(Palette.ORE, 0.34))


## Where a label drawn at font size `size` starts, from its spot, when its
## full-size start (box corner and baseline) is `offset` at font size `full`.
## The sideways part shrinks with the letters, so the box stays centred on the
## spot; the baseline moves so that the middle of the capital letters stays
## where it is at full size (LABEL_CAP_MID). At full size this is `offset`.
func _label_shift(offset: Vector2, full: int, size: int) -> Vector2:
	var k := float(size) / float(full)
	return Vector2(offset.x * k, offset.y - LABEL_CAP_MID * float(full - size))


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
