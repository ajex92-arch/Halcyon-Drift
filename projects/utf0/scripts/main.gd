extends Node
## WHAT THIS IS: the front door of the game. It runs right after the two
## autoloads (Game and Events): it shows the start screen (where you
## choose to be a pilot or the admiral), builds the match (the World), puts
## the screens on top of it, and in test runs prints a progress report
## every minute.
##
## HOW IT WORKS:
##   1. _ready() makes the screen layer and applies a few launch options
##      (Game, in scripts/autoload/game.gd, explains them all). Then it
##      either starts the match at once (test runs and runs without a
##      window) or shows the start screen and waits for a choice.
##   2. start(role) builds the World for that seat, adds the HUD (the
##      panels drawn over the game) and the sound player when there is a
##      window (neither with --sim-only, the speed mode of windowless test
##      runs: see Game), loads a test script when --test asks for one, adds
##      the stats recorder when --record-stats asks for it, and prints one
##      "match:" line about the map.
##   3. Every physics tick, the report part (MainReport) adds up how long
##      the simulation took, and prints a report each minute of match time.
##   4. When the match ends (Events.match_over) or the --max-minutes limit
##      is reached, it prints a last report and the "SUMMARY" line (and
##      tells the stats recorder, if there is one); in test runs it then
##      closes the game.
##
## WHO USES IT: scenes/main.tscn, the main scene named in project.godot,
## runs this script. It calls World.setup(), the HUD's setup() (from
## scenes/ui/hud.tscn), Sfx.setup() and the test script's setup(). The
## start screen (start_screen.gd) calls start() through its `chosen`
## signal.
##
## THE PARTS (files next to this one):
##   main_report.gd        (MainReport)        the minute reports and the
##                                             end-of-match SUMMARY
##   main_debug_overlay.gd (MainDebugOverlay)  the plain text overlay used
##                                             when the HUD scene is missing
##   stats_recorder.gd     (StatsRecorder)     the --record-stats notebook:
##                                             how each pilot fought, written
##                                             to a file (it only observes)
##   stats_pilot_record.gd (StatsPilotRecord)  its page for one pilot
##
## Words used here: a "tick" is one small step of game time; the game
## normally takes 60 of them per second. "Headless" means running with no
## window at all (automatic tests do this). An "autoload" is a script that
## Godot starts before everything else and that every file can reach by
## its name (here: Game and Events).
##
## Note: test tools read the printed report and SUMMARY lines, so their
## wording and layout must never change.

## The match scene: the World and its child nodes (camera, rocks, ...).
const WORLD_SCENE := "res://scenes/world/world.tscn"
## The start screen where the human picks a seat (pilot or admiral).
const START_SCENE := "res://scenes/ui/start_screen.tscn"
## The in-match screens (the HUD, short for "heads-up display").
const HUD_SCENE := "res://scenes/ui/hud.tscn"

## The running match, or null until start() has built it.
var world: World = null
## The screen layer every panel goes on. Layer 10 is drawn above the game.
var ui_layer: CanvasLayer
## The plain text overlay, made only when there is a window but no HUD
## scene; null otherwise.
var debug_label: Label = null
## The start screen (or the simple fallback buttons) while it is shown.
var start_screen: Node = null
## --max-minutes: stop the match after this many minutes of match time
## (0 = no limit).
var max_minutes := 0.0
## True once the match has ended or hit the time limit, so the last report
## and the SUMMARY are printed only once.
var _ended := false
## The report part: it counts tick times and prints the reports.
var reports := MainReport.new()
## The stats recorder, made by start() only when --record-stats is given
## (null otherwise): it writes how each pilot fought to a file.
var stats: StatsRecorder = null


## Godot calls this once when the game starts. Make the screen layer, apply
## the launch options, then start at once or show the start screen.
func _ready() -> void:
	# Step 1: the screen layer that every panel goes on, above the game.
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	max_minutes = float(Game.opt("max-minutes", 0.0))
	# Step 2: --seed=N sets the starting point ("seed") of the game's one
	# shared random sequence (AI dice rolls, weapon spread, waves), so the
	# same N plays the same match again. The map does not use it: the map
	# layout is always the same.
	if Game.opt("seed") != null:
		seed(int(Game.opt("seed")))
	# --speed=N runs the whole game N times as fast (Engine.time_scale).
	if Game.opt("speed") != null:
		Engine.time_scale = float(Game.opt("speed"))
	# Step 3: --snap=<png>: save one screenshot 1.5 s after start and quit
	# (used to check the start screen). The picture is taken right after
	# the next frame has been drawn.
	if Game.opt("snap") != null:
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(str(Game.opt("snap")))
			get_tree().quit())
	# Step 4: test runs (--auto or --all-ai) and windowless runs start at
	# once. --all-ai makes the human a spectator (watching only); otherwise
	# --role picks the seat (default "pilot").
	var auto: bool = bool(Game.opt("auto", false)) or bool(Game.opt("all-ai", false)) or DisplayServer.get_name() == "headless"
	if auto:
		var role := "spectator" if Game.opt("all-ai", false) else str(Game.opt("role", "pilot"))
		start(role)
	elif ResourceLoader.exists(START_SCENE):
		# Step 5: a person is playing: show the start screen. Its `chosen`
		# signal calls start() with the seat they picked.
		start_screen = load(START_SCENE).instantiate()
		ui_layer.add_child(start_screen)
		start_screen.connect("chosen", start)
	else:
		# No start screen scene: show two plain buttons instead.
		_simple_start()


## Fallback seat choice for when the real start screen scene is missing:
## a title and two plain buttons in the middle of the screen. Each button
## removes the buttons and calls start() with its seat.
func _simple_start() -> void:
	# Step 1: a centred column with the title.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ui_layer.add_child(box)
	var title := Label.new()
	title.text = "Halcyon Drift — choose your seat (this is locked for the match)"
	box.add_child(title)
	# Step 2: one button per seat: [button text, seat].
	for pair in [["Command as Admiral", "admiral"], ["Fly as a Pilot", "pilot"]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(func() -> void:
			box.queue_free()
			start(pair[1]))
		box.add_child(b)
	start_screen = box


## Build and start the match with the human in seat `role` ("pilot",
## "admiral" or "spectator"). It works only once: a second call does
## nothing. Called by _ready() in test runs, by the start screen's `chosen`
## signal, or by the fallback buttons.
func start(role: String) -> void:
	# Step 1: only one match per run; remove the start screen.
	if world != null:
		return
	if start_screen != null and is_instance_valid(start_screen):
		start_screen.queue_free()
	# Step 2: make the World from its scene and set it up for this seat.
	# --profile makes the World time each part of every tick.
	world = load(WORLD_SCENE).instantiate()
	add_child(world)
	world.profiling = Game.opt("profile", false)
	world.setup(role)
	# Step 3: hear about the end of the match (to print the last report).
	Events.match_over.connect(_on_match_over)
	# Step 4: the HUD is only built when there is a window to show it,
	# unless a test asks for it with --force-hud (headless UI checks:
	# tests/ui_tour.gd). The sound player is only made with a real window.
	# With --sim-only (Game.sim_only) neither is built: nothing is shown or
	# heard in that mode.
	var headless := DisplayServer.get_name() == "headless"
	if Game.sim_only:
		pass
	elif ResourceLoader.exists(HUD_SCENE) and (not headless or Game.opt("force-hud", false)):
		var hud: Node = load(HUD_SCENE).instantiate()
		ui_layer.add_child(hud)
		hud.call("setup", world)
		if not headless:
			var sfx := Sfx.new()
			add_child(sfx)
			sfx.setup(world)
	elif DisplayServer.get_name() != "headless":
		# A window but no HUD scene: show the plain text overlay instead.
		debug_label = MainDebugOverlay.make_label()
		ui_layer.add_child(debug_label)
	# Step 5: the test harness: --test=<name> loads tests/<name>.gd (a Node
	# with a setup(world) function) and adds it to the game.
	var test_name := str(Game.opt("test", ""))
	if test_name != "":
		var script: Script = load("res://tests/%s.gd" % test_name)
		var test_node: Node = script.new()
		add_child(test_node)
		test_node.call("setup", world)
	# Step 5b: --record-stats[=<file>]: the stats recorder (StatsRecorder). It
	# is not a test script, so it also works in a match you play from the
	# start screen. It only reads the match. Without the option nothing is
	# made. (A bare --record-stats is the value true: the default file.)
	var stats_opt = Game.opt("record-stats")
	if stats_opt != null:
		stats = StatsRecorder.new()
		add_child(stats)
		stats.setup(world, stats_opt if stats_opt is String else "")
	# Step 6: in --auto runs the human (a pilot, or an admiral, who has a
	# pilot record too) buys a Fighter and launches at once, unless a --bot
	# test script is flying the human itself. A spectator has no ship.
	if Game.opt("auto", false) and world.human != null and not Game.opt("bot"):
		world.human.buy_hull("fighter", world.teams[0])
		world.launch(world.human)
	# Step 7: one line about the match: the seat, the rule variants, and how
	# many rocks, ore nodes, monster camps and route-map points there are.
	print("match: role=%s variants=%s rocks=%d nodes=%d camps=%d route_nodes=%d" % [role, Game.variants, world.asteroids.pos.size(), world.nodes.size(), world.map.camps.size(), world.map.route.node_count()])


## Godot calls this every physics tick (normally 60 times a second). Count
## the tick for the reports (MainReport prints one every minute of match
## time), then stop the match when the --max-minutes limit is reached.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	# Step 1: count this tick; once a minute of match time, print a report.
	reports.count_tick(world)
	# Step 2: the --max-minutes limit: a last report, the SUMMARY, and quit.
	if max_minutes > 0.0 and world.time >= max_minutes * 60.0 and not _ended:
		_ended = true
		reports.print_minute(world)
		reports.print_summary(world, "time limit")
		if stats != null:
			stats.finish("time limit")
		get_tree().quit()


## Godot calls this every drawn frame. Refresh the plain text overlay, if
## it is shown (the text comes from MainDebugOverlay.text()).
func _process(_dt: float) -> void:
	if debug_label != null and world != null:
		debug_label.text = MainDebugOverlay.text(world)


## The match is over (Events.match_over, sent by MatchRules). `winner` is
## the winning team and `reason` says why. Print the last report and the
## SUMMARY once; then close the game in windowless or --all-ai runs (when
## a person is playing, the game stays open on the end screen).
func _on_match_over(winner: int, reason: String) -> void:
	# Step 1: only once (the time limit may have ended the run already).
	if _ended:
		return
	_ended = true
	# Step 2: the last report and the SUMMARY, such as "Halcyon wins: ...".
	reports.print_minute(world)
	reports.print_summary(world, "%s wins: %s" % [Rules.TEAM_NAMES[winner], reason])
	if stats != null:
		stats.finish("%s wins: %s" % [Rules.TEAM_NAMES[winner], reason])
	# Step 3: test runs stop here.
	if DisplayServer.get_name() == "headless" or Game.opt("all-ai", false):
		get_tree().quit()


## Godot sends here the key presses and clicks that no screen used. Only
## the plain text overlay uses this: F1 buys a Fighter if needed and
## launches. The real code is MainDebugOverlay.on_f1().
func _unhandled_input(event: InputEvent) -> void:
	# Step 1: only with the text overlay and a human pilot.
	if debug_label == null or world == null or world.human == null:
		return
	# Step 2: F1 (by its place on the keyboard) launches.
	if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F1:
		MainDebugOverlay.on_f1(world)
