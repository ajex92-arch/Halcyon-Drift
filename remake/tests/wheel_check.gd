extends Node
## WHAT THIS IS: the check that the mouse wheel over an open menu never
## zooms the camera behind it. The menus are the Admiral board (each of its
## five tabs), the hangar (each of its four tabs), the help (each page),
## the scoreboard and the end screen. The camera zooms on the wheel input
## no screen used (CameraRig._unhandled_input), so a wheel turn over a
## menu must scroll the menu or do nothing.
##
## HOW IT WORKS: it waits until the HUD exists, makes the window 1920 x
## 1080 (a headless window is only 64 x 64 pixels; --ui-size=WxH picks
## another size) and then:
##   1. the control: with every menu closed, one wheel turn in the middle
##      of the screen must change the camera's zoom goal (target_zoom), so
##      the check can see a zoom at all;
##   2. each menu in turn, opened alone: two frames for its layout, then 30
##      wheel turns down and 30 up at three points (the middle of the menu,
##      12 pixels below its top edge and 12 above its bottom edge). The
##      turns past the end of a list, and those over the menu's frame, are
##      the ones that reached the camera before the fix. After every turn
##      the zoom goal must be unchanged (a changed goal is counted and put
##      back). And where the list is taller than its scroll area, the 30
##      turns down in the middle must have scrolled it.
## Each turn is a press and a release of the wheel button, pushed into the
## window at that point (Viewport.push_input), so it takes the same path
## as a real wheel. The hangar is skipped when the human has no pilot
## profile, and the board when the human is not the Admiral. The end screen
## comes last: the HUD shows it as if Aurelian had won (the match goes on
## underneath, unpaused, as after a real win).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --auto --role=admiral --bot=tour --force-hud --test=wheel_check
##   godot --headless --path remake -- --auto --role=pilot --bot=tour --force-hud --test=wheel_check
##
## HOW TO READ THE OUTPUT: one "wheel_check <menu>: ok ..." line per menu,
## or "FAIL wheel_check <menu>: ...", then "wheel_check: N failures". If
## the run takes over 60 seconds of real time it prints "wheel_check:
## timeout" instead and quits.
##
## WHO USES IT: main.gd loads it for --test=wheel_check (see ui_tour.gd for
## how tests are loaded). It calls the HUD's own functions:
## Hud._toggle_board(), _open_hangar(), _toggle_help(), _show_scoreboard()
## _close_others() and _on_match_over(), then AdmiralBoard._set_tab(),
## Hangar._set_tab() and HelpPanel._show(). The quick checks (run_checks) run it for both roles.

## The board's tabs and the hangar's tabs, in the order they appear.
const BOARD_TABS := ["Research", "Build", "Mothership", "Fleet", "Pilots"]
const HANGAR_TABS := ["Ships", "Modules", "Gear", "Kits"]
## Wheel turns each way at each point.
const TURNS := 30

## The running match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## The window size the check runs at.
var size := Vector2i(1920, 1080)
## True once the check has started (it runs once).
var started := false
## How many menus failed.
var failures := 0


## main.gd calls this once, right after the World is built. Remember the
## world, pick the window size and keep running even if the game pauses.
func setup(w: World) -> void:
	world = w
	var xy := str(Game.opt("ui-size", "1920x1080")).split("x")
	if xy.size() == 2 and int(xy[0]) >= 320 and int(xy[1]) >= 240:
		size = Vector2i(int(xy[0]), int(xy[1]))
	get_tree().root.size = size
	process_mode = Node.PROCESS_MODE_ALWAYS


## Godot calls this every drawn frame. Quit after 60 s of real time; start
## the check once the HUD (a node named "Hud") exists.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 60000:
		print("wheel_check: timeout")
		get_tree().quit()
	if started:
		return
	hud = get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		return
	started = true
	_run()


## The whole check (see HOW IT WORKS), then the summary line and quit.
func _run() -> void:
	await _frames(5)
	# Step 1: the control, over the open map.
	hud._close_others(null)
	await _frames(2)
	var z := world.camera.target_zoom
	_turn(Vector2(size) / 2.0, MOUSE_BUTTON_WHEEL_DOWN)
	if world.camera.target_zoom == z:
		_fail("control", "a wheel turn over the open map left the zoom goal at %.4f, so this check cannot see a zoom" % z)
	else:
		print("wheel_check control: ok (a wheel turn over the open map zooms)")
	world.camera.target_zoom = z
	# Step 2: the board, on each tab (the Admiral only).
	if world.human_role == "admiral":
		hud._toggle_board()
		for t: String in BOARD_TABS:
			hud.board._set_tab(t)
			await _check("board " + t, hud.board)
		hud._close_others(null)
	# Step 3: the hangar, on each tab (it needs a pilot profile).
	hud._open_hangar()
	if hud.hangar == null:
		print("wheel_check hangar: skipped (no pilot profile)")
	else:
		for t: String in HANGAR_TABS:
			hud.hangar._set_tab(t)
			await _check("hangar " + t, hud.hangar)
	hud._close_others(null)
	# Step 4: the help, on each page.
	hud._toggle_help()
	for p: String in HelpPanel.PAGES.keys():
		hud.help._show(p)
		await _check("help " + p, hud.help)
	hud._close_others(null)
	# Step 5: the scoreboard (a pilot holds Tab for it).
	hud._show_scoreboard(true)
	await _check("scoreboard", hud.scoreboard)
	hud._show_scoreboard(false)
	# Step 6: the end screen, over a match that keeps running.
	hud._on_match_over(Rules.HALCYON, "The Cinder mothership was destroyed.")
	await _check("end screen", hud.end_screen)
	print("wheel_check: %d failures" % failures)
	get_tree().quit()


## Turn the wheel over menu `panel` (named `what` in the output) and count
## the turns that changed the camera's zoom goal (see HOW IT WORKS, step 2).
func _check(what: String, panel: Control) -> void:
	await _frames(2)
	if panel == null or not panel.visible:
		_fail(what, "the menu did not open")
		return
	var r := panel.get_global_rect()
	var points := [r.get_center(), Vector2(r.get_center().x, r.position.y + 12.0), Vector2(r.get_center().x, r.end.y - 12.0)]
	var scroll := _scroll_of(panel)
	var leaks := 0
	var scrolled := true
	for i in points.size():
		for button: MouseButton in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var before := scroll.scroll_vertical if scroll != null else 0
			for n in TURNS:
				var z := world.camera.target_zoom
				_turn(points[i], button)
				if world.camera.target_zoom != z:
					leaks += 1
					world.camera.target_zoom = z
			# The middle point's turns down must scroll a list taller than
			# its scroll area.
			if i == 0 and button == MOUSE_BUTTON_WHEEL_DOWN and scroll != null:
				var bar := scroll.get_v_scroll_bar()
				if bar.max_value - bar.page > 1.0 and scroll.scroll_vertical == before:
					scrolled = false
	if leaks > 0:
		_fail(what, "%d of %d wheel turns zoomed the camera behind the menu" % [leaks, points.size() * 2 * TURNS])
	elif not scrolled:
		_fail(what, "the list is taller than its scroll area but the wheel did not scroll it")
	else:
		print("wheel_check %s: ok (%d wheel turns, none zoomed the camera)" % [what, points.size() * 2 * TURNS])


## The first scroll area inside menu `panel`, or null if it has none.
func _scroll_of(panel: Control) -> ScrollContainer:
	var found := panel.find_children("*", "ScrollContainer", true, false)
	return found[0] as ScrollContainer if not found.is_empty() else null


## One wheel turn at window point `pos`: a press and a release of wheel
## button `button`, as a real mouse sends them.
func _turn(pos: Vector2, button: MouseButton) -> void:
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = down
		ev.factor = 1.0
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)


## Print one failure for menu `what` and count it.
func _fail(what: String, why: String) -> void:
	failures += 1
	print("FAIL wheel_check %s: %s" % [what, why])


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
