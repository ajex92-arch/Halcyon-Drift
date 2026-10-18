extends Node
## WHAT THIS IS: the camera check. It presses Space and moves the mouse the
## way a player does (through Godot's own input events) and checks what the
## camera does (DESIGN.md A15, the "Camera" line):
##   - the key map: Space is "center_on_ship" and no longer part of "fire";
##   - docked, a Space tap puts the camera on the mothership's spot;
##   - a pilot's camera jumps to a ship that launches (an Admiral's stays);
##   - look_at_point (a minimap click) moves the camera of a pilot too, and the
##     camera does not follow the ship by itself;
##   - the mouse at a screen edge pans the camera, and it stops when the mouse
##     comes back; a middle-button drag pulls the map;
##   - a Space tap centers the camera on the ship, and after the tap the
##     camera is free again;
##   - holding Space keeps the ship in the middle of the screen while it flies
##     at 900 units a second, letting go frees the camera, and Space never
##     fires the guns;
##   - how far a pilot may zoom out is unchanged (5,200 units across for a
##     fighter; an Admiral's free camera still sees the whole map).
## A spectator has no ship: Space must leave the camera alone.
##
## HOW IT WORKS: setup() looks at the key map and, for a pilot or an Admiral,
## buys a fighter for the human (it stays in the hangar until the test
## launches it). Then _physics_process() runs numbered steps, one after
## another, as tests/bot_pilot.gd does: each step parks the camera, presses a
## key, moves the mouse or the ship, waits for the camera to settle (it slides
## to its goal in well under a second) and prints a PASS or FAIL line. The
## test node runs after the World each tick (process_physics_priority), so
## the ship it moves is where the camera looks in the same frame. The mouse
## starts in the middle of the screen, because a windowless run's mouse sits at
## (0, 0), the screen corner, and the camera would pan into it. (A windowless
## run's window is only 64 pixels across, and the test branch stretches the
## picture to the window while v0.2.0 does not, so every mouse point here is
## worked out from the viewport's size and mapped to window pixels, which is
## what input events carry; a point outside the viewport counts as a screen
## edge.)
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/; the seat is picked by --role):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=camera_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=input --no-pilots --no-admiral-ai --test=camera_check
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-admiral-ai --test=camera_check
## (the last one is the spectator seat). --bot=input tells main.gd not to
## launch the human's ship by itself.
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or
## "FAIL <what> <detail>" (the detail is the number that was measured). The
## last line is "camera_check: N failures"; 0 means every check passed.
##
## WHO USES IT: main.gd loads it for --test=camera_check. It drives CameraRig
## (scripts/camera/camera_rig.gd) with the "center_on_ship" action of
## GameInputMap and reads PlayerController's ShipControls.

## Where the camera is parked for the checks: far from everything.
const FAR_A := Vector2(30000, 4000)
## A second parking spot, for the launch.
const FAR_B := Vector2(30000, 22000)
## Where the ship hovers.
const SPOT_A := Vector2(9000, 13000)
## A spot to look at, as if it was clicked on the minimap.
const LOOK_P := Vector2(15000, 6000)
## The speed the ship flies at while Space is held (world units a second).
const FLY := Vector2(900, 0)
## The step the zoom checks start at (a spectator jumps straight to it).
const STEP_ZOOM := 15

## The running match (set by setup()).
var world: World
## The match's camera.
var cam: CameraRig
## The seat: "pilot", "admiral" or "spectator".
var role := ""
## The human's ship once the test has launched it.
var ship: Ship
## Seconds since the test started.
var t := 0.0
## Which step of the test we are on (see _physics_process).
var step := 0
## Seconds since the current step began.
var step_t := 0.0
## How many checks failed so far.
var fails := 0
## A remembered position (the camera's, for comparing later).
var mark := Vector2.ZERO
## The largest distance between the camera and the ship while Space was held.
var max_off := 0.0
## True if the human's guns were ever told to fire while Space was down.
var fired := false


## main.gd calls this once, right after the World is built. Check the key
## map, make input events arrive at once, and buy the human a fighter.
func setup(w: World) -> void:
	world = w
	cam = w.camera
	role = w.human_role
	# Run after the World each physics tick, so the ship's place is the one
	# this test sets, and the camera (which runs later in the frame) sees it.
	process_physics_priority = 100
	# Input events reach the game at once, not at the start of the next frame.
	Input.use_accumulated_input = false
	# No minion waves.
	world.minion_director.next_wave = INF
	_check_key_map()
	if world.human != null:
		world.human.credits = 2000.0
		world.human.buy_hull("fighter", world.teams[0])


## Print one PASS or FAIL line for the check `name` (`ok` = it passed), with
## the measured `detail`, and count the failures.
func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Move on to the next step and restart the step clock.
func _next() -> void:
	step += 1
	step_t = 0.0


## Jump to step `n` and restart the step clock.
func _goto(n: int) -> void:
	step = n
	step_t = 0.0


## Key map checks: Space belongs to "center_on_ship" and not to "fire"; the
## left mouse button still fires.
func _check_key_map() -> void:
	var fire_space := false
	var fire_mouse := false
	for ev: InputEvent in InputMap.action_get_events("fire"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SPACE:
			fire_space = true
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			fire_mouse = true
	var center_space := false
	for ev: InputEvent in InputMap.action_get_events("center_on_ship"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SPACE:
			center_space = true
	_check("Space is not a fire key", not fire_space, "fire has a Space key: %s" % fire_space)
	_check("the left mouse button still fires", fire_mouse)
	_check("Space is the center_on_ship key", center_space)


## Press (`down` true) or let go of the Space key, as the keyboard would.
func _space(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.keycode = KEY_SPACE
	ev.pressed = down
	Input.parse_input_event(ev)


## Window pixels for screen point `p`. Input events carry window pixels, and
## the viewport maps them back to its own screen pixels through the stretch
## (the test branch stretches the picture to the window, v0.2.0 does not).
func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


## Move the mouse pointer to screen point `p` (pixels).
func _mouse_to(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _win(p)
	ev.global_position = _win(p)
	Input.parse_input_event(ev)


## Drag with the middle mouse button from screen point `a` to `b`.
func _drag_middle(a: Vector2, b: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	down.position = _win(a)
	down.global_position = _win(a)
	Input.parse_input_event(down)
	var move := InputEventMouseMotion.new()
	move.position = _win(b)
	move.global_position = _win(b)
	move.relative = _win(b) - _win(a)
	Input.parse_input_event(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_MIDDLE
	up.pressed = false
	up.position = _win(b)
	up.global_position = _win(b)
	Input.parse_input_event(up)


## The middle of the screen (pixels).
func _mid() -> Vector2:
	return cam.get_viewport_rect().size * 0.5


## Put the camera at world point `p` at once, goal included.
func _park(p: Vector2) -> void:
	cam.look_at_point(p)
	cam.global_position = p


## How far the camera is from world point `p`.
func _off(p: Vector2) -> float:
	return cam.global_position.distance_to(p)


## The spot the camera looks at when there is no ship: 900 world units in
## front of the Aurelian mothership.
func _home() -> Vector2:
	var ms := world.mothership(0)
	return ms.global_position + Vector2.from_angle(ms.rotation) * 900.0


## Launch the human's fighter and hold it still at SPOT_A.
func _launch() -> void:
	ship = world.launch(world.human)
	ship.global_position = SPOT_A
	ship.velocity = Vector2.ZERO


## How many world units fit across the screen at the camera's current zoom.
func _width() -> float:
	return cam.get_viewport_rect().size.x / cam.zoom.x


## Print the total and quit. (The PROBE_JSON line is what the queue,
## run_batch.ps1, counts as this test's result.)
func _finish() -> void:
	print("camera_check: %d failures" % fails)
	print("PROBE_JSON %s" % JSON.stringify({"test": "camera_check", "role": role, "failures": fails}))
	get_tree().quit()


## Godot calls this every tick; `dt` is the tick's length in seconds. Run the
## current step: each one parks, presses, moves, waits and checks.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	t += dt
	step_t += dt
	var first := step_t <= dt * 1.5
	match step:
		# 0: park the camera with the mouse in the middle. 0.5 s later it must
		# not have moved (no edge pan), which also proves this run can place
		# the mouse. Then press Space.
		0:
			if first:
				_mouse_to(_mid())
				_park(FAR_A)
			if step_t > 0.5:
				_check("mouse in the middle: the camera stays put", _off(FAR_A) < 5.0, "%.1f off, mouse at %s" % [_off(FAR_A), cam.get_viewport().get_mouse_position()])
				_space(true)
				_next()
		# 1: let go of Space 0.05 s later (a tap of a few ticks).
		1:
			if step_t > 0.05:
				_space(false)
				_next()
		# 2: a spectator has no ship: Space must have left the camera alone
		# (then only the zoom checks are left). Anyone else is docked: the
		# camera must be on the mothership's spot. Then park it far away and
		# launch the fighter.
		2:
			if step_t > 1.5:
				if role == "spectator":
					_check("spectator: Space leaves the camera alone", _off(FAR_A) < 5.0, "%.1f off" % _off(FAR_A))
					_goto(STEP_ZOOM)
					return
				_check("docked: a Space tap centers the camera on the mothership", _off(_home()) < 5.0, "%.1f off" % _off(_home()))
				_park(FAR_B)
				_launch()
				_next()
		# 3: a pilot's camera has jumped to the new ship; an Admiral's stays.
		# Then look at LOOK_P, as a minimap click does.
		3:
			if step_t > 1.5:
				if role == "pilot":
					_check("launch: a pilot's camera jumps to the new ship", _off(ship.global_position) < 5.0, "%.1f off" % _off(ship.global_position))
				else:
					_check("launch: an Admiral's camera stays where it was", _off(FAR_B) < 5.0, "%.1f off" % _off(FAR_B))
				cam.look_at_point(LOOK_P)
				_next()
		# 4: look_at_point moved the camera, and the camera is not following
		# the ship. Then push the mouse to the left screen edge.
		4:
			if step_t > 1.5:
				_check("look_at_point (a minimap click) moves the camera", _off(LOOK_P) < 5.0, "%.1f off" % _off(LOOK_P))
				_check("the camera does not follow the ship by itself", _off(ship.global_position) > 3000.0, "%.0f from the ship" % _off(ship.global_position))
				mark = cam.global_position
				_mouse_to(Vector2(2.0, _mid().y))
				_next()
		# 5: the camera has panned left; bring the mouse back.
		5:
			if step_t > 0.6:
				_check("mouse at the left edge pans the camera left", cam.global_position.x < mark.x - 800.0, "moved %.0f" % (cam.global_position.x - mark.x))
				_mouse_to(_mid())
				_next()
		# 6: wait for the slide to end.
		6:
			if step_t > 1.0:
				mark = cam.global_position
				_next()
		# 7: with the mouse back in the middle the camera has stopped. Then
		# drag the map with the middle button, 10 pixels left and 4 up (a
		# windowless run's screen is only 64 pixels across), and put the mouse
		# back in the middle.
		7:
			if step_t > 0.5:
				_check("mouse back in the middle: the camera stops", _off(mark) < 1.0, "%.2f moved" % _off(mark))
				mark = cam.global_position
				_drag_middle(_mid() + Vector2(5.0, 2.0), _mid() + Vector2(-5.0, -2.0))
				_mouse_to(_mid())
				_next()
		# 8: pulling the map left and up moves the camera right and down by
		# those pixels over the zoom. Then tap Space.
		8:
			if step_t > 1.0:
				var want := mark + Vector2(10.0, 4.0) / cam.zoom.x
				var got := cam.global_position - mark
				_check("middle-drag pulls the map", cam.global_position.distance_to(want) < 0.03 * want.distance_to(mark), "moved %.0f, %.0f (wanted %.0f, %.0f)" % [got.x, got.y, want.x - mark.x, want.y - mark.y])
				_space(true)
				_next()
		# 9: let go of Space.
		9:
			if step_t > 0.05:
				_space(false)
				_next()
		# 10: the camera is on the ship. Move the ship away.
		10:
			if step_t > 1.5:
				_check("a Space tap centers the camera on the ship", _off(ship.global_position) < 5.0, "%.1f off" % _off(ship.global_position))
				ship.global_position = SPOT_A + Vector2(5000.0, 0.0)
				_next()
		# 11: after a tap the camera is free: it stayed. Then park the camera
		# far away, put the ship back and press Space for the hold.
		11:
			if step_t > 1.0:
				_check("after a tap the camera does not follow the ship", _off(SPOT_A) < 5.0, "%.1f off" % _off(SPOT_A))
				_park(FAR_A)
				ship.global_position = SPOT_A
				ship.velocity = Vector2.ZERO
				max_off = 0.0
				_space(true)
				_next()
		# 12: hold Space while the ship flies at FLY. From 1.5 s on the ship
		# must stay in the middle of the screen, and the guns must stay quiet.
		# At 3.5 s let go.
		12:
			ship.global_position = SPOT_A + FLY * step_t
			ship.velocity = FLY
			if ship.controls.fire:
				fired = true
			if step_t > 1.5:
				max_off = maxf(max_off, _off(ship.global_position))
			if step_t > 3.5:
				_check("holding Space keeps the ship in the middle of the screen", max_off < 30.0, "at most %.1f units off at %d units a second" % [max_off, int(FLY.length())])
				_check("Space does not fire the guns", not fired, "controls.fire seen: %s" % fired)
				_space(false)
				_next()
		# 13: the ship flies on; after 0.7 s the camera should have settled:
		# remember where it is.
		13:
			ship.global_position = SPOT_A + FLY * (3.5 + step_t)
			ship.velocity = FLY
			if step_t > 0.7:
				mark = cam.global_position
				_next()
		# 14: a second later the camera must not have moved, while the ship is
		# far away: letting go of Space made it free.
		14:
			ship.global_position = SPOT_A + FLY * (4.2 + step_t)
			ship.velocity = FLY
			if step_t > 1.0:
				_check("letting go of Space frees the camera", _off(mark) < 1.0 and _off(ship.global_position) > 400.0, "%.2f moved, %.0f from the ship" % [_off(mark), _off(ship.global_position)])
				_next()
		# 15: how far out can the camera go? Ask for far too much; a pilot
		# must stop at the fighter's 5,200 units across (times the zoom_max
		# variant's factor), an Admiral or spectator at the whole map plus 10%.
		15:
			if first:
				cam.target_zoom = 0.0001
			if step_t > 2.0:
				var lim := cam.zoom_limits()
				var want := 5200.0 * ZoomMaxFeature.factor() if role == "pilot" else MapLayout.W * 1.1
				_check("zoom-out limit (%s)" % role, absf(_width() - want) < want * 0.005 and absf(lim.x - cam.get_viewport_rect().size.x / want) < 0.0001, "%.0f units across, wanted %.0f" % [_width(), want])
				_check("zoom_limited() (%s)" % role, cam.zoom_limited() == (role == "pilot"), "free %s, limited %s" % [cam.free, cam.zoom_limited()])
				cam.target_zoom = 1000.0
				_next()
		# 16: the closest zoom is unchanged: 1,100 units across. Then the C
		# switch: a pilot has none; an Admiral can follow the ship (and then
		# has a pilot's zoom limit) and go free again.
		16:
			if step_t > 2.0:
				_check("closest zoom is 1100 units across", absf(_width() - CameraRig.MIN_VIEW_WIDTH) < 6.0, "%.0f units across" % _width())
				cam.toggle_free()
				var after_one := cam.free
				var limited := cam.zoom_limited()
				cam.toggle_free()
				if role == "admiral":
					_check("Admiral: C follows the ship (pilot zoom limit) and frees it again", not after_one and limited and cam.free, "free after one switch %s, limited %s, free after two %s" % [after_one, limited, cam.free])
				elif role == "pilot":
					_check("pilot: C does nothing to the camera", after_one and cam.free, "free after one switch %s" % after_one)
				_finish()
