extends Node
## WHAT THIS IS: the pause menu check: a test that P and Esc open and close the
## pause menu the way the design says, that the game really stands still while
## it shows, and that Restart and Quit to start load a fresh match. It plays the
## keys through the game's own input path, like a person at the keyboard, and
## presses the menu's buttons.
##
## HOW IT WORKS: it waits until the HUD exists, makes the window 1280 x 720 (a
## headless window is only 64 x 64 pixels) and then, in this order:
##   1. Esc closes an open panel first and opens no menu;
##   2. Esc with nothing open opens the menu: the game is paused, the menu shows
##      and the big centre message steps aside; the match clock stands still for
##      30 frames; Esc again resumes (the clock moves again, and a mouse button
##      the World still thought was held is read again);
##   3. P opens the menu and P resumes;
##   4. H over the menu shows the help pages and hides the menu while the game
##      stays paused; the help's Close button, Esc and H each close the help and
##      the menu comes back; P from the help pages resumes at once;
##   5. a question (Restart) is a view of the menu: Esc goes back to the buttons
##      and Esc again resumes;
##   6. while the menu holds the game, B and Tab do nothing;
##   7. the buttons are there (Resume, How to play, Restart match, Quit to start,
##      the window button, and Quit game except in a web page) and Resume works;
##   8. an armed Admiral map tool: Esc puts the tool away and opens no menu;
##   9. the match ending while the menu holds the game lifts the pause;
##  10. with --restart-check the real thing: the Restart and Quit to start buttons
##      are pressed, each question answered with Yes, and the main scene that
##      loads again holds a fresh match (a new HUD, the same seat, the clock near
##      zero, not paused, no start screen) or the start screen's replacement in
##      a windowless run (which starts at once).
## It ends with "pause_menu_check: N failures" (0 = all good) and quits. If the
## run takes over 60 seconds of real time it prints "pause_menu_check: timeout".
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=pause --force-hud --test=pause_menu_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --bot=pause --force-hud --test=pause_menu_check --restart-check
## (--bot=pause only keeps the game from buying a ship and launching for the
## human.)
##
## WHO USES IT: main.gd loads it for --test=pause_menu_check. It reads the HUD
## (Hud, HudPanels, PauseMenu, HudInput) and the World, and presses real keys
## and buttons; it changes nothing else. With --restart-check it moves itself to
## the top of the scene tree and empties the --test option, so it survives the
## scene reload and the new match does not start a second copy of it.

## Frames the match clock must stand still while the menu shows.
const STILL_FRAMES := 30
## Frames the clock gets to move after a resume.
const MOVING_FRAMES := 30

## The running match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## True once the check has started (it runs once).
var started := false
## How many checks failed.
var failures := 0


## main.gd calls this once, right after the World is built. Remember the match,
## make the window the size the screens are laid out for and keep running even
## while the game is paused.
func setup(w: World) -> void:
	world = w
	get_tree().root.size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Godot calls this every drawn frame. Quit after 60 s of real time; start the
## check once the HUD (a node named "Hud") exists.
func _process(_dt: float) -> void:
	if world == null:
		return
	if Time.get_ticks_msec() > 60000:
		print("pause_menu_check: timeout")
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
	_expect(hud.pause_menu == null and not get_tree().paused, "start: no menu yet and the game runs")
	# Step 1: Esc closes an open panel first and opens no menu.
	hud._close_others(null)
	if world.human_role == "admiral":
		hud._toggle_board()
	else:
		hud._open_hangar()
	_expect(hud._any_panel_open(), "step 1: a panel is open")
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(not hud._any_panel_open() and not get_tree().paused and hud.pause_menu == null, "Esc with a panel open closes it and opens no menu")
	# Step 2: Esc with nothing open opens the menu; the game stands still.
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(_menu_open(), "Esc with nothing open opens the pause menu (paused %s)" % get_tree().paused)
	_expect(not hud.banner.visible, "the big centre message steps aside for the menu")
	var t0 := world.time
	await _frames(STILL_FRAMES)
	_expect(world.time == t0, "the match clock stands still while the menu shows (%.3f -> %.3f)" % [t0, world.time])
	world.mouse_fire = true
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(_menu_closed(), "Esc over the menu resumes")
	_expect(not world.mouse_fire, "resume reads the mouse buttons again (no button is held)")
	var t1 := world.time
	await _frames(MOVING_FRAMES)
	_expect(world.time > t1, "the match clock moves again after the resume (%.3f -> %.3f)" % [t1, world.time])
	# Step 3: P opens and P resumes.
	_key(KEY_P)
	await _frames(2)
	_expect(_menu_open(), "P opens the pause menu")
	_key(KEY_P)
	await _frames(2)
	_expect(_menu_closed(), "P over the menu resumes")
	# Step 4: H over the menu shows the help pages; the game stays paused.
	_key(KEY_P)
	await _frames(2)
	_key(KEY_H)
	await _frames(2)
	_expect(hud.help != null and hud.help.visible and not hud.pause_menu.visible and get_tree().paused and hud.pause_menu.active, "H over the menu shows the help and hides the menu; the game stays paused")
	hud.help.closed.emit()
	await _frames(2)
	_expect(_menu_open() and not hud.help.visible, "the help's Close button brings the menu back")
	_key(KEY_H)
	await _frames(2)
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(_menu_open() and not hud.help.visible, "Esc closes the help and the menu comes back")
	_key(KEY_H)
	await _frames(2)
	_key(KEY_H)
	await _frames(2)
	_expect(_menu_open() and not hud.help.visible, "H closes the help and the menu comes back")
	_key(KEY_H)
	await _frames(2)
	_key(KEY_P)
	await _frames(2)
	_expect(_menu_closed() and not hud.help.visible, "P from the help pages resumes at once")
	# Step 5: a question is a view of the menu.
	_key(KEY_P)
	await _frames(2)
	hud.pause_menu.ask(PauseMenu.VIEW_RESTART)
	await _frames(2)
	_expect(hud.pause_menu.current_view() == PauseMenu.VIEW_RESTART and _button("Yes, restart") != null and _button("Back") != null, "the Restart question has its two buttons")
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(_menu_open() and hud.pause_menu.current_view() == PauseMenu.VIEW_MENU, "Esc over a question goes back to the buttons")
	hud.pause_menu.ask(PauseMenu.VIEW_START)
	await _frames(2)
	_button("Back").pressed.emit()
	await _frames(2)
	_expect(_menu_open() and hud.pause_menu.current_view() == PauseMenu.VIEW_MENU, "Back goes back to the buttons")
	# Step 6: the other keys stay quiet while the menu holds the game.
	_key(KEY_B)
	_key(KEY_TAB)
	await _frames(2)
	_expect(_menu_open() and (hud.hangar == null or not hud.hangar.visible) and (hud.board == null or not hud.board.visible), "B and Tab do nothing while the menu holds the game")
	# Step 7: the buttons are there, and Resume works.
	for text: String in ["Resume", "How to play", "Restart match", "Quit to start"]:
		_expect(_button(text) != null, "the menu has a %s button" % text)
	_expect(_button("Full screen") != null or _button("Windowed") != null, "the menu has the window button")
	_expect((_button("Quit game") == null) == OS.has_feature("web"), "Quit game is there except in a web page")
	_button("Resume").pressed.emit()
	await _frames(2)
	_expect(_menu_closed(), "the Resume button resumes")
	# Step 8: an armed Admiral map tool is put away by Esc before any menu.
	if world.human_role == "admiral":
		world.teams[world.human_team].repair_bays = true
		hud.overlay.arm("bay")
		_expect(hud.overlay.tool != "", "step 8: a map tool is armed")
		_key(KEY_ESCAPE)
		await _frames(2)
		_expect(hud.overlay.tool == "" and _menu_closed(), "Esc puts an armed map tool away and opens no menu")
	# Step 9: the match ending lifts the pause.
	_key(KEY_P)
	await _frames(2)
	hud._on_match_over(Rules.HALCYON, "The Cinder mothership was destroyed.")
	await _frames(2)
	_expect(not get_tree().paused and not hud.pause_menu.active and not hud.pause_menu.visible, "the match ending while the menu holds the game lifts the pause")
	# Step 10: the real Restart and Quit to start.
	if Game.opt("restart-check", false):
		await _restart_run()
	print("pause_menu_check: %d failures" % failures)
	get_tree().quit()


## Step 10: press Restart match and Quit to start with their Yes buttons, each
## time on a fresh match, and look at the main scene that loads again.
func _restart_run() -> void:
	var role := world.human_role
	# Survive the scene reload, and let the new match start without a copy of
	# this test.
	reparent(get_tree().root)
	Game.options["test"] = ""
	for which: String in ["restart", "start"]:
		var old_scene := get_tree().current_scene
		var old_hud := get_tree().root.find_child("Hud", true, false) as Hud
		if old_hud.end_screen != null:
			# The ended match of step 9 has an end screen over everything.
			old_hud.end_screen.queue_free()
			old_hud.end_screen = null
		if old_hud.pause_menu != null:
			old_hud.pause_menu.end_session()
		old_hud._toggle_pause_menu()
		await _frames(2)
		if which == "restart":
			_button("Restart match").pressed.emit()
			await _frames(2)
			_button("Yes, restart").pressed.emit()
		else:
			_button("Quit to start").pressed.emit()
			await _frames(2)
			_button("Yes, quit to start").pressed.emit()
		for i in 120:
			await get_tree().process_frame
			if get_tree().current_scene != old_scene and get_tree().current_scene != null:
				break
		await _frames(10)
		var main := get_tree().current_scene
		var new_hud := get_tree().root.find_child("Hud", true, false) as Hud
		_expect(main != old_scene and new_hud != null and new_hud != old_hud, "%s: the main scene loaded again with a new HUD" % which)
		_expect(not get_tree().paused, "%s: the new match is not paused" % which)
		_expect(Game.restart_role == "", "%s: the restart seat was used up" % which)
		var new_world = main.get("world")
		_expect(new_world != null and new_world != world and float(new_world.time) < 5.0, "%s: a fresh match is running (clock near zero)" % which)
		if which == "restart":
			_expect(new_world != null and new_world.human_role == role, "restart: the seat is the same (%s)" % role)
			_expect(main.get("start_screen") == null, "restart: no start screen came up")
		# The next round runs on the new match.
		world = new_world
		hud = new_hud
		hud._close_others(null)


## Is the pause menu open and holding a paused game?
func _menu_open() -> bool:
	return hud.pause_menu != null and hud.pause_menu.visible and hud.pause_menu.active and get_tree().paused


## Is the game running and the menu gone (hidden, with no session)?
func _menu_closed() -> bool:
	return not get_tree().paused and (hud.pause_menu == null or (not hud.pause_menu.visible and not hud.pause_menu.active))


## The pause menu's button showing `text`, or null.
func _button(text: String) -> Button:
	if hud.pause_menu == null:
		return null
	for b in hud.pause_menu.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


## Press and let go of keyboard key `code` (a place on the keyboard, such as
## KEY_P), as a person does, through the game's input path.
func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = down
		get_viewport().push_input(ev)


## Count a PASS or FAIL line for the check `what`.
func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


## Wait `n` drawn frames.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
