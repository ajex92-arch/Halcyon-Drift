class_name ProjectilesDraw
extends RefCounted
## WHAT THIS IS: draws the rounds in flight and the beam lines on the
## screen. A part of Projectiles, kept in its own file. Drawing only: it
## never changes the game.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## When Godot redraws the screen it calls Projectiles._draw(), which hands
## itself to draw_all(). We work out the part of the map the camera shows
## (plus a 200 world-unit margin) and skip rounds outside it. Enemy rounds
## in fog the viewing team can't see are skipped too; our own are always
## drawn. Each round is a short streak pointing back along its flight:
##   torpedo: a dot with a faint tail;
##   shell:   a thick streak;
##   flak:    a short streak;
##   others (bolts, point defense): a thin streak.
## Beams are a wide faint glow with a thin bright core. Ion beams are
## shield-blue; other beams take the team's bolt colour. An enemy beam is
## hidden only when the viewer can see neither of its two ends.
##
## Sizes are multiplied by "px" (one screen pixel in world units, which
## depends on the camera zoom), so streaks keep the same size on screen at
## any zoom.
##
## WHO USES IT: only Projectiles._draw().


## Draw every visible round and last tick's beam lines onto `proj` (the
## Projectiles node). Only call this from Projectiles._draw().
static func draw_all(proj: Projectiles) -> void:
	# Step 1: the part of the map the camera shows (plus a margin), and how
	# big one screen pixel is in world units.
	var cam := proj.get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam != null else 1.0
	var view := proj.get_viewport_rect().size / zoom
	var center := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var rect := Rect2(center - view * 0.5, view).grow(200.0)
	var px := 1.0 / maxf(0.02, zoom)
	var world := proj.world
	var viewer_team := proj.viewer_team
	var live := proj.live
	var pos := proj.pos
	var team := proj.team
	var kind := proj.kind
	var vel := proj.vel
	var radius := proj.radius
	# Step 2: each live round on screen that the viewer may see.
	for i in proj.active:
		if live[i] == 0:
			continue
		var p := pos[i]
		if not rect.has_point(p):
			continue
		if viewer_team >= 0 and team[i] != viewer_team and not world.vision.is_visible(viewer_team, p):
			continue
		# Its colour, and the direction it flies (straight right if it is
		# not moving), so the streak can point backwards.
		var col := Palette.bolt(team[i])
		var k := kind[i]
		var v := vel[i]
		var sp := v.length()
		var dir := v / sp if sp > 0.0 else Vector2.RIGHT
		# Step 3: its shape depends on the weapon kind.
		match k:
			Rules.W_TORP:
				proj.draw_circle(p, maxf(radius[i], 3.0 * px), col)
				proj.draw_line(p, p - dir * 10.0 * px, Palette.with_alpha(col, 0.6), 2.0 * px)
			Rules.W_SHELL:
				proj.draw_line(p, p - dir * 16.0 * px, col, 3.0 * px)
			Rules.W_FLAK:
				proj.draw_line(p, p - dir * 6.0 * px, Palette.with_alpha(col, 0.9), 2.0 * px)
			_:
				proj.draw_line(p, p - dir * 9.0 * px, col, 1.6 * px)
	# Step 4: the beams, each [a, b, team, width, kind]: a wide faint glow
	# under a thin bright core (at least 2 screen pixels wide).
	for bm: Array in proj.beams_draw:
		var bt: int = bm[2]
		var a: Vector2 = bm[0]
		var b: Vector2 = bm[1]
		if viewer_team >= 0 and bt != viewer_team and not world.vision.is_visible(viewer_team, a) and not world.vision.is_visible(viewer_team, b):
			continue
		var w := maxf(float(bm[3]), 2.0 * px)
		var col := Palette.SHIELD if int(bm[4]) == Rules.W_ION else Palette.bolt(bt)
		proj.draw_line(a, b, Palette.with_alpha(col, 0.35), w * 2.5)
		proj.draw_line(a, b, col, w)
