extends Node
## WHAT THIS IS: the hull gallery, a windowed picture test. It puts every
## kind of unit of both teams side by side, Aurelian (amber) on the left and
## Cinder (red) on the right, on the game's own background, and saves PNG
## pictures of them: one close-up per unit type, and "play zoom" and "far"
## pictures that line all the types up at the sizes you really see in a
## match. It is for judging the Cinder alien look. It also checks the Cinder
## shape tables and the Aurelian minion outlines (see GalleryChecks.run()). Run with --bench instead and it measures
## what the drawing costs per frame; with --live it does that in a real match
## (see GalleryMeasure); with --check it only does the shape checks (that works without
## a window, like the other pass/fail tests); with --fights it plays a real
## match and photographs its biggest fights (see GalleryFights).
##
## HOW IT WORKS: it builds the normal match, then freezes it (the match
## clock stops, nothing moves or shoots) and hides the screens, the rocks and
## the ore nodes. Then it makes one of every unit type for each team (the
## pilot ships through the real hangar, the others through the real
## spawner), so what you see is drawn by the real ShipVisual and UnitVisual.
## For each picture it parks the units of the picture where they belong,
## points the camera, writes the names with Label nodes, waits half a second
## so the engine flames fill in, and saves the frame.
##   - close-ups: the camera is zoomed far in (further than the game allows),
##     so the shapes can be judged; each file holds one unit type, both teams.
##   - play zoom: 4,500 world units across the screen (the zoom of the
##     spectate_shots tour), where small ships are only a dozen pixels long.
##   - mid and near: 2,200 across and 1,100 across (the closest a pilot can
##     zoom in, CameraRig.MIN_VIEW_WIDTH), for the small ships and units: they
##     only get big enough to see in detail when zoomed in this far.
##   - far: 12,000 across (the admiral's overview), where every ship is at its
##     minimum size.
## --bench: instead of pictures, 70 ships and 70 minions per team are spread
## over a play-zoom view and the frame time is printed for the three ways of
## drawing them: Aurelian only, Cinder alien, Cinder plain (the old
## outlines), with the game's own frame work and the number of draw calls.
## --bench --bench-parts (the draw-cost table): the same crowd and looks,
## measured once per parts switch set of DrawParts: every part drawn, each part
## (flames, arcs, arrow, bars, name, outline, redraw) left out alone, the six
## drawn parts left out together (the redraw stays), all left out, and an empty
## scene (every unit hidden: what the rest of the scene costs). What a part
## costs is the difference to "every part drawn". The reference crowd stands
## still, so it draws no flames and (at play zoom) no bars or name: add
## --bench-busy (the ships drift, burn their engines and the minions are hurt,
## like a fight) and, for the bars and names, --bench-view=2200. The drift arrow
## belongs to the human's ship alone, so this all-AI crowd never draws one. The
## other options: --bench-rounds=N, --bench-frames=N. See GalleryMeasure and
## tools/draw_cost_table.py. The same switches work in any run through
## --bench-off=<parts> (read once by DrawParts, listed in scripts/autoload/game.gd):
## for example --bench --bench-off=arcs draws the three looks without the shield
## arcs (not with redraw: the looks would keep the previous look's picture).
## --fights: instead of the frozen units, the real match runs (everything on,
## the screens too) and whenever both teams are in a big fight the camera goes
## there and saves a wide and a near picture of it, so the look can be judged
## in the game itself.
## --scene: the real match runs to --scene-start seconds, then both teams' mothership,
## towers and Repair Bay are staged in one view with a fight round them and three
## pictures are saved (scene_play.png, scene_near.png, scene_far.png; see GalleryScene).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --path remake --resolution 1920x1080 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hull_gallery --shots-dir=<folder>
##   godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hull_gallery --bench
##   godot --path remake --resolution 1920x1080 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hull_gallery --bench --bench-parts --bench-busy
##   godot --path remake --resolution 1920x1080 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --all-ai --test=hull_gallery --live --secs=480
##   godot --path remake --resolution 1920x1080 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --all-ai --speed=3 --test=hull_gallery --fights --secs=1500 --shots-dir=<folder>
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hull_gallery --check
## The first five need a window (no --headless); --position 30000,30000 puts
## it far off the screen so nothing pops up (the frames are still drawn and
## saved). --shots-dir is the folder for the pictures (default: Godot's user
## data folder).
##
## HOW TO READ THE OUTPUT: first the checks ("cinder polygons: N checked, 0
## cannot be filled", "cinder sizes: N shapes checked, 0 outside 10% ..." and
## "minion looks: N outlines checked, 0 not plain"),
## then one "shot <path>" line per picture and "hull_gallery: done N pictures"
## (with --bench, three "bench ..." lines instead; with --bench --bench-parts, one
## "DRAWCOST ..." line per measurement and a "bench-parts ..." summary per look and
## switch set; with --live, two "live ..." lines; with --check, only
## "hull_gallery checks: N failures", where 0 means every check passed; with
## --fights, "shot <path>" lines and "hull_gallery: done N fights, ...").
## The files are close_01_scout.png ... close_20_mothership.png, play_ships.png,
## play_big_ships.png, play_units.png, play_mothership.png, mid_ships.png,
## mid_units.png, near_ships.png, near_units.png, far_ships.png and far_units.png
## (and with --fights fight_<n>_<match time>_wide.png and _near.png).
##
## WHO USES IT: main.gd loads it for --test=hull_gallery (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()). It
## builds ships with World.launch() and units with World.spawn_*(), moves the
## CameraRig. It starts every run with GalleryChecks (tests/lib/gallery_checks.gd),
## and hands --bench and --live to GalleryMeasure (tests/lib/gallery_measure.gd,
## which flips CinderPaint.set_alien()) and --fights to GalleryFights
## (tests/lib/gallery_fights.gd).
## The Aurelian steel hulls and the turrets are checked by GalleryAurelian
## (tests/lib/gallery_aurelian.gd, part of every run), the drawings of the
## mothership, the lane towers and the Repair Bay by GalleryStructures
## (tests/lib/gallery_structures.gd, part of every run), the turret silhouettes are
## shown by GalleryTurrets (tests/lib/gallery_turrets.gd, turret_sheet.png), the
## options of the Scout and the Support Corvette that the game does not use (and
## the new Fighter) by GalleryOptions (tests/lib/gallery_options.gd, the last
## picture, options_sheet.png), and --bench-look=steel and --live-look=steel
## (GalleryMeasure.bench_steel() and live_steel()) measure the steel hulls and the
## turrets against the plain old look: godot ... --test=hull_gallery --bench --bench-look=steel
## (1280x720) and godot ... -- --all-ai --test=hull_gallery --live --live-look=steel --secs=480.

## The unit types, in picture order: [file name, unit key, title]. A key is
## "ship:<hull id>", "minion:<type>", "mining_drone", "repair_drone", "ward",
## "turret:<type>", "bay" or "mother".
const TYPES := [
	["scout", "ship:scout", "Scout"], ["fighter", "ship:fighter", "Fighter"], ["lance", "ship:lance", "Lance Fighter"],
	["bomber", "ship:bomber", "Bomber"], ["logistics", "ship:logistics", "Logistics Corvette"],
	["support", "ship:support", "Support Corvette"], ["flak", "ship:flak", "Flak Frigate"], ["ion", "ship:ion", "Ion Frigate"],
	["destroyer", "ship:destroyer", "Destroyer"], ["battlecruiser", "ship:battlecruiser", "Battlecruiser"],
	["minion_fighter", "minion:fighter", "Snub-Fighter (minion)"], ["minion_bomber", "minion:bomber", "Light Bomber (minion)"],
	["minion_corvette", "minion:corvette", "Patrol Leader (minion)"], ["mining_drone", "mining_drone", "Mining Drone"],
	["repair_drone", "repair_drone", "Repair Drone"], ["ward", "ward", "Ward"], ["turret_pd", "turret:pd", "PD Turret"],
	["turret_torp", "turret:torp", "Torpedo Turret"], ["repair_bay", "bay", "Repair Bay"], ["mothership", "mother", "Mothership"],
]
## The rows of the lineup pictures: lineup name -> rows, each a list of unit
## keys laid out left to right. The "mid_" and "near_" ones hold only what fits
## on the screen at those closer views. "big_ships" holds the two capitals,
## which fill a row of the play view by themselves, and "all_ships" is every
## ship at once, for the far view.
const LINEUPS := {
	"ships": [["ship:scout", "ship:fighter", "ship:lance", "ship:bomber", "ship:logistics", "ship:support"],
		["ship:flak", "ship:ion"]],
	"big_ships": [["ship:destroyer", "ship:battlecruiser"]],
	"all_ships": [["ship:scout", "ship:fighter", "ship:lance", "ship:bomber", "ship:logistics", "ship:support"],
		["ship:flak", "ship:ion", "ship:destroyer", "ship:battlecruiser"]],
	"units": [["minion:fighter", "minion:bomber", "minion:corvette", "mining_drone", "repair_drone", "ward"],
		["turret:pd", "turret:torp", "bay"]],
	"mothership": [["mother"]],
	"mid_ships": [["ship:scout", "ship:fighter", "ship:lance", "ship:bomber", "ship:logistics", "ship:support"], ["ship:flak", "ship:ion"]],
	"near_ships": [["ship:scout", "ship:fighter", "ship:lance", "ship:bomber", "ship:logistics", "ship:support"]],
}
## Seconds of waiting after the camera moves, so the flames fill in.
const SETTLE := 0.5
## The width (world units) of the play-zoom view (the zoom of the spectate_shots tour).
const PLAY_VIEW := 4500.0
## The width (world units) of the far (overview) view, where every ship is at its
## minimum size.
const FAR_VIEW := 12000.0
## The width of the mid view: between the play view and the closest one.
const MID_VIEW := 2200.0
## The width of the near view: the closest a pilot can zoom in.
const NEAR_VIEW := CameraRig.MIN_VIEW_WIDTH
## The lineup pictures, in the order they are taken: [lineup name in LINEUPS,
## the view's width in world units, file name].
const PICTURES := [
	["ships", PLAY_VIEW, "play_ships"], ["big_ships", PLAY_VIEW, "play_big_ships"], ["units", PLAY_VIEW, "play_units"],
	["mothership", PLAY_VIEW, "play_mothership"],
	["mid_ships", MID_VIEW, "mid_ships"], ["units", MID_VIEW, "mid_units"],
	["near_ships", NEAR_VIEW, "near_ships"], ["units", NEAR_VIEW, "near_units"],
	["all_ships", FAR_VIEW, "far_ships"], ["units", FAR_VIEW, "far_units"],
]

## The running match (set by setup()).
var world: World
## The folder the pictures go into (--shots-dir).
var dir := ""
## The centre of the gallery on the map (open jungle, between the lanes).
var home := Vector2.ZERO
## The units: units[team] is a dictionary from unit key to the unit.
var units: Array = [{}, {}]
## The layer the names are written on.
var labels: CanvasLayer
## How many pictures were saved.
var count := 0


## main.gd calls this once, right after the World is built. Freeze the match,
## hide what would get in the way, and start the run on the next frame.
func setup(w: World) -> void:
	world = w
	dir = str(Game.opt("shots-dir", Game.opt("shots", OS.get_user_data_dir())))
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# --live, --fights and --scene use a real match: leave everything running.
	if Game.opt("live", false) or Game.opt("fights", false) or Game.opt("scene", false):
		_run.call_deferred()
		return
	# Nothing moves, shoots or is rebuilt: the match clock is stopped.
	world.set_physics_process(false)
	world.camera.set_process(false)
	world.get_node("Asteroids").visible = false
	world.get_node("Nodes").visible = false
	world.get_node("FogView").visible = false
	var hud := get_tree().root.find_child("Hud", true, false)
	if hud != null:
		hud.visible = false
	home = Vector2(MapLayout.CX, MapLayout.H * 0.3)
	labels = CanvasLayer.new()
	labels.layer = 20
	add_child(labels)
	_run.call_deferred()


## The whole run: check the shapes, make the units, take the pictures (or
## measure), quit. With --check it stops after the shape checks; --live and
## --fights hand the real match to GalleryMeasure and GalleryFights instead.
func _run() -> void:
	await wait_frames(5)
	if Game.opt("live", false):
		if str(Game.opt("live-look", "")) == "steel":
			await GalleryMeasure.new(self).live_steel(PLAY_VIEW)
		else:
			await GalleryMeasure.new(self).live(PLAY_VIEW)
		get_tree().quit()
		return
	if Game.opt("fights", false):
		await GalleryFights.new(self).fights()
		get_tree().quit()
		return
	if Game.opt("scene", false):
		await GalleryScene.new(self).scene()
		get_tree().quit()
		return
	var failures := GalleryChecks.run()
	failures += GalleryAurelian.run()
	failures += GalleryStructures.run()
	if Game.opt("check", false):
		print("hull_gallery checks: %d failures" % failures)
		get_tree().quit()
		return
	_make_units()
	await wait_frames(5)
	if Game.opt("bench", false):
		if Game.opt("bench-parts", false):
			await GalleryMeasure.new(self).bench_parts(PLAY_VIEW)
		elif str(Game.opt("bench-look", "")) == "steel":
			await GalleryMeasure.new(self).bench_steel(PLAY_VIEW)
		else:
			await GalleryMeasure.new(self).bench(PLAY_VIEW)
	else:
		for i in TYPES.size():
			await _close_up(i)
		for pic: Array in PICTURES:
			await _lineup(str(pic[0]), float(pic[1]), str(pic[2]))
		await GalleryTurrets.sheet(self, "turret_sheet")
		await GalleryOptions.sheet(self, "options_sheet")
		print("hull_gallery: done %d pictures" % count)
	get_tree().quit()


## Wait `n` drawn frames.
func wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


# --- the units ---------------------------------------------------------------------------------

## Make one of every unit type for both teams (see the key list at the top).
## They are made the normal way and then moved by hand; the match is frozen,
## so they stay where they are put.
func _make_units() -> void:
	for t in 2:
		var u: Dictionary = units[t]
		for hid: String in Ships.ORDER:
			u["ship:" + hid] = make_ship(t, hid)
		for mt: String in Minions.TYPES:
			u["minion:" + mt] = world.spawn_minion(t, mt, "mid", home)
		var drone := world.spawn_mining_drone(t, "")
		drone.cargo = 160.0
		u["mining_drone"] = drone
		u["repair_drone"] = world.spawn_repair_drone(u["ship:logistics"], t, home, RepairDrone.MODE_LOGISTICS)
		u["ward"] = world.spawn_ward(t, home)
		u["turret:pd"] = world.spawn_turret(t, world.nodes[t], 0, "pd", true)
		u["turret:torp"] = world.spawn_turret(t, world.nodes[t], 1, "torp", true)
		u["bay"] = world.spawn_bay(t, home)
		u["mother"] = world.mothership(t)


## Launch a pilot ship of hull `hid` for team `t` (a pilot named after the
## hull, so the ship's own name tag says what it is), standing still with
## its main engine burning.
func make_ship(t: int, hid: String) -> Ship:
	var p := PilotProfile.new(str(Ships.HULLS[hid]["label"]), t, 20 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.controller = null
	s.thrust_main = 0.7
	_pose_turrets(s)
	return s


## Turn the guns of ship `s` that swing to different directions (the match is
## frozen, so they stay there), so the pictures show turrets that point somewhere.
## The Bomber also gets a stand-in for a rear gunner (a point-defense mount named
## as a tail gun, near the tail, facing backward) to show that its hull has room
## for one.
func _pose_turrets(s: Ship) -> void:
	var i := 0
	for m: WeaponMount in s.mounts:
		if m.mount_type != WeaponMount.FIXED:
			var side := 1.0 if i % 2 == 0 else -1.0
			m.angle = clampf(side * (0.55 + 0.25 * float(i % 3)), -m.arc, m.arc)
			i += 1
	if s.hull_id == "bomber":
		var tail := WeaponMount.new(s, "pd_gun", "auto", Vector2(-10.9, 0.0), 60.0)
		tail.weapon_id = "tail_gun"
		tail.angle = PI - 0.45
		s.mounts.append(tail)


## Show only the units whose key is in `keys` (both teams); hide the rest.
func _show(keys: Array) -> void:
	for t in 2:
		for key: String in units[t]:
			(units[t][key] as Node2D).visible = keys.has(key)


## Stand unit `u` at `at`, nose pointing right, not moving.
func _put(u: Node2D, at: Vector2) -> void:
	u.global_position = at
	u.rotation = 0.0
	if u is Ship:
		(u as Ship).velocity = Vector2.ZERO
	elif u is RepairBay:
		(u as RepairBay).anchor = at
	elif u is Ward:
		(u as Ward).anchor = at


# --- pictures --------------------------------------------------------------------------------------

## Point the camera at `at` with zoom `z` (1 = one world unit per pixel).
func aim_camera(at: Vector2, z: float) -> void:
	world.camera.global_position = at
	world.camera.target_zoom = z
	world.camera.zoom = Vector2(z, z)


## Where world point `p` is on the screen, for the camera set by aim_camera().
func _screen(p: Vector2) -> Vector2:
	return (p - world.camera.global_position) * world.camera.zoom.x + get_viewport().get_visible_rect().size * 0.5


## Write `text` at screen point `at` (the middle of the text), `px` pixels tall.
func _label(text: String, at: Vector2, px: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Palette.VOID)
	l.add_theme_constant_override("outline_size", 4)
	labels.add_child(l)
	l.position = at - l.get_minimum_size() * 0.5


## Take the picture `file`: write the headers, wait for the flames to fill
## in, save the frame, and take the names off again.
func _snap(file: String, title: String) -> void:
	var size := get_viewport().get_visible_rect().size
	_label(title, Vector2(size.x * 0.5, 22.0), 20, Palette.ICE)
	_label(str(Rules.TEAM_DISPLAY[0]).to_upper(), Vector2(size.x * 0.25, 52.0), 16, Palette.AMBER)
	_label(str(Rules.TEAM_DISPLAY[1]).to_upper(), Vector2(size.x * 0.75, 52.0), 16, Palette.CINDER)
	await wait_frames(int(SETTLE * 60.0))
	await RenderingServer.frame_post_draw
	var path := dir.path_join(file + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	count += 1
	for l in labels.get_children():
		l.queue_free()


## The close-up picture of unit type number `i` of TYPES: both teams' unit,
## nose right, zoomed so the whole thing (and its shield ring) fills most of
## its half of the screen.
func _close_up(i: int) -> void:
	var key: String = TYPES[i][1]
	var size := get_viewport().get_visible_rect().size
	var z := _close_zoom(key)
	aim_camera(home, z)
	_show([key])
	var y := 30.0 / z
	_put(units[0][key], home + Vector2(-size.x * 0.25 / z, y))
	_put(units[1][key], home + Vector2(size.x * 0.25 / z, y))
	await _snap("close_%02d_%s" % [i + 1, TYPES[i][0]], "%s (zoom %.1f)" % [TYPES[i][2], z])


## A zoom that fits unit `key` (with its shield ring and bars) in half the
## screen: ships by their shield ring, the rest by their own size. Never above
## 10: ShipVisual writes a ship's name in letters 11 screen pixels tall, which
## it works out as 11 / zoom whole world units, so beyond a zoom of 11 the
## letters would be under one pixel and Godot would print an error. (The game's
## own zoom stops at about 1.7.)
func _close_zoom(key: String) -> float:
	var half := get_viewport().get_visible_rect().size * 0.5
	var z := 0.0
	if key.begins_with("ship:"):
		var def: Dictionary = Ships.HULLS[key.substr(5)]
		var ring := maxf(float(def["length"]) * 0.62, float(def["radius"]) * 1.3)
		z = minf(half.x * 0.42, half.y * 0.55) / ring
	else:
		z = minf(half.x * 0.85, half.y * 0.6) / (_extent(key).x * 0.5)
	return minf(z, 10.0)


## About how long and wide unit `key` is drawn, in world units.
func _extent(key: String) -> Vector2:
	if key.begins_with("ship:"):
		var hid := key.substr(5)
		var box := GalleryChecks.box(AurelianPaint.outline(hid))
		return box * float(Ships.HULLS[hid]["length"]) / 36.0
	if key.begins_with("minion:"):
		var mt := key.substr(7)
		return GalleryChecks.box(MinionShapes.AURELIAN[mt]) * float(Minions.TYPES[mt]["radius"]) * 1.3
	match key:
		"mining_drone":
			return GalleryChecks.box(UnitVisual.DRONE) * float(Structures.MINING_DRONE["radius"]) * 1.2
		"repair_drone":
			return Vector2(12.0, 12.0)
		"ward":
			return Vector2(20.0, 20.0)
		"turret:pd":
			return Vector2(2.0, 2.0) * float(TurretData.TURRETS["pd"]["radius"])
		"turret:torp":
			return Vector2(2.4, 2.4) * float(TurretData.TURRETS["torp"]["radius"])
		"bay":
			return Vector2(2.0, 1.4) * float(Structures.REPAIR_BAY["radius"])
	return Vector2(1506.0, 340.0)


## How much room unit `key` takes on the screen at zoom `z`, in pixels: its
## shield ring for a ship (ships are never drawn under 16 pixels), its own
## size for the rest.
func _room(key: String, z: float) -> float:
	if key.begins_with("ship:"):
		var def: Dictionary = Ships.HULLS[key.substr(5)]
		var length := float(def["length"])
		var k := maxf(1.0, 16.0 / maxf(0.001, length * z))
		return maxf(maxf(length * k * 0.62, float(def["radius"]) * 1.3) * 2.0 * z, 48.0)
	return maxf(_extent(key).x * z, 64.0)


## How wide unit `key` stands in a lineup row at zoom `z`, in pixels: its
## room, or, for a pilot ship whose name tag shows (ShipVisual writes it from
## zoom 0.45 on), the tag's width when that is wider, so two neighbours' tags
## never overlap ("LOGISTICS CORVETTE" and "SUPPORT CORVETTE" did at mid zoom).
func _slot(key: String, z: float) -> float:
	var room := _room(key, z)
	if not key.begins_with("ship:") or z <= 0.45:
		return room
	# The tag is the hull's name (the gallery's pilots are named after their
	# hull) in capitals, 11 screen pixels tall.
	var tag := str(Ships.HULLS[key.substr(5)]["label"]).to_upper()
	var w := ThemeDB.fallback_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	return maxf(room, w + 8.0)


## A picture of the lineup `which` of LINEUPS at a view `view` world units
## wide: the rows of each team's half of the screen, units left to right with
## their names under them.
func _lineup(which: String, view: float, file: String) -> void:
	var size := get_viewport().get_visible_rect().size
	var z := size.x / view
	aim_camera(home, z)
	var keys: Array = []
	var rows: Array = LINEUPS[which]
	for row: Array in rows:
		keys.append_array(row)
	_show(keys)
	var row_y := size.y * 0.5 - (rows.size() - 1) * 170.0
	for r in rows.size():
		for t in 2:
			# Step 1: the row's total width, with a gap between units.
			var total := 0.0
			for key: String in rows[r]:
				total += _slot(key, z) + 28.0
			total -= 28.0
			# Step 2: stand each unit in its place, with its name under it.
			var x := size.x * (0.25 + 0.5 * t) - total * 0.5
			for key: String in rows[r]:
				var room := _room(key, z)
				var slot := _slot(key, z)
				var spot := Vector2(x + slot * 0.5, row_y + r * 340.0)
				_put(units[t][key], home + (spot - size * 0.5) / z)
				var nick: String = key.get_slice(":", key.get_slice_count(":") - 1).replace("_", " ")
				if nick == "mother":
					nick = "mothership"
				_label(nick, spot + Vector2(0.0, room * 0.5 + 16.0), 12, Palette.MIST)
				x += slot + 28.0
	await _snap(file, "%s, %s world units across (zoom %.2f)" % [which.replace("_", " "), String.num(view, 0), z])
