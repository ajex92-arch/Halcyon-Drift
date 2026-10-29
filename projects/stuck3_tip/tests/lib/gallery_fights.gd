class_name GalleryFights
extends RefCounted
## WHAT THIS IS: the in-match pictures of the hull gallery (tests/hull_gallery.gd
## with --fights). It plays a real AI match and, whenever both teams are in a
## big fight, photographs the fight twice (wide, then closer), so the Cinder
## alien look can be judged where it counts: in the game itself, with the
## screens, the shield arcs and the other team next to it.
##
## HOW IT WORKS: every FIGHT_CHECK frames it looks at the surroundings of every
## living pilot ship (the units within FIGHT_RADIUS world units). Each team's
## "strength" there is 3 for every pilot ship and 1 for every minion, and the
## fight's score is the weaker team's strength, so only a spot with BOTH teams
## in it scores. The best-scoring spot is "the fight". When its score is at
## least MIN_SCORE (plus SCORE_STEP for every fight already photographed), and
## COOLDOWN seconds of match time have passed since the last pictures, the
## camera goes to the middle of the units there and the wide
## picture (WIDE_VIEW world units across the screen) and then the near one
## (NEAR_VIEW) are saved, both of the same instant: the match stands still
## until both are saved (each picture waits several drawn frames, which at
## --speed=4 on a slow PC are several match seconds, and a fight is gone by
## then). It stops after --fights-n fights (default 5) or at
## --secs of match time (default 900), whichever comes first.
##
## WHO USES IT: tests/hull_gallery.gd makes one (GalleryFights.new(self)) for
## --fights and calls fights(). It uses the gallery's world, dir, count and
## wait_frames().

## Frames between two looks for a fight (60 frames are a second at 60 frames
## per second).
const FIGHT_CHECK := 120
## How far round a pilot ship (world units) the units of a fight are counted.
const FIGHT_RADIUS := 1000.0
## The least score the first fight needs to be photographed, for example two
## pilot ships and three minions of each team.
const MIN_SCORE := 9
## How much more score each later fight needs than the one before, so the
## pictures show bigger and bigger fights and not the first clash again and
## again.
const SCORE_STEP := 4
## Seconds of match time between two photographed fights.
const COOLDOWN := 100.0
## How wide (world units across the screen) the wide picture is.
const WIDE_VIEW := 4500.0
## How wide (world units across the screen) the near picture is.
const NEAR_VIEW := 2200.0

## The hull gallery test that owns this part.
var gallery: Node


## Remember the gallery that made us.
func _init(g: Node) -> void:
	gallery = g


## Play the match, photograph its big fights, and print how many pictures were
## taken.
func fights() -> void:
	var secs := float(Game.opt("secs", 900.0))
	var want := int(Game.opt("fights-n", 5))
	var world: World = gallery.world
	world.camera.free = true
	var taken := 0
	var last := -COOLDOWN
	var frame := 0
	while taken < want and world.time < secs:
		await gallery.get_tree().process_frame
		frame += 1
		if frame % FIGHT_CHECK != 0 or world.time - last < COOLDOWN:
			continue
		var fight := _hottest(world)
		if int(fight[0]) < MIN_SCORE + SCORE_STEP * taken:
			continue
		last = world.time
		taken += 1
		print("fight %d at %s: score %d, middle %s" % [taken, Util.clock(world.time), int(fight[0]), fight[1]])
		await _photograph(world, fight[1], taken)
	print("hull_gallery: done %d fights, %d pictures, match time %s" % [taken, taken * 2, Util.clock(world.time)])


## The hottest fight right now: [score, middle of its units]. Score 0 means no
## spot has both teams in it.
func _hottest(world: World) -> Array:
	var best := 0
	var middle := Vector2.ZERO
	var scratch: Array = []
	for s: Ship in world.ships:
		if not s.alive:
			continue
		var strength := [0, 0]
		var sum := Vector2.ZERO
		var n := 0
		for obj in world.unit_hash.query(s.global_position, FIGHT_RADIUS, scratch):
			# A unit freed this frame can still be in the grid.
			if not is_instance_valid(obj):
				continue
			var u: Unit = obj
			if not u.alive or (u.kind != Unit.K_SHIP and u.kind != Unit.K_MINION) or u.team > 1:
				continue
			strength[u.team] += 3 if u.kind == Unit.K_SHIP else 1
			sum += u.global_position
			n += 1
		var score := mini(int(strength[0]), int(strength[1]))
		if score > best:
			best = score
			middle = sum / float(n)
	return [best, middle]


## Save the wide and the near picture of the fight at `at` (fight number
## `number`): the camera is put there and the zoom set by hand (the camera's
## own per-frame work is off meanwhile: left to itself, the free camera pans
## toward a corner of the map when the game window does not have the mouse
## over it), a third of a second is waited so the frame is drawn, and the frame
## saved as fight_<number>_<match time>_wide.png / _near.png (the same match
## time in both names, because the match is frozen until both are saved).
func _photograph(world: World, at: Vector2, number: int) -> void:
	# Both pictures are of the same instant: the match stands still (its tick
	# is off, as in the frozen hull gallery) until both are saved.
	world.set_physics_process(false)
	world.camera.set_process(false)
	var clock := Util.clock(world.time).replace(":", "m")
	for view: float in [WIDE_VIEW, NEAR_VIEW]:
		var z: float = gallery.get_viewport().get_visible_rect().size.x / view
		world.camera.global_position = at
		world.camera.target_zoom = z
		world.camera.zoom = Vector2(z, z)
		await gallery.wait_frames(20)
		await RenderingServer.frame_post_draw
		var file := "fight_%02d_%s_%s.png" % [number, clock, "wide" if view == WIDE_VIEW else "near"]
		var path: String = gallery.dir.path_join(file)
		gallery.get_viewport().get_texture().get_image().save_png(path)
		print("shot ", path)
		gallery.count += 1
	world.camera.set_process(true)
	world.set_physics_process(true)
