extends Node
## WHAT THIS IS: the UI tour. It drives the HUD (the on-screen panels:
## hangar, help, scoreboard, admiral board ...) through its screens and
## saves screenshots. Windowed, it saves a PNG at every step. Headless
## with --force-hud (which builds the HUD anyway), it clicks through the
## same screens without pictures: any script error in the UI shows up in
## the output.
##
## HOW IT WORKS: it waits until the HUD exists, then follows a timed list
## of steps: one list for a pilot (_pilot_steps) and one for an admiral
## (_admiral_steps), picked by the human's role. Each step is [seconds
## since the HUD appeared, a function to run]. Some steps open a screen,
## buy something or move the camera; the others take a picture (_shot).
## The last step prints "ui_tour: done (...)" and quits. If the whole run
## takes over 60 seconds of real time (60 for each window size of a
## --ui-size list), it prints "ui_tour: timeout" and quits.
## The tour covers the screens a player really meets, each in its busiest
## state: the hangar (all four tabs, and opened in flight), the docked
## message, the flying HUD with a full kill feed, earnings log and pop-up
## hint, the help pages, the scoreboard, the pause message, both
## motherships in trouble, the dead screen with the hangar open over it,
## the end screen (with a pop-up hint shown just before the match ends)
## and the start screen; for an admiral the board's five tabs, the map
## tool, the help, the pause and the hangar.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --path remake --resolution 1280x720 -- --auto --role=pilot --test=ui_tour --shots=<dir>
##   godot --path remake --resolution 1280x720 -- --auto --role=admiral --test=ui_tour --shots=<dir>
##   godot --headless --path remake -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour --dump
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour --dump-layout --ui-size=1366x657
## The first two run in a window and save pictures in the folder given by
## --shots (default: Godot's user data folder). The third runs with no
## window (--headless); --bot=tour stops main.gd from buying and launching
## the human's ship by itself, so the tour starts in the hangar. The
## fourth also prints every control on screen at every picture step
## (--dump, see UiDump); with --fixed-fps 60 each step happens on the same
## game frame every run, so two builds' dumps can be compared line by line.
## The fifth is the layout check: --dump-layout adds what
## tools/ui_layout_check.py needs (see UiDump), and --ui-size=WxH is the
## window size to test (a headless window is only 64 x 64 pixels, so the
## dump uses 1280x720 when --ui-size is not given). Pipe the output of the
## fifth, one run per role and size, into the checker. Several sizes
## separated by commas (--ui-size=1280x720,1366x657,1024x600) make one run
## dump every picture step at each size in turn, resizing the window
## between the dumps the way a player resizing the browser does; that is
## the quick way to test many sizes, one run per role.
##
## HOW TO READ THE OUTPUT: windowed, one "shot <path>" line per picture
## (p01_hangar_ships.png ... p10_start.png for a pilot, a01_start.png ...
## a09_hangar.png for an admiral). Headless, one "ui_tour step <name>"
## line per picture step instead, plus the UIDUMP lines with --dump. The
## run ends with "ui_tour: done (pilot)" or "ui_tour: done (admiral)". Any
## SCRIPT ERROR line from Godot means a UI script broke.
##
## WHO USES IT: main.gd loads it for --test=ui_tour (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()), and
## builds the HUD headless only for --force-hud. It finds the node named
## "Hud" and calls the HUD's own functions: Hud._toggle_help(),
## _show_scoreboard(), _toggle_board(), _on_match_over(),
## Hangar._set_tab() / launch(), AdmiralBoard._set_tab(), HelpPanel._show()
## and CommandOverlay arm() / apply_at() / disarm(). tests/lib/ui_dump.gd
## prints the dumps.

## The start screen, shown once at the end of the pilot tour (--auto runs
## never show it otherwise).
const START_SCENE := preload("res://scenes/ui/start_screen.tscn")
## Prints the dumps (the UIDUMP lines).
const UiDump := preload("res://tests/lib/ui_dump.gd")
## The kill feed's lines for a busy fight: [text, tone]. They are the
## longest sentences HudFeed makes (a kill, a lost repair bay, a lost
## turret, finished research, a finished module), and there are seven, as
## many as the feed keeps (HudFeed.MAX_LINES).
const FEED_LINES := [
	["Valkyrie-Nine shot down Nightingale's Capital Ship", "good"],
	["Aurelian repair bay at Upper Crossing destroyed", "good"],
	["Vhorr destroyed the Aurelian Flak Turret at Lower Asteroid Cluster", "bad"],
	["Research complete: Heavy Plating. Frigate can now be bought in the hangar.", "good"],
	["Module built: Capital Ship Facility. Capital Ship can now be bought in the hangar.", "good"],
	["Pike's Frigate was destroyed by an Aurelian turret", "good"],
	["Free mining drone queued for the Aurelian fleet", "info"],
]
## The reasons of four earnings lines (HudMePanel keeps four).
const EARN_REASONS := ["kill", "assist", "turret", "ore"]

## The running match (set by setup()).
var world: World
## The HUD, once we have found it (null until then).
var hud: Hud
## The folder the pictures go into (--shots).
var dir := ""
## Seconds since the HUD was found (the step times count from then).
var t := 0.0
## Which step is next (an index into the step list).
var step := 0
## The human's role: "pilot" or "admiral" (picks the step list).
var role := "pilot"
## True with --dump or --dump-layout: picture steps also print every
## control (see UiDump).
var dump := false
## True with --dump-layout: the dump also carries the extra facts the
## layout checker needs.
var layout := false
## The window sizes of a headless dump (--ui-size; the first is the size
## the run starts and ends at).
var sizes: Array[Vector2i] = [Vector2i(1280, 720)]
## True while a step is still running (a dump at several sizes takes a few
## frames), so the next step waits for it.
var busy := false


## main.gd calls this once, right after the World is built. Remember the
## role and the picture folder, and keep running even if the game is
## paused. A pilot's camera stays where it is left (Space centers it), and a
## fresh window's mouse sits at (0, 0), the screen corner, where the free
## camera would pan away: so a pilot's tour holds Space the whole time, and
## the pictures keep the ship (while docked, the mothership) in view.
func setup(w: World) -> void:
	world = w
	role = w.human_role
	if role == "pilot":
		Input.action_press("center_on_ship")
	layout = Game.opt("dump-layout", false) == true
	dump = layout or Game.opt("dump", false) == true
	# A headless window is only 64 x 64 pixels; give the dump the real
	# window size, so text wraps and panels sit as they do on screen.
	sizes = _ui_sizes()
	if DisplayServer.get_name() == "headless" and (dump or Game.opt("ui-size") != null):
		get_tree().root.size = sizes[0]
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS


## The window sizes for a headless dump: --ui-size=WxH (such as 1366x657),
## or several of them separated by commas. A size that is not WxH with at
## least 320 x 240 is skipped; with none left, 1280x720 (the size
## project.godot sets).
func _ui_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in str(Game.opt("ui-size", "1280x720")).split(",", false):
		var xy := part.split("x")
		if xy.size() == 2 and int(xy[0]) >= 320 and int(xy[1]) >= 240:
			out.append(Vector2i(int(xy[0]), int(xy[1])))
	if out.is_empty():
		out.append(Vector2i(1280, 720))
	return out


## Godot calls this every drawn frame; `dt` is the frame's length in
## seconds. Find the HUD, then run each step when its time comes.
func _process(dt: float) -> void:
	if world == null:
		return
	# Safety net: quit after 60 s of real time since the program started
	# (for each window size of a headless dump at several sizes).
	if Time.get_ticks_msec() > 60000 * sizes.size():
		print("ui_tour: timeout")
		get_tree().quit()
	# Wait until the HUD exists (it is a node named "Hud" somewhere in the
	# scene).
	if hud == null:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud == null:
			return
	# Run the next step once its time has come, and wait for it to finish
	# ("await": a picture step waits for the frame to be drawn).
	t += dt
	var steps: Array = _pilot_steps() if role == "pilot" else _admiral_steps()
	if step >= steps.size() or busy:
		return
	var s: Array = steps[step]
	if t >= float(s[0]):
		step += 1
		busy = true
		await (s[1] as Callable).call()
		busy = false


## Take the picture `name`: windowed, wait for the frame to be drawn and
## save it as <name>.png in the --shots folder; headless, just print
## "ui_tour step <name>" (there is nothing to take a picture of). With
## --dump (or --dump-layout) every control on screen is printed too, in a
## window as well as headless; headless with several --ui-size sizes, once
## at each size (see _dump_sizes()).
func _shot(name: String) -> void:
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		print("ui_tour step ", name)
	if dump and headless and sizes.size() > 1:
		await _dump_sizes(name)
	elif dump:
		UiDump.dump(hud, name, layout)
	if headless:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("shot ", path)


## Dump picture step `name` at every window size in turn: resize the window,
## let the HUD lay itself out again (8 frames: the panels rebuild their
## cards when their width changes, and the big message and the HUD's other
## texts refresh 10 times a second, every 6 frames) and print the dump. The
## window goes back to the first size at the end.
func _dump_sizes(name: String) -> void:
	for sz in sizes:
		_keep_lines_alive()
		get_tree().root.size = sz
		for i in 8:
			await get_tree().process_frame
		UiDump.dump(hud, name, layout)
	get_tree().root.size = sizes[0]
	for i in 3:
		await get_tree().process_frame


## Make the kill feed's and the earnings log's lines new again. They fade
## out after 9 and 5 real seconds, and a dump at many sizes takes longer
## than that, so the last sizes would see an empty feed.
func _keep_lines_alive() -> void:
	for box: Container in [hud.feed, hud.me_panel.earn_box]:
		for c in box.get_children():
			c.set_meta("born", Time.get_ticks_msec())
			(c as CanvasItem).modulate.a = 1.0


## Fill the HUD the way a long fight does: the kill feed full (FEED_LINES),
## four earnings lines under the credits, and (`with_toast`) a pop-up hint.
## The layout check needs the HUD at its fullest, since an empty HUD hides
## overlaps.
func _busy_hud(with_toast: bool = true) -> void:
	for l: Array in FEED_LINES:
		Events.feed.emit(l[0], l[1], world.human_team)
	for r: String in EARN_REASONS:
		Events.credits_earned.emit(world.human, 40.0, r)
	if with_toast:
		Events.toast.emit("Pick a ship in the hangar and launch. H explains everything.")


## Put both motherships in trouble (`on` = true: a systems failure with 25
## seconds to go, which writes the longest top bar and banner texts) or
## clear it again.
func _trouble(on: bool) -> void:
	for team in 2:
		world.mothership(team).failure_t = 25.0 if on else 0.0


## The pilot's tour: [seconds since the HUD appeared, what to do]. Each
## "func() -> void: ..." is a small function written in place (a lambda).
func _pilot_steps() -> Array:
	return [
		# The hangar's Ships tab, then its Gear tab.
		[1.0, func() -> void: await _shot("p01_hangar_ships")],
		[1.5, func() -> void:
			hud.hangar._set_tab("Gear")],
		[2.0, func() -> void: await _shot("p02_hangar_gear")],
		# Buy a fighter and a repair kit, then the Modules tab, then Kits.
		[2.5, func() -> void:
			world.human.buy_hull("fighter", world.teams[world.human_team])
			world.human.buy_kit()
			hud.hangar._set_tab("Modules")],
		[3.0, func() -> void: await _shot("p03_hangar_modules")],
		[3.2, func() -> void:
			hud.hangar._set_tab("Kits")],
		[3.4, func() -> void: await _shot("p03a_hangar_kits")],
		# Close the hangar while still docked: the "Docked at the mothership"
		# message, then launch and take a picture in flight.
		[3.5, func() -> void: hud.hangar.visible = false],
		[3.9, func() -> void: await _shot("p03b_docked")],
		[4.0, func() -> void: hud.hangar.launch()],
		[7.0, func() -> void: await _shot("p04_flying")],
		# The busiest flying HUD: full kill feed, earnings and a hint.
		[7.1, func() -> void: _busy_hud()],
		[7.4, func() -> void: await _shot("p04a_feed")],
		# The hangar opened in flight (B): its longest status line.
		[7.6, func() -> void: hud._open_hangar()],
		[8.0, func() -> void: await _shot("p04b_hangar_flying")],
		[8.1, func() -> void: hud.hangar.visible = false],
		# The help screen (its longest page too), then the scoreboard.
		[8.2, func() -> void: hud._toggle_help()],
		[8.6, func() -> void: await _shot("p05_help")],
		[8.8, func() -> void: hud.help._show("Admiral")],
		[9.0, func() -> void: await _shot("p05a_help_admiral")],
		[9.1, func() -> void:
			hud._toggle_help()
			hud._show_scoreboard(true)],
		[9.5, func() -> void: await _shot("p06_scoreboard")],
		# Close the scoreboard and jump the match clock to 64 s, past the
		# first minion wave's time (45 s), for a picture of a wave. Pause
		# for a picture of the pause message first.
		[10.0, func() -> void:
			hud._show_scoreboard(false)
			world.time = 64.0
			get_tree().paused = true],
		[10.4, func() -> void: await _shot("p06a_pause")],
		[10.5, func() -> void: get_tree().paused = false],
		[14.5, func() -> void: await _shot("p07_wave")],
		# Both motherships in trouble: the longest top bar and banner text.
		[14.7, func() -> void: _trouble(true)],
		[15.1, func() -> void: await _shot("p07a_trouble")],
		[15.3, func() -> void: _trouble(false)],		# Destroy our own ship, for a picture of the "dead" screen.
		[15.5, func() -> void:
			var s := world.human.ship
			if s != null:
				world.combat.kill(s, DamageInfo.new())],
		[16.5, func() -> void: await _shot("p08_dead")],
		# The hangar over the dead screen, as the HUD opens it on a respawn,
		# with the kill feed busy.
		[16.7, func() -> void:
			_busy_hud(false)
			hud._open_hangar()],
		[17.1, func() -> void: await _shot("p08a_dead_hangar")],
		[17.3, func() -> void: hud.hangar.visible = false],
		# The end screen, shown the way the HUD shows it when a match ends
		# (Hud._on_match_over). The match itself goes on: a real ending
		# closes headless test runs at once (main.gd), before the picture.
		[17.7, func() -> void:
			Events.toast.emit("Rally waypoint set.")
			hud._on_match_over(Rules.HALCYON, "The Cinder mothership was destroyed.")],
		[18.7, func() -> void: await _shot("p09_end")],
		# The start screen on top of everything, for one last picture (--auto
		# runs never show it otherwise).
		[18.9, func() -> void: hud.add_child(START_SCENE.instantiate())],
		[19.1, func() -> void: await _shot("p10_start")],
		[19.2, func() -> void:
			print("ui_tour: done (pilot)")
			get_tree().quit()],
	]


## The admiral's tour: [seconds since the HUD appeared, what to do].
func _admiral_steps() -> Array:
	return [
		# The start, with a busy HUD, then the admiral board (it opens on
		# Research).
		[1.0, func() -> void: await _shot("a01_start")],
		[1.1, func() -> void: _busy_hud()],
		[1.3, func() -> void: await _shot("a01a_feed")],
		[1.5, func() -> void: hud._toggle_board()],
		[2.0, func() -> void: await _shot("a02_board_research")],
		# Order the research facility and the repair bay research (the
		# admiral's order desk queues them), and visit the Build,
		# Mothership, Fleet and Pilots tabs.
		[2.5, func() -> void:
			world.command.build_facility(0, "research")
			world.command.research(0, "repairBays")
			hud.board._set_tab("Build")],
		[3.0, func() -> void: await _shot("a03_board_build")],
		[3.5, func() -> void: hud.board._set_tab("Mothership")],
		[4.0, func() -> void: await _shot("a04_board_mothership")],
		[4.5, func() -> void: hud.board._set_tab("Fleet")],
		[5.0, func() -> void: await _shot("a05_board_fleet")],
		# The command orders that feature modules add (none in today's game):
		# press each button and look at the map tool.
		[5.2, func() -> void: await _tour_orders()],
		[5.5, func() -> void: hud.board._set_tab("Pilots")],
		[6.0, func() -> void: await _shot("a06_board_pilots")],
		# Close the board, allow repair bays, pick the "place a bay" tool on
		# the map, and look at the spot (9000, 13000).
		[6.5, func() -> void:
			hud._toggle_board()
			world.teams[world.human_team].repair_bays = true
			hud.overlay.arm("bay")
			world.camera.look_at_point(_my_side(Vector2(9000, 13000)))],
		[8.0, func() -> void: await _shot("a07_tool_bay")],
		# Place the bay there, put the tool away, and look at the middle
		# of the map (20000, 13000).
		[8.5, func() -> void:
			hud.overlay.apply_at(_my_side(Vector2(9000, 13000)))
			hud.overlay.disarm()
			world.camera.look_at_point(Vector2(20000, 13000))],
		[11.0, func() -> void: await _shot("a08_map_mid")],
		# The help (the Admiral page), the pause message, the hangar an
		# admiral can open with B, and both motherships in trouble.
		[11.2, func() -> void:
			hud._toggle_help()
			hud.help._show("Admiral")],
		[11.6, func() -> void: await _shot("a08a_help")],
		[11.8, func() -> void:
			hud._toggle_help()
			get_tree().paused = true],
		[12.2, func() -> void: await _shot("a08b_pause")],
		[12.3, func() -> void:
			get_tree().paused = false
			hud._open_hangar()],
		[12.8, func() -> void: await _shot("a09_hangar")],
		[13.0, func() -> void:
			hud.hangar.visible = false
			_trouble(true)],
		[13.4, func() -> void: await _shot("a09a_trouble")],
		[13.6, func() -> void:
			_trouble(false)
			print("ui_tour: done (admiral)")
			get_tree().quit()],
	]


## A map point written for Aurelian's side of the map, as the human's side has it:
## the same point for Aurelian, its mirror image across the centre line for Vhorr.
func _my_side(p: Vector2) -> Vector2:
	return p if world.human_team == Rules.HALCYON else MapLayout.mirror(p)


## The admiral tour's order step: for each command order that a feature
## module added (CommandOrders; there are none unless --variant switches one
## on), press its button on the Fleet tab. An order that needs a spot arms
## its map tool: take a picture of the tool, then click a spot near our
## mothership (the order may be refused there, which is printed). Prints one
## "ui_tour: order <id> ..." line per order, puts the tool away and reopens
## the board if the tool closed it.
func _tour_orders() -> void:
	var orders: Dictionary = world.command.orders
	if orders.is_empty():
		return
	world.teams[world.human_team].treasury = 20000.0
	var spot := _my_side(world.mothership(Rules.HALCYON).global_position + Vector2(2500, 0))
	for id in orders:
		hud.board._refresh()
		var btn: Button = hud.board._cards.get("order:" + str(id))
		if btn == null:
			print("ui_tour: order %s has NO BUTTON" % id)
			continue
		if btn.disabled:
			print("ui_tour: order %s button is disabled" % id)
			continue
		btn.pressed.emit()
		if hud.overlay.tool != "":
			world.camera.look_at_point(spot)
			await _shot("a05b_tool_" + str(id))
			print("ui_tour: order %s armed; hint: %s; spot check: '%s'" % [id, hud.overlay.hint(), hud.overlay.blocker_at(spot)])
			hud.overlay.apply_at(spot)
			hud.overlay.disarm()
		else:
			print("ui_tour: order %s given from its button" % id)
		if not hud.board.visible:
			hud._toggle_board()
		hud.board._set_tab("Fleet")
	await _shot("a05c_orders_done")
