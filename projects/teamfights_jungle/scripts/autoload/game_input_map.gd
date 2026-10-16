class_name GameInputMap
extends RefCounted
## WHAT THIS IS: the list of the game's controls: which keys and mouse
## buttons do what.
##
## HOW IT WORKS: Godot works with "input actions": a named control such as
## "fire" that one or more keys or buttons can trigger. Game code then asks
## Input.is_action_pressed("fire") instead of asking about one key, so a
## control can have several keys (fire = Space or the left mouse button).
## define_all() goes down the list once at startup. For each action it
## makes the action if it doesn't exist yet and adds each key or mouse
## button to it. Keys are matched by their place on the keyboard (Godot's
## "physical" key code, named after a US keyboard), so the W/A/S/D block
## stays in the same spot on other keyboard layouts.
##
## WHO USES IT: Game._ready() calls define_all() (through
## Game._define_actions()). The actions are read by PlayerController (the
## human's flying), HudInput (the screen keys), CameraRig (zoom keys, and
## the move keys to pan the free camera) and tests/bot_pilot.gd, which
## presses them like a player would.
##
## The controls are defined in code rather than in project.godot so they
## are easy to read and tests can press them by name. All functions here
## are "static": they belong to the class itself and are called as
## GameInputMap.define_all(), without making an object first.


## Define every control, in this order (the order is kept as it always
## was).
static func define_all() -> void:
	# Flying: W/S forward and back, A/D (or Q/E) slide sideways, Shift boosts.
	_key("thrust_forward", [KEY_W])
	_key("thrust_back", [KEY_S])
	_key("strafe_left", [KEY_A, KEY_Q])
	_key("strafe_right", [KEY_D, KEY_E])
	_key("boost", [KEY_SHIFT])
	# Weapons: fire (Space or left mouse) and the hull's special ability
	# (G or right mouse).
	_key("fire", [KEY_SPACE])
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_key("special", [KEY_G])
	_mouse("special", MOUSE_BUTTON_RIGHT)
	# Shield focus: the arrow keys point the shields to one side.
	_key("shield_front", [KEY_UP])
	_key("shield_rear", [KEY_DOWN])
	_key("shield_left", [KEY_LEFT])
	_key("shield_right", [KEY_RIGHT])
	# Energy routing: 1-4 send the ship's power to weapons, shields,
	# thrusters, or spread it evenly.
	_key("energy_weapons", [KEY_1])
	_key("energy_shields", [KEY_2])
	_key("energy_thrusters", [KEY_3])
	_key("energy_balanced", [KEY_4])
	# Ship helpers: R uses a repair kit, V turns flight assist on or off.
	_key("use_kit", [KEY_R])
	_key("assist_toggle", [KEY_V])
	# Screens: B hangar, F dock (or launch), Tab admiral board, H help,
	# C camera (the admiral switches free / follow).
	_key("hangar", [KEY_B])
	_key("dock", [KEY_F])
	_key("admiral_board", [KEY_TAB])
	_key("help", [KEY_H])
	_key("center_camera", [KEY_C])
	# Zoom: = or keypad + zooms in, - or keypad - zooms out. Esc cancels.
	_key("zoom_in", [KEY_EQUAL, KEY_KP_ADD])
	_key("zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT])
	_key("cancel", [KEY_ESCAPE])


## Add keyboard keys `keys` (key codes such as KEY_W) to action `action`,
## making the action first if it doesn't exist yet.
static func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# One key event per key, matched by the key's place on the keyboard.
	for k: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


## Add mouse button `button` (such as MOUSE_BUTTON_LEFT) to action
## `action`, making the action first if it doesn't exist yet.
static func _mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
