extends Node
## WHAT THIS IS: a photo tour of the first minion waves, run with a window
## (added for T-07, the smaller waves). At each listed
## match time it takes one picture per lane: the camera is pointed at
## Aurelian's wave on that lane and zoomed in so the ships of the wave can
## be told apart. It is for looking at what a wave is made of and how the
## minions are drawn.
##
## HOW IT WORKS: the pictures are taken one second of match time apart, the
## lanes in the order top, mid, bot. For each one, 0.5 game seconds early, it
## finds the front of Aurelian's wave on the lane (the live minion furthest
## down the lane), takes the middle of the Aurelian minions of that lane
## within WAVE_SPREAD of it, frees the camera from following anyone and
## points it there, zoomed so about VIEW_WIDTH world units fit across the
## screen (1 world unit is about one pixel at normal zoom). The camera's own
## per-frame work is switched off until the picture is saved, as in
## spectate_shots. At the time itself it waits for the frame to be drawn and
## saves it as a PNG. After the last picture it quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --path remake --resolution 1280x720 -- --all-ai --speed=2 --test=wave_shots --shots=<dir> --times=72
## No --headless here: it needs a window to take pictures. --shots is the
## folder for the pictures (default: Godot's user data folder). --times lists
## the match times in seconds of the first picture of each round (default
## 72: the first wave left at 45 s and is on its way down the lane).
##
## HOW TO READ THE OUTPUT: "shot <path>" for each picture; the files are
## named wave_<match time>_<lane>.png, for example wave_01m12_top.png. Then
## "view <lane> at <match time>: camera (x, y), N minions in view (C corvettes,
## F fighters, B bombers)", what the picture shows: the Aurelian ones and the
## Vhorr ones together. A picture with no minion in it is a failure and is
## followed by "FAIL wave shot ...". The last line is "wave_shots: done N
## pictures, F failures".
##
## WHO USES IT: main.gd loads it for --test=wave_shots. It moves the World's
## CameraRig (free, look_at_point, target_zoom, zoom, set_process) and reads
## World.minions; it changes nothing in the match.

## How many world units fit across the picture (the zoom).
const VIEW_WIDTH := 2400.0
## Aurelian minions of the lane this close to the wave's front minion (world
## units) are the wave; the picture is centred on their middle.
const WAVE_SPREAD := 1800.0

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots).
var dir := ""
## The pictures to take, in order: each [match time, lane id].
var _shots: Array = []
## Which picture is next (an index into _shots); also the number taken so far.
var _idx := 0
## True once the camera has been pointed for the next picture.
var _aimed := false
## How many pictures had no minion in view.
var _failures := 0


## main.gd calls this once, right after the World is built. Read the folder
## and the times, list the pictures and keep running even if the game is
## paused.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(dir)
	for s in str(Game.opt("times", "72")).split(","):
		var t := float(s)
		for i in MapLayout.LANE_ORDER.size():
			_shots.append([t + float(i), MapLayout.LANE_ORDER[i]])
	process_mode = Node.PROCESS_MODE_ALWAYS


## Godot calls this every drawn frame. Aim the camera 0.5 s before the next
## picture, take the picture at its time, and quit after the last.
func _process(_dt: float) -> void:
	if world == null or _idx >= _shots.size():
		return
	var at: float = _shots[_idx][0]
	var lane: String = _shots[_idx][1]
	# Step 1: point a free camera at the lane's wave.
	if not _aimed and world.time >= at - 0.5:
		_aimed = true
		var p := _wave_centre(lane)
		var z := get_viewport().get_visible_rect().size.x / VIEW_WIDTH
		world.camera.free = true
		world.camera.set_process(false)
		world.camera.look_at_point(p)
		world.camera.global_position = p
		world.camera.target_zoom = z
		world.camera.zoom = Vector2(z, z)
	# Step 2: on time, wait for the frame, then save it (":" in the clock
	# becomes "m", since file names can't hold ":").
	if _aimed and world.time >= at:
		_idx += 1
		_aimed = false
		await RenderingServer.frame_post_draw
		var clock := Util.clock(world.time).replace(":", "m")
		var path := dir.path_join("wave_%s_%s.png" % [clock, lane])
		get_viewport().get_texture().get_image().save_png(path)
		print("shot ", path)
		# Step 3: say what the picture shows; one without a minion in it is a
		# failure. Then give the camera its own work back.
		var seen := _in_view()
		world.camera.set_process(true)
		print("view %s at %s: camera %s, %d minions in view (%d corvettes, %d fighters, %d bombers)" % [lane, Util.clock(world.time), world.camera.global_position, seen[0], seen[1], seen[2], seen[3]])
		if int(seen[0]) == 0:
			_failures += 1
			print("FAIL wave shot %s at %s: no minion in view" % [lane, Util.clock(world.time)])
		# Step 4: that was the last picture: quit.
		if _idx >= _shots.size():
			print("wave_shots: done %d pictures, %d failures" % [_idx, _failures])
			get_tree().quit()


## The middle of Aurelian's wave on `lane`: the front minion is the live
## Aurelian minion of the lane furthest down it; the middle is the average
## spot of the Aurelian minions of the lane within WAVE_SPREAD of it. With
## no minion out, the lane's first point.
func _wave_centre(lane: String) -> Vector2:
	var pts := MapLayout.lane_points(lane, 0)
	var front: Minion = null
	var front_s := -1.0
	for m: Minion in world.minions:
		if m.team == 0 and m.alive and m.lane == lane:
			var s := float(Util.project_on_polyline(m.global_position, pts)["s"])
			if s > front_s:
				front_s = s
				front = m
	if front == null:
		return pts[0]
	var sum := Vector2.ZERO
	var n := 0
	for m: Minion in world.minions:
		if m.team == 0 and m.alive and m.lane == lane and m.global_position.distance_to(front.global_position) <= WAVE_SPREAD:
			sum += m.global_position
			n += 1
	return sum / float(n)


## What the picture shows: the live minions whose spot is inside the part of
## the world the camera shows now, as [all minions, corvettes, fighters,
## bombers].
func _in_view() -> Array:
	var half := get_viewport().get_visible_rect().size / world.camera.zoom.x * 0.5
	var centre := world.camera.global_position
	var seen := [0, 0, 0, 0]
	for m: Minion in world.minions:
		if not m.alive or absf(m.global_position.x - centre.x) > half.x or absf(m.global_position.y - centre.y) > half.y:
			continue
		seen[0] += 1
		match m.mtype:
			"corvette":
				seen[1] += 1
			"fighter":
				seen[2] += 1
			"bomber":
				seen[3] += 1
	return seen
