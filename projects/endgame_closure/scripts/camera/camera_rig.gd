class_name CameraRig
extends Camera2D
## WHAT THIS IS: the camera. It decides which part of the map is on the
## screen and how far zoomed in it is (DESIGN.md A15, the "Camera" line).
##
## HOW IT WORKS: it has two modes.
##   - Follow mode (pilots): the camera glides after your ship and looks a
##     little ahead, toward the mouse pointer and where the ship is going.
##     You can only zoom out so far, and bigger ships may zoom out further
##     (PILOT_VIEW_WIDTH: small craft see roughly their lane, capital ships
##     a bit more). Holding the mouse at a screen edge "peeks" a little
##     further that way. With no ship (docked or dead), the camera looks at
##     the Halcyon mothership.
##   - Free mode (admirals and spectators): the camera goes anywhere at any
##     zoom. The mouse wheel zooms; the move keys (W/A/S/D, also Q/E) and
##     the screen edges pan when you are not flying; dragging with the
##     middle mouse button pulls the map; minimap clicks jump the camera
##     (look_at_point()).
## Every frame _process() works out where the camera wants to be and how
## far zoomed in, and slides part of the way there, so it moves smoothly.
##
## WHO USES IT: it is the "CameraRig" node in scenes/world/world.tscn.
## WorldSetup calls setup() and keeps it as World.camera. The minimap and
## the admiral board call look_at_point(); HudInput calls toggle_free()
## (the admiral's C key); the command overlay asks followed() and reads the
## zoom; Sfx reads the camera to make far-away sounds quieter; tests also
## move it.
##
## Words used here: "zoom" is how big things look. At zoom 1 one world unit
## is one pixel; a smaller zoom shows more of the map (zoomed out). So the
## visible world width = screen width in pixels / zoom. "lerp" means moving
## part of the way from one value to another. Using 1 - exp(-k * dt) as
## that part makes the slide equally smooth at any frame rate (a bigger k
## slides faster). `dt` is the time since the last frame, in seconds.

## How wide a piece of the world (in world units) a pilot sees when zoomed
## all the way out, by the followed ship's size class: small, medium,
## large, capital.
const PILOT_VIEW_WIDTH := [5200.0, 6400.0, 8000.0, 10000.0]
## The narrowest view anyone can zoom in to (world units across the
## screen).
const MIN_VIEW_WIDTH := 1100.0

## The running match. Set by setup().
var world: World
## True in free mode (admirals and spectators), false while following the
## human's ship.
var free := false
## The zoom the camera is sliding toward; the wheel and the zoom keys
## change it. 0.25 is only a starting value until setup() runs.
var target_zoom := 0.25
## The edge peek: how far (world units) the view is pushed toward the
## screen edge the mouse is at. Only used in follow mode.
var peek := Vector2.ZERO
## True while the middle mouse button is dragging the free camera.
var _drag := false
## Where the mouse was (screen pixels) at the last drag step.
var _drag_last := Vector2.ZERO
## Where the free camera wants to be (world units); the camera slides
## toward it.
var _free_pos := Vector2.ZERO


## Get ready for match `w`. Free mode for anyone who is not a pilot. Start
## 1800 world units to the right of the Halcyon mothership's spot, zoomed
## so 6000 world units fit across the screen, and become the screen's
## camera.
func setup(w: World) -> void:
	world = w
	free = w.human_role != "pilot"
	# Step 1: the starting spot (also the free camera's goal).
	var home: Vector2 = w.map.mothership_pos[Rules.HALCYON]
	global_position = home + Vector2(1800, 0)
	_free_pos = global_position
	# Step 2: the starting zoom. Godot's own smoothing is off because
	# _process() does its own; make_current() makes this the camera the
	# screen shows.
	target_zoom = _vw() / 6000.0
	zoom = Vector2(target_zoom, target_zoom)
	position_smoothing_enabled = false
	make_current()


## The screen's width in pixels (the "viewport" is the area the game draws
## into).
func _vw() -> float:
	return get_viewport_rect().size.x


## The ship the camera follows: the human's ship while it exists and is
## alive, otherwise null.
func followed() -> Ship:
	var h := world.human
	if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		return h.ship
	return null


## The allowed zoom range, as Vector2(most zoomed out, most zoomed in).
## Most zoomed in always shows MIN_VIEW_WIDTH (1100) world units across.
## Most zoomed out: in free mode, the whole map width (MapLayout.W) plus
## 10%; in follow mode, PILOT_VIEW_WIDTH for the followed ship's size
## (small when there is no ship).
func zoom_limits() -> Vector2:
	var vw := _vw()
	var min_z: float
	if free:
		min_z = vw / (MapLayout.W * 1.1)
	else:
		var s := followed()
		var size := s.size_class if s != null else Rules.SIZE_SMALL
		min_z = vw / float(PILOT_VIEW_WIDTH[Rules.size_index(size)])
	return Vector2(min_z, vw / MIN_VIEW_WIDTH)


## Jump the free camera to world point `p` (minimap clicks, the admiral
## board, tests). It slides there over the next frames. Does nothing in
## follow mode: pilots can't move their camera away.
func look_at_point(p: Vector2) -> void:
	if free:
		_free_pos = p


## Switch between free and follow mode. Only an admiral can; for anyone
## else this does nothing. The free camera starts from where the camera is
## now.
func toggle_free() -> void:
	if world.human_role == "admiral":
		free = not free
		_free_pos = global_position


## Godot sends here the mouse input that no screen used. The wheel zooms
## (in any mode; each notch is 12%). The middle button drags the free
## camera: moving the mouse pulls the map along with the pointer.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Wheel up zooms in, wheel down zooms out; the middle button starts
		# a drag (only in free mode) and letting go ends it.
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom *= 1.12
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom /= 1.12
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed and free
			_drag_last = mb.position
	elif event is InputEventMouseMotion and _drag:
		# Dragging: move the goal the opposite way to the mouse, turning
		# screen pixels into world units (divide by the zoom).
		var mm := event as InputEventMouseMotion
		_free_pos -= (mm.position - _drag_last) / zoom.x
		_drag_last = mm.position


## Godot calls this every drawn frame. Update the zoom, then the position:
## in free mode slide toward the free goal; in follow mode slide toward
## the ship (plus look-ahead and edge peek), or toward the mothership when
## there is no ship.
func _process(dt: float) -> void:
	if world == null:
		return
	# Step 1: the zoom keys change the goal smoothly while held (by
	# 1.5 x dt per frame); keep it inside the allowed range, then slide the
	# real zoom toward it (k = 10).
	if Input.is_action_pressed("zoom_in"):
		target_zoom *= 1.0 + 1.5 * dt
	if Input.is_action_pressed("zoom_out"):
		target_zoom /= 1.0 + 1.5 * dt
	var lim := zoom_limits()
	target_zoom = clampf(target_zoom, lim.x, lim.y)
	var z := lerpf(zoom.x, target_zoom, 1.0 - exp(-10.0 * dt))
	zoom = Vector2(z, z)
	# `view` is how much of the world fits on the screen (world units).
	var view := get_viewport_rect().size / z
	# Step 2: free mode: pan the goal, then slide toward it (k = 12).
	if free:
		_free_pan(dt, view)
		global_position = global_position.lerp(_free_pos, 1.0 - exp(-12.0 * dt))
		return
	# Step 3: follow mode with a ship: look toward the mouse (at most 12% of
	# the view width), a quarter of a second ahead of where the ship is
	# moving, plus the edge peek.
	var s := followed()
	var want: Vector2
	if s != null:
		var aim := (world.mouse_world() - s.global_position)
		var look := aim.limit_length(view.x * 0.12)
		want = s.global_position + look + s.velocity * 0.25
		_edge_peek(dt, view)
		want += peek
	else:
		# Step 4: no ship (docked or dead): look at a spot 900 world units
		# in front of the Halcyon mothership (in the direction it faces).
		var ms := world.mothership(Rules.HALCYON)
		want = ms.global_position + Vector2.from_angle(ms.rotation) * 900.0
	# Step 5: slide toward that spot (k = 6).
	global_position = global_position.lerp(want, 1.0 - exp(-6.0 * dt))


## Follow mode's edge peek. While the mouse is within 16 pixels of a screen
## edge, `peek` grows toward that edge by 60% of the view width per second,
## up to a quarter of the view each way. Away from the edges it slides back
## to zero (k = 3). `view` is the view size in world units.
func _edge_peek(dt: float, view: Vector2) -> void:
	# Step 1: which edges the mouse is at (-1, 0 or 1 across and up-down).
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport_rect().size
	var dir := Vector2.ZERO
	var m := 16.0
	if mp.x < m:
		dir.x = -1.0
	elif mp.x > vs.x - m:
		dir.x = 1.0
	if mp.y < m:
		dir.y = -1.0
	elif mp.y > vs.y - m:
		dir.y = 1.0
	# Step 2: no edge: ease back to the centre. An edge: push that way,
	# but never past a quarter of the view.
	var max_peek := view * 0.25
	if dir == Vector2.ZERO:
		peek = peek.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * dt))
	else:
		peek += dir * view.x * 0.6 * dt
		peek = Vector2(clampf(peek.x, -max_peek.x, max_peek.x), clampf(peek.y, -max_peek.y, max_peek.y))


## Free mode's panning: move the free camera's goal with the move keys
## (only when the human is not flying, because then those keys fly the
## ship) and with the mouse at a screen edge (within 6 pixels, only while
## the game window is focused). It moves at 80% of the view width per
## second and stays inside the map. `view` is the view size in world units.
func _free_pan(dt: float, view: Vector2) -> void:
	# Step 1: the move keys (D/E right, A/Q left, S down, W up).
	var flying := followed() != null
	var dir := Vector2.ZERO
	if not flying:
		dir.x = Input.get_action_strength("strafe_right") - Input.get_action_strength("strafe_left")
		dir.y = Input.get_action_strength("thrust_back") - Input.get_action_strength("thrust_forward")
	# Step 2: the screen edges; they win over the keys on their own axis.
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport_rect().size
	if get_window().has_focus():
		if mp.x < 6.0:
			dir.x = -1.0
		elif mp.x > vs.x - 6.0:
			dir.x = 1.0
		if mp.y < 6.0:
			dir.y = -1.0
		elif mp.y > vs.y - 6.0:
			dir.y = 1.0
	# Step 3: move the goal, and keep it inside the map
	# (0..MapLayout.W across, 0..MapLayout.H down).
	_free_pos += dir * view.x * 0.8 * dt
	_free_pos = Vector2(clampf(_free_pos.x, 0.0, MapLayout.W), clampf(_free_pos.y, 0.0, MapLayout.H))
