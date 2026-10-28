extends Node
## WHAT THIS IS: the "team photo tour": a windowed run of a real match with the
## human on the team chosen with --team, that saves a few pictures of what the
## human sees, so a person can look at the side they play (the camera's start,
## the HUD colours, the minimap and fog, the Admiral board). It plays for about
## two minutes of match time, then quits.
##
## HOW IT WORKS: setup() waits for the HUD. A pilot is photographed in the open
## hangar first, then launches a Fighter, and a computer pilot brain (PilotAI)
## flies it from then on, so the match is alive around the pictures; an Admiral
## opens the board's Research and Build tabs, closes it, and the match goes on
## without orders. Each picture waits for a match time (PILOT_STEPS or
## ADMIRAL_STEPS: seconds since the match began, a name) and is saved as
## <role>_<name>.png in the --shots folder; headless, the same steps only print
## their names. The last picture is the start screen, shown on top of the HUD
## with the chosen team picked (it shows the colour the menus are highlighted in).
## After the last step it prints "team_shots: done (pilot)" or "(admiral)" and
## quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/; park the window off screen with --position):
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --role=pilot --team=vhorr --bot=team --test=team_shots --shots=<dir>
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --role=admiral --team=vhorr --bot=team --test=team_shots --shots=<dir>
## --bot=team keeps main.gd from launching the human's ship, because the tour
## launches it itself.
##
## WHO USES IT: main.gd loads it for --test=team_shots. It finds the node named
## "Hud" and calls Hud._toggle_board() and AdmiralBoard._set_tab(). It launches
## the human's ship and gives it a computer brain, so it is only for this tour.

## The start screen, shown once at the end of the tour (--auto runs never show
## it otherwise).
const START_SCENE := preload("res://scenes/ui/start_screen.tscn")
## The pilot's pictures: [match seconds, name]. The first is the open hangar
## before the launch.
const PILOT_STEPS := [[0.5, "00_hangar"], [1.5, "01_start"], [12.0, "02_flying"], [60.0, "03_one_minute"], [110.0, "04_nearly_two_minutes"], [111.0, "05_start_screen"]]
## The Admiral's pictures: [match seconds, name]. The first three are the
## camera's start and the board's two tabs, one second apart.
const ADMIRAL_STEPS := [[1.0, "01_start"], [2.0, "02_board_research"], [3.0, "03_board_build"], [60.0, "04_one_minute"], [110.0, "05_nearly_two_minutes"], [111.0, "06_start_screen"]]
## The match time at which the tour quits (seconds).
const END_AT := 113.0

## The running match (set by setup()).
var world: World
## The HUD, found once it exists.
var hud: Hud = null
## Where the pictures go (--shots, default the user data folder).
var dir := ""
## The index of the next step in the seat's list of pictures.
var _step := 0
## True while a picture is being taken.
var _busy := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)


## Godot calls this every drawn frame: once the HUD exists, take each picture when
## its match time comes, and quit at the end.
func _process(_dt: float) -> void:
	if world == null or _busy:
		return
	if hud == null:
		hud = get_tree().root.find_child("Hud", true, false) as Hud
		if hud == null:
			return
	if world.time >= END_AT:
		print("team_shots: done (%s)" % world.human_role)
		get_tree().quit()
		return
	var steps: Array = ADMIRAL_STEPS if world.human_role == "admiral" else PILOT_STEPS
	if _step < steps.size() and world.time >= float(steps[_step][0]):
		var shot_name := String(steps[_step][1])
		_step += 1
		_busy = true
		await _take(shot_name)
		# The pilot leaves the hangar for the sky once it has been photographed.
		if shot_name.contains("hangar"):
			_launch()
		_busy = false


## A pilot buys and launches a Fighter and hands it to a computer brain (an
## Admiral has nothing to launch). Called once the open hangar has been photographed.
func _launch() -> void:
	if world.human_role != "pilot" or world.human == null:
		return
	var h := world.human
	h.buy_hull("fighter", world.teams[h.team])
	var ship := world.launch(h)
	if ship == null:
		return
	var brain := PilotAI.new(world, h)
	world.pilot_ai[h] = brain
	ship.controller = brain
	hud._close_others(null)


## Take picture `shot_name`. An Admiral's board pictures open the board first and
## the "one minute" picture closes it; the last picture puts the start screen on
## top of the HUD.
func _take(shot_name: String) -> void:
	if shot_name.contains("start_screen"):
		hud.add_child(START_SCENE.instantiate())
		await get_tree().process_frame
	if world.human_role == "admiral":
		if shot_name.contains("board_research"):
			hud._toggle_board()
			hud.board._set_tab("Research")
		elif shot_name.contains("board_build"):
			hud.board._set_tab("Build")
		elif shot_name.contains("one_minute") and hud.board != null and hud.board.visible:
			hud._toggle_board()
	var headless := DisplayServer.get_name() == "headless"
	print("team_shots: %s at %s" % [shot_name, Util.clock(world.time)])
	if headless:
		return
	await RenderingServer.frame_post_draw
	var path := dir.path_join("%s_%s.png" % [world.human_role, shot_name])
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
