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
## takes over 60 seconds of real time, it prints "ui_tour: timeout" and
## quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --path remake --resolution 1280x720 -- --auto --role=pilot --test=ui_tour --shots=<dir>
##   godot --path remake --resolution 1280x720 -- --auto --role=admiral --test=ui_tour --shots=<dir>
##   godot --headless --path remake -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=tour --force-hud --test=ui_tour --dump
## The first two run in a window and save pictures in the folder given by
## --shots (default: Godot's user data folder). The third runs with no
## window (--headless); --bot=tour stops main.gd from buying and launching
## the human's ship by itself, so the tour starts in the hangar. The
## fourth also prints every control on screen at every picture step
## (--dump, see _dump()); with --fixed-fps 60 each step happens on the same
## game frame every run, so two builds' dumps can be compared line by line.
##
## HOW TO READ THE OUTPUT: windowed, one "shot <path>" line per picture
## (p01_hangar_ships.png ... p10_start.png for a pilot, a01_start.png ...
## a08_map_mid.png for an admiral). Headless, one "ui_tour step <name>"
## line per picture step instead, plus the UIDUMP lines with --dump. The
## run ends with "ui_tour: done (pilot)" or "ui_tour: done (admiral)". Any
## SCRIPT ERROR line from Godot means a UI script broke.
##
## WHO USES IT: main.gd loads it for --test=ui_tour (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()), and
## builds the HUD headless only for --force-hud. It finds the node named
## "Hud" and calls the HUD's own functions: Hud._toggle_help(),
## _show_scoreboard(), _toggle_board(), _on_match_over(),
## Hangar._set_tab() / launch(), AdmiralBoard._set_tab() and
## CommandOverlay arm() / apply_at() / disarm().

## The start screen, shown once at the end of the pilot tour (--auto runs
## never show it otherwise).
const START_SCENE := preload("res://scenes/ui/start_screen.tscn")

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
## True with --dump: headless picture steps also print every control
## (see _dump()).
var dump := false


## main.gd calls this once, right after the World is built. Remember the
## role and the picture folder, and keep running even if the game is
## paused.
func setup(w: World) -> void:
	world = w
	role = w.human_role
	dump = Game.opt("dump", false) == true
	# A headless window is only 64 x 64 pixels; give the dump the real
	# window size, so text wraps and panels sit as they do on screen.
	if dump:
		get_tree().root.size = Vector2i(1280, 720)
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Godot calls this every drawn frame; `dt` is the frame's length in
## seconds. Find the HUD, then run each step when its time comes.
func _process(dt: float) -> void:
	if world == null:
		return
	# Safety net: quit after 60 s of real time since the program started.
	if Time.get_ticks_msec() > 60000:
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
	if step >= steps.size():
		return
	var s: Array = steps[step]
	if t >= float(s[0]):
		step += 1
		await (s[1] as Callable).call()


## Take the picture `name`: windowed, wait for the frame to be drawn and
## save it as <name>.png in the --shots folder; headless, just print
## "ui_tour step <name>" (there is nothing to take a picture of), and
## with --dump every control on screen (_dump()).
func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("ui_tour step ", name)
		if dump:
			_dump(name)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("shot ", path)


## The pilot's tour: [seconds since the HUD appeared, what to do]. Each
## "func() -> void: ..." is a small function written in place (a lambda).
func _pilot_steps() -> Array:
	return [
		# The hangar's Ships tab, then its Gear tab.
		[1.0, func() -> void: await _shot("p01_hangar_ships")],
		[1.5, func() -> void:
			hud.hangar._set_tab("Gear")],
		[2.0, func() -> void: await _shot("p02_hangar_gear")],
		# Buy a fighter and a repair kit, then the Modules tab.
		[2.5, func() -> void:
			world.human.buy_hull("fighter", world.teams[0])
			world.human.buy_kit()
			hud.hangar._set_tab("Modules")],
		[3.0, func() -> void: await _shot("p03_hangar_modules")],
		# Launch, and take a picture in flight.
		[3.5, func() -> void: hud.hangar.launch()],
		[7.0, func() -> void: await _shot("p04_flying")],
		# The help screen, then the scoreboard.
		[7.5, func() -> void: hud._toggle_help()],
		[8.0, func() -> void: await _shot("p05_help")],
		[8.5, func() -> void:
			hud._toggle_help()
			hud._show_scoreboard(true)],
		[9.0, func() -> void: await _shot("p06_scoreboard")],
		# Close the scoreboard and jump the match clock to 64 s, past the
		# first minion wave's time (45 s), for a picture of a wave.
		[9.5, func() -> void:
			hud._show_scoreboard(false)
			world.time = 64.0],
		[14.0, func() -> void: await _shot("p07_wave")],
		# Destroy our own ship, for a picture of the "dead" screen.
		[14.5, func() -> void:
			var s := world.human.ship
			if s != null:
				world.combat.kill(s, DamageInfo.new())],
		[15.5, func() -> void: await _shot("p08_dead")],
		# The end screen, shown the way the HUD shows it when a match ends
		# (Hud._on_match_over). The match itself goes on: a real ending
		# closes headless test runs at once (main.gd), before the picture.
		[16.0, func() -> void:
			hud._on_match_over(Rules.HALCYON, "The Cinder mothership was destroyed.")],
		[17.0, func() -> void: await _shot("p09_end")],
		# The start screen on top of everything, for one last picture (--auto
		# runs never show it otherwise).
		[17.2, func() -> void: hud.add_child(START_SCENE.instantiate())],
		[17.4, func() -> void: await _shot("p10_start")],
		[17.5, func() -> void:
			print("ui_tour: done (pilot)")
			get_tree().quit()],
	]


## The admiral's tour: [seconds since the HUD appeared, what to do].
func _admiral_steps() -> Array:
	return [
		# The start, then the admiral board (it opens on Research).
		[1.0, func() -> void: await _shot("a01_start")],
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
			world.teams[0].repair_bays = true
			hud.overlay.arm("bay")
			world.camera.look_at_point(Vector2(9000, 13000))],
		[8.0, func() -> void: await _shot("a07_tool_bay")],
		# Place the bay there, put the tool away, and look at the middle
		# of the map (20000, 13000).
		[8.5, func() -> void:
			hud.overlay.apply_at(Vector2(9000, 13000))
			hud.overlay.disarm()
			world.camera.look_at_point(Vector2(20000, 13000))],
		[11.0, func() -> void: await _shot("a08_map_mid")],
		[11.5, func() -> void:
			print("ui_tour: done (admiral)")
			get_tree().quit()],
	]


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
	world.teams[0].treasury = 20000.0
	var spot := world.mothership(0).global_position + Vector2(2500, 0)
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


## With --dump (headless only): print every control that is showing, one
## "UIDUMP" line each, in tree order from the HUD down. A line is
## "UIDUMP <step> <depth> <class> <x>,<y> <w>x<h>" plus the mouse and
## focus settings, the see-through amount and what the control shows (its
## text, font size and colour, box style, bar value, gaps). Node names are
## left out on purpose: nodes made in code get made-up names, nodes in a
## scene get real ones, and both must dump the same. Two builds whose dumps
## match look the same on screen (scratchpad ui_dump.ps1 compares them).
func _dump(step: String) -> void:
	_dump_node(hud, 0, step)


## Print the line for `n` (if it is a control that shows) and then, if it
## shows, the lines of its children, one level deeper.
func _dump_node(n: Node, depth: int, step: String) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		print("UIDUMP %s %d %s" % [step, depth, _describe(n as Control)])
	for child in n.get_children():
		_dump_node(child, depth + 1, step)


## One control as text (see _dump()). Positions and sizes are rounded to
## whole pixels; colours are written as hex (rrggbbaa).
func _describe(c: Control) -> String:
	var r := c.get_global_rect()
	var s := "%s %d,%d %dx%d mouse=%d focus=%d mod=%s" % [c.get_class(), roundi(r.position.x), roundi(r.position.y),
		roundi(r.size.x), roundi(r.size.y), c.mouse_filter, c.focus_mode, c.modulate.to_html(true)]
	# What each kind of control shows.
	if c is Label:
		var l := c as Label
		s += " text=%s size=%d color=%s align=%d wrap=%d" % [JSON.stringify(l.text), l.get_theme_font_size("font_size"),
			l.get_theme_color("font_color").to_html(true), l.horizontal_alignment, l.autowrap_mode]
	elif c is RichTextLabel:
		s += " text=%s" % JSON.stringify((c as RichTextLabel).text)
	elif c is Button:
		var b := c as Button
		s += " text=%s size=%d color=%s disabled=%s normal=%s hover=%s pressed=%s off=%s" % [JSON.stringify(b.text),
			b.get_theme_font_size("font_size"), b.get_theme_color("font_color").to_html(true), b.disabled,
			_box(b.get_theme_stylebox("normal")), _box(b.get_theme_stylebox("hover")),
			_box(b.get_theme_stylebox("pressed")), _box(b.get_theme_stylebox("disabled"))]
	elif c is ProgressBar:
		var p := c as ProgressBar
		s += " value=%.3f fill=%s back=%s" % [p.value, _box(p.get_theme_stylebox("fill")), _box(p.get_theme_stylebox("background"))]
	elif c is ColorRect:
		s += " color=%s" % (c as ColorRect).color.to_html(true)
	# The box behind panels and scroll areas, and the gaps in rows and grids.
	if c is PanelContainer or c is ScrollContainer:
		s += " panel=%s" % _box(c.get_theme_stylebox("panel"))
	if c is BoxContainer:
		s += " sep=%d" % c.get_theme_constant("separation")
	if c is GridContainer:
		s += " cols=%d hsep=%d vsep=%d" % [(c as GridContainer).columns, c.get_theme_constant("h_separation"), c.get_theme_constant("v_separation")]
	return s


## A box style as text: fill and border colour, border widths, corner
## radius and the space inside (left/top/right/bottom). Other kinds of box
## are named by their class ("StyleBoxEmpty").
func _box(sb: StyleBox) -> String:
	if sb == null:
		return "none"
	if sb is StyleBoxFlat:
		var f := sb as StyleBoxFlat
		return "flat(%s,%s,b%d%d%d%d,r%d,m%d/%d/%d/%d)" % [f.bg_color.to_html(true), f.border_color.to_html(true),
			f.border_width_left, f.border_width_top, f.border_width_right, f.border_width_bottom, f.corner_radius_top_left,
			roundi(f.content_margin_left), roundi(f.content_margin_top), roundi(f.content_margin_right), roundi(f.content_margin_bottom)]
	return sb.get_class()
