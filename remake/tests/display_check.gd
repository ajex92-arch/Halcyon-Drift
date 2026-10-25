extends Node
## WHAT THIS IS: a check of the window settings: the stretch (the picture
## is scaled from a 1280 x 720 base to the window), the smallest window size
## and the fullscreen key (F11 / Alt+Enter). It prints what the window and
## the viewport look like, and "display_check: N failures" at the end.
##
## HOW IT WORKS: setup() starts a short routine that waits a few frames for
## the window to settle and then:
##   1. checks the fullscreen action: F11 (not in a web build), Alt+Enter
##      and Alt+keypad Enter are keys of it, and a plain Enter, Shift+Enter
##      and Alt alone are not; it also prints which other actions an
##      Alt+Enter press matches (a loose match ignores the Alt key; Godot's
##      own buttons and text boxes ask for an exact match);
##   2. with no window (--headless), or with --real-toggle, sends a plain
##      Enter and an Alt+Enter through the viewport and counts how many reach
##      the screens' own key handling (_unhandled_input): the plain Enter
##      must reach it (so the check means something) and the Alt+Enter must
##      not, because Game._input used it up;
##   3. with a window, prints the sizes, checks the stretch settings and the
##      minimum size, and checks that the mouse position reads in the
##      viewport's own pixels (the base pixels), not the window's;
##   4. with --real-toggle (a window only), presses Alt+Enter and then F11
##      for real and checks that the window went to fullscreen and back. That
##      covers the monitor for a moment, so it is off by default.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=display_check
##   godot --path remake --resolution 1024x600 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --all-ai --test=display_check
## The second one opens a window off the visible screen; add --real-toggle
## after the -- to try the fullscreen key for real.
##
## HOW TO READ THE OUTPUT: "display_check: window=..." lines say what Godot
## made of the window; a line starting "display_check FAIL" names a broken
## expectation; the last line is "display_check: N failures" (0 is good).
##
## WHO USES IT: main.gd loads it for --test=display_check (for --test=<name>
## it loads tests/<name>.gd, adds it after the World and calls setup()).

## The number of failed expectations so far.
var _bad := 0
## How many plain-Enter and how many Alt+Enter key presses reached
## _unhandled_input (a two-item list: plain, Alt).
var _reached := [0, 0]


## main.gd calls this once, right after the World is built (the World `_w`
## is not needed). Start the checks.
func setup(_w: World) -> void:
	_run()


## Godot sends here the key presses that no screen used. Count the Enter
## presses, plain and with Alt (see _check_key_flow).
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ENTER:
		_reached[1 if key.alt_pressed else 0] += 1


## The checks, one after the other (they wait for frames, so this is a
## coroutine: Godot lets it pause at each "await").
func _run() -> void:
	# Step 1: let the window settle (a window can still be resized by the
	# system in its first frames).
	for i in 8:
		await get_tree().process_frame
	var real := DisplayServer.get_name() != "headless"
	var real_toggle: bool = Game.opt("real-toggle", false) == true and real
	# Step 2: the action and its keys.
	_check_keys()
	# Step 3: the key presses, only where they cannot cover the user's screen
	# (no window, or --real-toggle).
	if not real or real_toggle:
		await _check_key_flow(real_toggle)
	# Step 4: the window's own numbers (a window only).
	if real:
		_check_window()
	print("display_check: %d failures" % _bad)
	get_tree().quit()


## Count a failure and name it when `ok` is false.
func _check(ok: bool, what: String) -> void:
	if not ok:
		_bad += 1
		print("display_check FAIL: ", what)


## A key press (or release) event for key `code`, with Alt and Shift as
## given. Real key events carry both the key and its place on the keyboard.
func _key_event(code: Key, alt: bool, pressed: bool, shift := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.alt_pressed = alt
	ev.shift_pressed = shift
	ev.pressed = pressed
	return ev


## Which keys the "toggle_fullscreen" action answers to, and which other
## actions an Alt+Enter press matches.
func _check_keys() -> void:
	var act := "toggle_fullscreen"
	_check(InputMap.has_action(act), "the action toggle_fullscreen exists")
	if not InputMap.has_action(act):
		return
	if not OS.has_feature("web"):
		_check(InputMap.event_is_action(_key_event(KEY_F11, false, true), act), "F11 toggles fullscreen")
	_check(InputMap.event_is_action(_key_event(KEY_ENTER, true, true), act), "Alt+Enter toggles fullscreen")
	_check(InputMap.event_is_action(_key_event(KEY_KP_ENTER, true, true), act), "Alt+keypad Enter toggles fullscreen")
	_check(not InputMap.event_is_action(_key_event(KEY_ENTER, false, true), act), "a plain Enter does not toggle fullscreen")
	_check(not InputMap.event_is_action(_key_event(KEY_ENTER, false, true, true), act), "Shift+Enter does not toggle fullscreen")
	_check(not InputMap.event_is_action(_key_event(KEY_ALT, true, true), act), "Alt alone does not toggle fullscreen")
	# Which actions does an Alt+Enter press match, loosely and exactly?
	var loose := []
	var exact := []
	var alt_enter := _key_event(KEY_ENTER, true, true)
	for a: StringName in InputMap.get_actions():
		if InputMap.event_is_action(alt_enter, a, false):
			loose.append(String(a))
		if InputMap.event_is_action(alt_enter, a, true):
			exact.append(String(a))
	loose.sort()
	exact.sort()
	print("display_check: keys ok=%s events=%d web=%s; Alt+Enter matches loosely %s, exactly %s" % [_bad == 0, InputMap.action_get_events(act).size(), OS.has_feature("web"), loose, exact])
	_check(exact == [act], "Alt+Enter matches only toggle_fullscreen when the match is exact (got %s)" % [exact])


## Send a plain Enter and an Alt+Enter through the viewport (the way a key
## press from the keyboard arrives) and count what reaches the screens'
## _unhandled_input: the plain Enter must (the control), Alt+Enter must
## not. With `real_toggle` (a window) also check that Alt+Enter and F11
## really switch the window to fullscreen and back.
func _check_key_flow(real_toggle: bool) -> void:
	var vp := get_viewport()
	# Step 1: the control: a plain Enter reaches _unhandled_input.
	vp.push_input(_key_event(KEY_ENTER, false, true))
	await get_tree().process_frame
	vp.push_input(_key_event(KEY_ENTER, false, false))
	await get_tree().process_frame
	_check(_reached[0] == 1, "control: a plain Enter reaches the screens' key handling (reached %d times)" % _reached[0])
	# Step 2: Alt+Enter must be used up before it gets there. With
	# --real-toggle the window goes fullscreen (its mode and size are printed
	# before, after and after going back).
	var size_before := DisplayServer.window_get_size()
	if real_toggle:
		_print_window_state("before")
	vp.push_input(_key_event(KEY_ENTER, true, true))
	for i in 10:
		await get_tree().process_frame
	if real_toggle:
		_print_window_state("after Alt+Enter")
		_check(WindowMode.is_fullscreen(), "Alt+Enter put the window in fullscreen")
	vp.push_input(_key_event(KEY_ENTER, true, false))
	await get_tree().process_frame
	_check(_reached[1] == 0, "Alt+Enter was used up before the screens saw it (reached %d times)" % _reached[1])
	# Step 3: with --real-toggle, F11 brings the window back.
	if real_toggle:
		vp.push_input(_key_event(KEY_F11, false, true))
		for i in 10:
			await get_tree().process_frame
		_print_window_state("after F11")
		_check(not WindowMode.is_fullscreen(), "F11 brought the window back from fullscreen")
		_check(DisplayServer.window_get_size() == size_before, "the window is back at its old size %s (is %s)" % [size_before, DisplayServer.window_get_size()])
		vp.push_input(_key_event(KEY_F11, false, false))
		await get_tree().process_frame
	print("display_check: key flow done (plain Enter reached %d, Alt+Enter reached %d, real_toggle=%s)" % [_reached[0], _reached[1], real_toggle])


## Print the window's mode (0 window, 2 maximised, 3 borderless fullscreen,
## 4 exclusive fullscreen), position, size and the viewport's size, with a
## label for the moment.
func _print_window_state(label: String) -> void:
	print("display_check: window state %s: mode=%d position=%s size=%s viewport=%s" % [label, DisplayServer.window_get_mode(), DisplayServer.window_get_position(), DisplayServer.window_get_size(), get_viewport().get_visible_rect().size])


## Print the window's numbers and check the stretch, the minimum size and
## the mouse mapping. Only for a run with a window.
func _check_window() -> void:
	var win := get_window()
	var ws := DisplayServer.window_get_size()
	var vs := get_viewport().get_visible_rect().size
	print("display_check: window=%s min_size=%s os_min_size=%s viewport=%s content_scale_size=%s mode=%d aspect=%d final_scale=%.4f" % [
		ws, win.min_size, DisplayServer.window_get_min_size(), vs, win.content_scale_size,
		win.content_scale_mode, win.content_scale_aspect, win.get_final_transform().get_scale().x])
	# Step 1: the project settings arrived: canvas items stretch, expand, a
	# 1280 x 720 base, and the minimum size.
	_check(win.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "stretch mode is canvas_items")
	_check(win.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "stretch aspect is expand")
	_check(win.content_scale_size == WindowMode.MIN_SIZE, "the base size is 1280 x 720")
	_check(win.min_size == WindowMode.MIN_SIZE, "the window's minimum size is 1280 x 720")
	_check(ws.x >= WindowMode.MIN_SIZE.x and ws.y >= WindowMode.MIN_SIZE.y, "the window is at least 1280 x 720 (is %s)" % ws)
	# Step 2: the viewport is the base size grown on the wide or tall side:
	# window / scale, with scale = the smaller of window / base across and down.
	var fit := minf(float(ws.x) / 1280.0, float(ws.y) / 720.0)
	var want := Vector2(ws) / fit
	_check(vs.distance_to(want) < 1.5, "the viewport is %s base pixels (want about %s)" % [vs, want])
	# Step 3: the mouse position reads in viewport pixels. Godot gives the
	# viewport's mouse position from where the real pointer is, so compare it
	# with the pointer's place in the window (screen position minus the
	# window's position, in window pixels) divided by the stretch scale. The
	# pointer need not be over the window; both are read together, and a pointer
	# that is moving a little gives a pixel or two of difference.
	var window_px := Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position())
	var mp := get_viewport().get_mouse_position()
	var expect := window_px / fit
	print("display_check: pointer at window pixel %s reads %s in the viewport (want about %s)" % [window_px, mp, expect])
	_check(mp.distance_to(expect) < 3.0, "the mouse position %s is in viewport pixels (want about %s for window pixel %s)" % [mp, expect, window_px])