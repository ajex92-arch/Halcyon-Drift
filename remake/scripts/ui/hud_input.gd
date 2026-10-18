class_name HudInput
extends RefCounted
## WHAT THIS IS: the part of the HUD that decides what the menu keys do:
## P pause, Tab (Admiral board or scoreboard), B hangar, H help, Esc
## cancel / close, C camera and F launch.
##
## HOW IT WORKS: Godot gives the HUD every key press the game didn't use
## (Hud._unhandled_input) and the HUD passes it to handle(). Keys only work
## while the match is being played, and a key held down long enough to
## repeat ("echo") is ignored. Each key that does something is marked
## "handled", so nothing else reacts to it as well. The key names
## ("hangar", "dock", ...) are actions set up in Game (autoload/game.gd),
## for example "dock" is F and "admiral_board" is Tab.
##
## WHO USES IT: Hud makes one (hud.router) and calls handle() for each key.
## It opens panels through the Hud's forwarding functions (HudPanels does
## the work), cancels CommandOverlay map tools, and switches the camera
## (CameraRig.toggle_free).

## The HUD this part belongs to (we read its world, panels and overlay).
var hud: Hud


## Remember which HUD we belong to.
func _init(owner: Hud) -> void:
	hud = owner


## Tell Godot this key press is used up, so no other node reacts to it.
func _handled() -> void:
	hud.get_viewport().set_input_as_handled()


## React to one key press or release (see HOW IT WORKS).
func handle(event: InputEvent) -> void:
	var world := hud.world
	# Step 1: only real key presses during play.
	if world == null or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.echo:
		return
	if world.phase != "play":
		return
	# Step 2: P pauses or resumes the whole game.
	if k.pressed and k.physical_keycode == KEY_P:
		hud.get_tree().paused = not hud.get_tree().paused
		_handled()
		return
	# Step 3: Tab. The Admiral toggles their board on each press; a pilot
	# sees the scoreboard only while Tab is held down (press shows it,
	# release hides it).
	if event.is_action("admiral_board"):
		if world.human_role == "admiral":
			if k.pressed:
				hud._toggle_board()
		else:
			hud._show_scoreboard(k.pressed)
		_handled()
		return
	# Every other key only reacts when pressed, not when let go.
	if not k.pressed:
		return
	# Step 4: B opens the hangar, or closes it if it is showing.
	if event.is_action("hangar"):
		if hud.hangar != null and hud.hangar.visible:
			hud.hangar.visible = false
		else:
			hud._open_hangar()
		_handled()
	# Step 5: H shows or hides the help pages.
	elif event.is_action("help"):
		hud._toggle_help()
		_handled()
	# Step 6: Esc cancels an armed map tool first; otherwise it closes
	# every panel.
	elif event.is_action("cancel"):
		if hud.overlay.tool != "":
			hud.overlay.disarm()
		else:
			hud._close_others(null)
		_handled()
	# Step 7: C switches the Admiral's camera between free and following
	# their ship (a pilot's camera is always free: Space centers it, see
	# CameraRig, so C does nothing for a pilot).
	elif event.is_action("center_camera"):
		if world.human_role == "admiral":
			world.camera.toggle_free()
			hud.toast("Camera: %s" % ("free (WASD / edges / minimap)" if world.camera.free else "following your ship"))
		_handled()
	# Step 8: F launches when docked. A pilot can always do this; an
	# Admiral only while the hangar is open. The hangar does the
	# launching, so it is made (and hidden again) if it doesn't exist yet.
	# The key counts as used only if the launch worked.
	elif event.is_action("dock"):
		var h := world.human
		var may := world.human_role == "pilot" or (hud.hangar != null and hud.hangar.visible)
		if h != null and h.state == "docked" and may:
			if hud.hangar == null:
				hud._open_hangar()
				hud.hangar.visible = false
			if hud.hangar.launch():
				_handled()
