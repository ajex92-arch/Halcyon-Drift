extends Node
## WHAT THIS IS: a check for the zoom_max variant (idea E6 of the
## combat_roles fork). It flies the human's Fighter, asks the camera how far
## it may zoom out, pushes the camera to its limit and prints what happened.
##
## HOW IT WORKS: main.gd (with --auto --role=pilot and no --bot) buys and
## launches a Fighter for the human. After half a second this test reads the
## camera's zoom limits (CameraRig.zoom_limits(): the most zoomed-out value
## first), tells the camera to zoom out as far as it can, waits two seconds
## and prints one line, "ZOOM_CHECK ...": the limit, the zoom reached, how
## many world units fit across the screen at that zoom and the usage counter
## "zoom_wide_frames". With the variant off the width is 5,200 (a small
## ship); "wide" gives 7,800 and "xwide" 10,400.
##
## HOW TO RUN IT:
##   godot --headless --path forks/combat_roles --fixed-fps 60 -- --auto --role=pilot --no-pilots --no-admiral-ai --test=zoom_check --variant=zoom_max:wide
##
## Windowed (not headless) and with --shots=<folder> it also saves the
## screenshot zoom_<off|wide|xwide>.png there: run it once per value for the
## picture pair (godot --path forks/combat_roles --resolution 1280x720 --
## --auto --role=pilot --no-pilots --no-admiral-ai --test=zoom_check
## --shots=<folder> --variant=zoom_max:wide).
##
## WHO USES IT: the combat_roles build report quotes its output.

## The running match (set by setup()).
var world: World
## Seconds since the test started.
var t := 0.0


## main.gd calls this once, right after the World is built. With no human
## pilot (the queue always runs with --all-ai, a spectator), make one: a
## Fighter flown by a made-up human profile, and the camera in follow mode.
func setup(w: World) -> void:
	world = w
	if world.human == null:
		var p := PilotProfile.new("zoom-check", Rules.HALCYON, 0, true)
		world.profiles.append(p)
		world.human = p
		p.buy_hull("fighter", world.teams[Rules.HALCYON])
		world.launch(p)
		world.camera.free = false


## Godot calls this every tick: at 0.5 s push the camera outwards, at 2.5 s
## print the result and quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	t += dt
	if t >= 0.5 and t < 0.5 + dt:
		world.camera.target_zoom = 0.0001
	if t >= 2.5:
		# Windowed runs with --shots=<folder> also save the picture at the
		# widest zoom: zoom_<variant>.png (run it once with the variant off
		# and once with wide / xwide to get the pair).
		if Game.opt("shots") != null and DisplayServer.get_name() != "headless":
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/zoom_%s.png" % [str(Game.opt("shots")), Game.variant("zoom_max")])
		var lim := world.camera.zoom_limits()
		var vw := world.camera.get_viewport_rect().size.x
		print("ZOOM_CHECK followed=%s limit=%.4f zoom=%.4f width_at_zoom=%d usage=%s" % [world.camera.followed() != null, lim.x, world.camera.zoom.x, int(vw / world.camera.zoom.x), JSON.stringify(Game.usage)])
		# The queue (run_batch.ps1) counts a PROBE_JSON line as a result.
		print("PROBE_JSON %s" % JSON.stringify({"test": "zoom_check", "width_at_zoom": int(vw / world.camera.zoom.x), "usage": Game.usage}))
		get_tree().quit()
