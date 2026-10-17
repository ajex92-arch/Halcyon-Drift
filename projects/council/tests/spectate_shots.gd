extends Node
## WHAT THIS IS: a spectator photo tour, run with a window. At each listed
## match time it points the camera at the busiest fight and saves a
## screenshot. It is for a visual review of combat, fog, effects and the
## HUD in a real AI match.
##
## HOW IT WORKS: for each time in --times, 1.5 game seconds early it finds
## the pilot ship with the most pilot ships and minions around it (within
## about 1,500 world units; 1 world unit is about one pixel at normal
## zoom), frees the camera from following anyone and points it there,
## zoomed so about 4,500 world units fit across the screen. At the time
## itself it waits for the frame to be drawn and saves it as a PNG. After
## the last picture it quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --path remake --resolution 1280x720 -- --all-ai --speed=3 --test=spectate_shots --shots=<dir> --times=120,240,360
## No --headless here: it needs a window to take pictures. --speed=3 runs
## the game 3 times faster. --shots is the folder for the pictures
## (default: Godot's user data folder). --times lists the match times in
## seconds (default 120,240,360).
##
## HOW TO READ THE OUTPUT: one line per picture, "shot <path>". The files
## are named spec_<number>_<match time>.png, for example
## spec_01_2m00.png for the first picture at 2:00.
##
## WHO USES IT: main.gd loads it for --test=spectate_shots (for
## --test=<name> it loads tests/<name>.gd, adds it after the World and
## calls setup()). It moves the World's CameraRig (free, look_at_point,
## target_zoom) and searches World.unit_hash.

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## The match times (seconds) to take pictures at, from --times.
var times: Array = []
## Which picture is next (an index into `times`); also the number of
## pictures taken so far.
var idx := 0
## True once the camera has been pointed for the next picture.
var aimed := false


## main.gd calls this once, right after the World is built. Read the
## folder and the times, and keep running even if the game is paused.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	for s in str(Game.opt("times", "120,240,360")).split(","):
		times.append(float(s))
	process_mode = Node.PROCESS_MODE_ALWAYS


## Godot calls this every drawn frame. Aim the camera 1.5 s before the next
## picture time, take the picture at that time, and quit after the last.
func _process(_dt: float) -> void:
	if world == null or idx >= times.size():
		return
	var at: float = times[idx]
	# Step 1: 1.5 s early, point a free camera at the busiest spot,
	# zoomed so about 4,500 world units fit across the screen.
	if not aimed and world.time >= at - 1.5:
		aimed = true
		var p := _busiest()
		world.camera.free = true
		world.camera.look_at_point(p)
		world.camera.global_position = p
		world.camera.target_zoom = get_viewport().get_visible_rect().size.x / 4500.0
	# Step 2: on time, wait until the frame has been drawn, then save it
	# (":" in the clock becomes "m", since file names can't hold ":").
	if aimed and world.time >= at:
		idx += 1
		aimed = false
		await RenderingServer.frame_post_draw
		var path := dir.path_join("spec_%02d_%s.png" % [idx, Util.clock(world.time).replace(":", "m")])
		get_viewport().get_texture().get_image().save_png(path)
		print("shot ", path)
		# Step 3: that was the last picture: quit.
		if idx >= times.size():
			get_tree().quit()


## Centre of the densest knot of pilot ships and minions.
## For every living pilot ship, count the live pilot ships and minions the
## spatial hash (a grid that finds nearby units quickly) gives back within
## about 1,500 world units of it (a grid search, so a few slightly farther
## ones can count). The ship with the most wins. If there are no pilot
## ships, it is Aurelian's mothership's position.
func _busiest() -> Vector2:
	var best := world.mothership(0).global_position
	var best_n := -1
	var scratch: Array = []
	for s: Ship in world.ships:
		if not s.alive:
			continue
		var n := 0
		for u: Unit in world.unit_hash.query(s.global_position, 1500.0, scratch):
			if u.alive and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION):
				n += 1
		if n > best_n:
			best_n = n
			best = s.global_position
	return best
