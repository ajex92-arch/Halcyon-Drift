class_name CameraRig
extends Camera2D
## WHAT THIS IS: the camera. It decides which part of the map is on the
## screen and how far zoomed in it is (DESIGN.md A15, the "Camera" line).
##
## HOW IT WORKS: it has two modes.
##   - Free mode (pilots, admirals and spectators all start in it): the
##     camera stays where you put it, anywhere on the map. The mouse wheel
##     zooms; the move keys (W/A/S/D, also Q/E) pan when you are not flying
##     (while you fly they steer the ship); the screen edges pan; dragging
##     with the middle mouse button pulls the map; minimap clicks jump the
##     camera (look_at_point()). The Space key centers the camera on your
##     ship (with no ship, docked or dead, on the human's own mothership), and
##     holding it keeps the camera centered on the ship as it moves; let go
##     and the camera is free again from where it is. A pilot's camera also
##     jumps to the ship whenever it launches, so a new ship is never off
##     screen. How far you may zoom out depends on the seat: admirals and
##     spectators see the whole map; a pilot sees only a piece of it
##     (PILOT_VIEW_WIDTH: small craft see roughly their lane, capital ships
##     a bit more) and moves that piece around the map.
##   - Follow mode (only an Admiral who pressed C): the camera glides after
##     your ship and looks a little ahead, toward the mouse pointer and
##     where the ship is going. Holding the mouse at a screen edge "peeks" a
##     little further that way. The zoom-out limit is a pilot's. With no
##     ship (docked or dead), the camera looks at the human's own mothership.
## Every frame _process() works out where the camera wants to be and how
## far zoomed in, and slides part of the way there, so it moves smoothly.
##
## WHO USES IT: it is the "CameraRig" node in scenes/world/world.tscn.
## WorldSetup calls setup() and keeps it as World.camera. The minimap and
## the admiral board call look_at_point(); HudInput calls toggle_free()
## (the admiral's C key); ZoomMaxFeature asks zoom_limited(); the command
## overlay asks followed() and reads the zoom; Sfx reads the camera to make
## far-away sounds quieter; tests also move it.
##
## "Pixels" in this file are the game's own pixels, not the monitor's: the
## project stretches the whole picture to the window (project.godot, canvas
## items stretch, base size 1280 x 720), so the viewport size, the mouse
## position and the screen-edge distances below are all in the base pixels
## (a window twice as big draws each one as 2 x 2 real pixels). Because the
## zoom limits below are worked out from the viewport's width, how many
## world units fit across the screen never depended on the window size.
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
## How fast the free camera slides toward its goal (the k in 1 - exp(-k *
## dt)): about a quarter of a second to get there.
const FREE_SLIDE := 12.0

## The running match. Set by setup().
var world: World
## True in free mode (the camera stays where you put it; everybody starts
## here), false while an Admiral who pressed C has the camera follow their
## ship.
var free := true
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
## Did the human have a ship that was alive in the last frame? A change from
## no to yes is a launch (see _process()).
var _was_flying := false


## Get ready for match `w`. Everyone starts in free mode. Start 1800 world
## units in front of the human's mothership's spot (to the right of Aurelian's,
## to the left of Vhorr's; a spectator starts at Aurelian's), zoomed so 6000
## world units fit across the screen, and become the screen's camera.
func setup(w: World) -> void:
	world = w
	free = true
	# Step 1: the starting spot (also the free camera's goal): in front of the
	# human's own mothership, toward the middle of the map.
	var home: Vector2 = w.map.mothership_pos[w.human_team]
	var toward_middle := 1.0 if w.human_team == Rules.HALCYON else -1.0
	global_position = home + Vector2(1800.0 * toward_middle, 0)
	_free_pos = global_position
	# Step 2: the starting zoom. Godot's own smoothing is off because
	# _process() does its own; make_current() makes this the camera the
	# screen shows.
	target_zoom = _vw() / 6000.0
	zoom = Vector2(target_zoom, target_zoom)
	position_smoothing_enabled = false
	make_current()
	# --sim-only (Game.sim_only): nothing is drawn, so the camera never needs
	# to move: switch the per-frame work off.
	if Game.sim_only:
		set_process(false)


## The screen's width in pixels (the "viewport" is the area the game draws
## into).
func _vw() -> float:
	return get_viewport_rect().size.x


## The human's ship while it exists and is alive, otherwise null. Follow
## mode and the Space key (centering) look at it.
func followed() -> Ship:
	var h := world.human
	if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		return h.ship
	return null


## Is the zoom-out limit a pilot's (PILOT_VIEW_WIDTH by the ship's size)?
## True for a pilot in any mode, and for an Admiral who pressed C to follow
## their ship. A free Admiral camera and a spectator's may zoom out over the
## whole map.
func zoom_limited() -> bool:
	return not free or (world != null and world.human_role == "pilot")


## The allowed zoom range, as Vector2(most zoomed out, most zoomed in).
## Most zoomed in always shows MIN_VIEW_WIDTH (1100) world units across.
## Most zoomed out: the whole map width (MapLayout.W) plus 10% when the
## limit is not a pilot's; otherwise PILOT_VIEW_WIDTH for the followed
## ship's size (small when there is no ship), see zoom_limited().
func zoom_limits() -> Vector2:
	var vw := _vw()
	var min_z: float
	if not zoom_limited():
		min_z = vw / (MapLayout.W * 1.1)
	else:
		var s := followed()
		var size := s.size_class if s != null else Rules.SIZE_SMALL
		min_z = vw / (float(PILOT_VIEW_WIDTH[Rules.size_index(size)]) * ZoomMaxFeature.factor())
	return Vector2(min_z, vw / MIN_VIEW_WIDTH)


## Jump the free camera to world point `p` (minimap clicks, the admiral
## board, tests). It slides there over the next frames. Does nothing in
## follow mode (an Admiral who pressed C): that camera is on their ship.
func look_at_point(p: Vector2) -> void:
	if free:
		_free_pos = p


## Switch between free and follow mode. Only an admiral can; for anyone
## else (pilots too) this does nothing. The free camera starts from where
## the camera is now.
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


## Godot calls this on window events. When the game loses focus (Alt+Tab,
## the Windows key) during a middle drag, the button's release never comes
## here, so the drag ends now; otherwise every later mouse move would drag
## the map.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_drag = false


## Godot calls this every drawn frame. Update the zoom, then the position:
## in free mode slide toward the free goal (which the Space key, the edges,
## the move keys and the mouse move); in follow mode slide toward the ship
## (plus look-ahead and edge peek), or toward the mothership when there is
## no ship.
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
	# Step 2: a pilot's ship has just appeared (it launched): put the free
	# camera's goal on it, so a new ship is never off screen because the
	# camera was left somewhere else. An Admiral who launches keeps their
	# camera where it is (they are still commanding the map).
	var s := followed()
	if s != null and not _was_flying and world.human_role == "pilot":
		_free_pos = s.global_position
	_was_flying = s != null
	# Step 3: free mode: while Space is down the goal sits on the ship (or the
	# mothership); otherwise pan the goal. Then slide toward it.
	if free:
		if _centering():
			_free_pos = _center_goal(s)
		else:
			_free_pan(dt, view)
		global_position = global_position.lerp(_free_pos, 1.0 - exp(-FREE_SLIDE * dt))
		return
	# Step 4: follow mode with a ship: look toward the mouse (at most 12% of
	# the view width), a quarter of a second ahead of where the ship is
	# moving, plus the edge peek.
	var want: Vector2
	if s != null:
		var aim := (world.mouse_world() - s.global_position)
		var look := aim.limit_length(view.x * 0.12)
		want = s.global_position + look + s.velocity * 0.25
		_edge_peek(dt, view)
		want += peek
	else:
		# Step 5: no ship (docked or dead): look at the spot in front of the
		# human's mothership.
		want = _home_spot()
	# Step 6: slide toward that spot (k = 6).
	global_position = global_position.lerp(want, 1.0 - exp(-6.0 * dt))


## The spot the camera looks at when there is no ship (docked or dead): 900
## world units in front of the human's mothership (Aurelian's for a spectator),
## in the direction it faces. Where the camera already is if there is no
## mothership.
func _home_spot() -> Vector2:
	var ms := world.mothership(world.human_team)
	if ms == null or not is_instance_valid(ms):
		return global_position
	return ms.global_position + Vector2.from_angle(ms.rotation) * 900.0


## Is the Space key ("center_on_ship") down, or was it pressed this frame?
## A spectator has no ship to center on, so for them it is never.
func _centering() -> bool:
	if world.human == null:
		return false
	return Input.is_action_pressed("center_on_ship") or Input.is_action_just_pressed("center_on_ship")


## Where the free camera's goal goes while Space is down: on ship `s`, a
## little ahead of it by its speed / FREE_SLIDE, which is exactly how far
## the slide lags behind a moving goal, so a ship flying steadily stays in
## the middle of the screen. With no ship (`s` is null): the home spot.
func _center_goal(s: Ship) -> Vector2:
	if s != null:
		return s.global_position + s.velocity / FREE_SLIDE
	return _home_spot()


## Follow mode's edge peek. While the mouse is within 16 pixels of a screen
## edge, `peek` grows toward that edge by 60% of the view width per second,
## up to a quarter of the view each way. Away from the edges, or with the
## pointer outside the window, it slides back to zero (k = 3). `view` is the
## view size in world units.
func _edge_peek(dt: float, view: Vector2) -> void:
	# Step 1: which edges the mouse is at (-1, 0 or 1 across and up-down).
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport_rect().size
	var dir := Vector2.ZERO
	var m := 16.0
	if _pointer_inside(mp, vs):
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
## the game window is focused and the pointer is inside it). It moves at 80%
## of the view width per second and stays inside the map. `view` is the
## view size in world units.
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
	if get_window().has_focus() and _pointer_inside(mp, vs):
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


## Is the mouse pointer `mp` (screen pixels) inside the game's screen of size
## `vs`? On a desktop Godot reports the pointer even when it is outside the
## window (on a second monitor, or on the title bar), and such a position
## would count as "at the edge" and pan the camera without end.
func _pointer_inside(mp: Vector2, vs: Vector2) -> bool:
	return Rect2(Vector2.ZERO, vs).has_point(mp)
