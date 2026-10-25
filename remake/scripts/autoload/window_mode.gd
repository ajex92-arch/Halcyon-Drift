class_name WindowMode
extends RefCounted
## WHAT THIS IS: the game window's size limit and its fullscreen switch.
##
## HOW IT WORKS: the project scales the whole picture with Godot's "canvas
## items" stretch (project.godot: base size 1280 x 720, aspect "expand").
## That means the screens (menus, HUD, panels) are laid out as if the window
## were 1280 x 720 or a little wider or taller, and Godot then enlarges
## everything to fill the real window. A window smaller than 1280 x 720
## would squeeze the screens below the size they were laid out for, so the
## window may never be smaller than that (MIN_SIZE).
##   - apply_minimum_size() sets that limit on the game's window once, at
##     startup.
##   - toggle_fullscreen() switches between the window (or the maximised
##     window) and borderless fullscreen, and remembers which one to go back
##     to.
##   - handle_input() is the listener for the key: it sees every key press
##     first, and for the fullscreen key (F11 or Alt+Enter) it toggles, then
##     marks the key as used, so nothing else reacts to Alt+Enter as if it
##     were a plain Enter. (A screen that matched Enter loosely, ignoring
##     the Alt key, would otherwise get it; Godot's own buttons match
##     exactly, so they would not, and the game has no other Enter key.)
## "Borderless fullscreen" is Godot's DisplayServer.WINDOW_MODE_FULLSCREEN:
## the window covers the whole screen without a frame and the monitor keeps
## its video mode (WINDOW_MODE_EXCLUSIVE_FULLSCREEN, which changes the
## monitor's mode, is not used). In a web browser the same call asks the
## browser for fullscreen, which is only allowed while a key press is being
## handled, and handle_input() runs exactly then (Godot's web notes say to
## ask from an input callback such as _input).
##
## WHO USES IT: Game._ready() calls apply_minimum_size() and Game._input()
## passes every input event to handle_input(). The action name
## "toggle_fullscreen" and its keys come from GameInputMap.
##
## All functions here are "static": they belong to the class itself and are
## called as WindowMode.toggle_fullscreen(), without making an object first.

## The smallest window allowed, in pixels: the base size the screens are
## laid out for (the same numbers as display/window/size/viewport_width and
## viewport_height in project.godot).
const MIN_SIZE := Vector2i(1280, 720)

## The window mode to go back to when fullscreen is switched off: the plain
## window, or the maximised one if that is what it was before.
static var _before_fullscreen: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_WINDOWED


## Stop `window` (the game's main window) from being made smaller than
## MIN_SIZE. A window with no screen (the --headless runs the tests use)
## is left alone, so those runs lay the screens out exactly as before.
static func apply_minimum_size(window: Window) -> void:
	if DisplayServer.get_name() == "headless":
		return
	window.min_size = MIN_SIZE


## Is the window in fullscreen right now (borderless or exclusive)?
static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Switch between borderless fullscreen and the mode the window was in
## before.
static func toggle_fullscreen() -> void:
	# Step 1: fullscreen now: go back to what it was before.
	if is_fullscreen():
		DisplayServer.window_set_mode(_before_fullscreen)
		return
	# Step 2: not fullscreen: remember the mode (window or maximised), then
	# go borderless fullscreen.
	_before_fullscreen = DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Look at one input event `event` (Game._input sends every one here, before
## any screen sees it). If it is the fullscreen key, toggle once per press
## (a key held down and repeating does nothing more) and mark the event as
## used on `viewport`, so no screen reacts to it as well (see the header:
## Alt+Enter must not count as an Enter).
static func handle_input(event: InputEvent, viewport: Viewport) -> void:
	if not (event is InputEventKey) or not event.is_action("toggle_fullscreen"):
		return
	viewport.set_input_as_handled()
	var key := event as InputEventKey
	if key.pressed and not key.echo:
		toggle_fullscreen()
