class_name GalleryScene
extends RefCounted
## WHAT THIS IS: the staged fight pictures of the hull gallery (tests/hull_gallery.gd
## with --scene). The real AI match runs, and then both teams' mothership, a point-defense
## tower, a torpedo tower and a Repair Bay are put side by side in one view with
## minions and pilot ships fighting between them, so the new drawings of the
## structures can be judged at the zooms a player really has, next to real bolts,
## torpedoes and flames. The fight is real (the match engine runs it), the places of
## the structures are staged: in a real match they are many thousand world units
## apart.
##
## HOW IT WORKS: it waits until the match clock has reached --scene-start seconds
## (default 60, so the first waves and the AI pilots are out), gives both teams all
## their Flagship research and Bay Defenses (so every gun spot of the mothership
## and the bay has its head), hides the HUD, and builds the scene round a spot above
## the middle of the map (clear of the Crossing): the Aurelian mothership at the west end facing east, the Vhorr one at the
## east end facing west, and for each team a point-defense tower, a torpedo tower and a
## Repair Bay between them (the towers turned away from their own mothership, as a
## tower stands on its node), then minions of both teams in the middle and up to
## three pilot ships of each team moved into the fight. It lets the match run for
## --scene-frames drawn frames (default 150), stops it, and saves three pictures of
## that instant: scene_play.png at the play zoom (4,500 world units across), scene_near.png
## and scene_near_vhorr.png (2,250 across, on the Aurelian and the Vhorr side), scene_far.png
## at a capital's far zoom (0.13).
##
## WHO USES IT: tests/hull_gallery.gd makes one (GalleryScene.new(self)) for --scene and
## calls scene(). It uses the gallery's world, dir, count and wait_frames().

## The match time (seconds) when the scene is built, unless --scene-start says otherwise.
const START := 60.0
## Frames the fight plays after the scene is built, unless --scene-frames says otherwise.
const FRAMES := 150
## How far (world units) the scene is put above the map's middle (the Crossing), so the
## ore nodes and the Crossing's rings are not in it.
const MID_UP := 1700.0
## How far (world units) each mothership stands from the middle of the scene.
const MS_X := 1250.0
## The width (world units across the screen) of the play-zoom picture.
const PLAY_VIEW := 4500.0
## The width of the near picture.
const NEAR_VIEW := 2250.0
## The zoom of the far picture: a capital's furthest zoom (CameraRig).
const FAR_ZOOM := 0.13

## The hull gallery test that owns this part.
var gallery: Node


## Remember the gallery that made us.
func _init(g: Node) -> void:
	gallery = g


## Build the scene, let the fight play, save the pictures.
func scene() -> void:
	var world: World = gallery.world
	world.camera.free = true
	var start := float(Game.opt("scene-start", START))
	while world.time < start:
		await gallery.get_tree().process_frame
	var hud := gallery.get_tree().root.find_child("Hud", true, false)
	if hud != null:
		hud.visible = false
	var mid := Vector2(MapLayout.CX, MapLayout.H * 0.5 - MID_UP)
	_stage(world, mid)
	await gallery.wait_frames(int(Game.opt("scene-frames", FRAMES)))
	world.set_physics_process(false)
	world.camera.set_process(false)
	await _shot(world, mid, PLAY_VIEW, 0.0, "scene_play")
	await _shot(world, mid + Vector2(-800.0, 0.0), NEAR_VIEW, 0.0, "scene_near")
	await _shot(world, mid + Vector2(800.0, 0.0), NEAR_VIEW, 0.0, "scene_near_vhorr")
	await _shot(world, mid, 0.0, FAR_ZOOM, "scene_far")
	print("hull_gallery: done %d scene pictures" % 4)


## Put the scene together round `mid`.
func _stage(world: World, mid: Vector2) -> void:
	# Step 1: all the research, so every gun spot has a gun.
	for t in 2:
		var ts: TeamState = world.teams[t]
		ts.ms_pd = 4
		ts.ms_flak = 4
		ts.ms_heavy = 4
		ts.ms_ion = 1
		ts.bay_defenses = true
		MothershipGuns.apply_upgrades(world.mothership(t), ts)
	# Step 2: the two motherships at the ends, nose to nose.
	for t in 2:
		var side := -1.0 if t == Rules.HALCYON else 1.0
		var ms := world.mothership(t)
		ms.global_position = mid + Vector2(side * MS_X, 0.0)
		ms.rotation = 0.0 if t == Rules.HALCYON else PI
		ms.move_target = Vector2.INF
	# Step 3: the towers and the bay of each team, between the motherships, the
	# towers turned away from their own mothership.
	for t in 2:
		var side := -1.0 if t == Rules.HALCYON else 1.0
		var turn := 0.0 if t == Rules.HALCYON else PI
		var pd := world.spawn_turret(t, world.nodes[t], 0, "pd", true)
		pd.global_position = mid + Vector2(side * 420.0, -560.0)
		pd.rotation = turn
		var torp := world.spawn_turret(t, world.nodes[t], 1, "torp", true)
		torp.global_position = mid + Vector2(side * 420.0, 560.0)
		torp.rotation = turn
		var bay := world.spawn_bay(t, mid + Vector2(side * 250.0, -300.0))
		bay.global_position = bay.anchor
		bay.rotation = turn
		bay.state = "anchored"
	# Step 4: a fight in the middle: minions of both teams, pilot ships moved in.
	var kinds: Array = Minions.TYPES.keys()
	for t in 2:
		var side := -1.0 if t == Rules.HALCYON else 1.0
		for i in 6:
			var at := mid + Vector2(side * (60.0 + 90.0 * floorf(float(i) / 2.0)), (float(i % 2) - 0.5) * 360.0)
			world.spawn_minion(t, str(kinds[i % kinds.size()]), "mid", at)
		var moved := 0
		for s: Ship in world.ships:
			if s.team == t and s.alive and moved < 3:
				s.global_position = mid + Vector2(side * (320.0 + 160.0 * float(moved)), (float(moved) - 1.0) * 420.0)
				s.velocity = Vector2.ZERO
				moved += 1


## Save one picture: the camera at `at`, `view` world units across (or, when
## `view` is 0, at zoom `zoom`), as `file`.png in the gallery's folder.
func _shot(world: World, at: Vector2, view: float, zoom: float, file: String) -> void:
	var z := zoom if view <= 0.0 else gallery.get_viewport().get_visible_rect().size.x / view
	world.camera.global_position = at
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)
	await gallery.wait_frames(20)
	await RenderingServer.frame_post_draw
	var path: String = gallery.dir.path_join(file + ".png")
	gallery.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	gallery.count += 1
