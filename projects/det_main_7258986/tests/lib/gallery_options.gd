class_name GalleryOptions
extends RefCounted
## WHAT THIS IS: the options sheet of the hull gallery (tests/hull_gallery.gd): one
## picture that shows the directions drawn for the Aurelian Scout (the Pin, the
## Comet and the Blade) and for the Support Corvette (the one the game uses and
## the one it does not), and the new Fighter. Each hull is drawn big, and then
## small at the sizes of the near, the
## mid and the play view, so the directions can be judged (and picked) at the
## sizes a player really sees.
##
## HOW IT WORKS: it covers the screen with a plain backdrop and one small
## drawing node for each hull, which draws it through AurelianPaint.draw_shape(),
## exactly the way a ship's own painter does (the big drawings are scaled to fit
## their rows; the small ones are scaled to the view they stand for). The
## drawings the game uses come from AurelianPaint.hull(); the options, which the
## game never draws, come from OptionHulls through AurelianPaint.prepare(). The
## big Support Corvette also gets its light turret, so the mount can be judged.
## The names are written with Label nodes by the gallery.
##
## WHO USES IT: tests/hull_gallery.gd calls sheet() after the turret sheet, and
## tests/lib/gallery_aurelian.gd asks record() for the hulls it checks.

## The rows of the sheet: the hull of ships.gd, the options on the left (a list
## of ids, empty for none), the drawing the game uses on the right with the words
## under it, and the screen pixels per world unit of the big drawings on a screen
## 1,920 pixels wide (sheet() scales it to the real width).
const ROWS := [
	{"base": "scout", "left": ["scout_pin", "scout_comet"], "right": "scout", "words": "C  Blade  (in the game)", "big": 15.0},
	{"base": "support", "left": ["support_box"], "right": "support", "words": "B  Saturn  (in the game)", "big": 7.0},
	{"base": "fighter", "left": [], "right": "fighter", "words": "Forward-swept cross  (in the game)", "big": 17.0},
]
## The widths (world units) of the views the small drawings stand for: the
## closest a pilot can zoom in, the mid view and the play view.
const VIEWS := [CameraRig.MIN_VIEW_WIDTH, 2200.0, 4500.0]
## The names of those views, written over the small drawings.
const VIEW_NAMES := ["near view", "mid view", "play view"]
## Frames to wait before the picture is taken.
const SETTLE_FRAMES := 30

## The prepared drawings: id -> prepared hull (see AurelianPaint.hull()).
static var _recs := {}


## The prepared drawing `id`: a hull the game draws, or an option hull.
static func record(id: String) -> Dictionary:
	if not _recs.has(id):
		if OptionHulls.HULLS.has(id):
			_recs[id] = AurelianPaint.prepare(OptionHulls.HULLS[id])
		else:
			_recs[id] = AurelianPaint.hull(id)
	return _recs[id]


## One hull drawn on the sheet: the steel drawing and, when asked, a turret.
class HullView extends Node2D:
	## The prepared hull (AurelianPaint.hull()).
	var rec: Dictionary
	## Screen pixels per design unit.
	var u := 1.0
	## True = also draw the hull's light turret at `mount` (design units).
	var turret := false
	var mount := Vector2.ZERO
	## Design units per turret unit of this hull.
	var tu := 1.0

	## Draw the hull, nose to the right, and its turret when it has one.
	func _draw() -> void:
		AurelianPaint.draw_shape(self, rec, u, 0.0, 1.0, Palette.AMBER, 1.4, 0.0, 0.8)
		if turret:
			TurretPaint.draw_turret(self, TurretPaint.turret("light", Rules.HALCYON), mount * u, 0.5, tu * u, 1.0)


## Put hull `id` (of the ships.gd hull `base`, `scale` screen pixels per world
## unit) with its middle at `at` on `layer`; with `turret` it also gets its turret.
static func _place(layer: CanvasLayer, id: String, base: String, scale: float, at: Vector2, turret: bool) -> void:
	var rec := record(id)
	var sil: PackedVector2Array = rec["sil"]
	var x_lo := INF
	var x_hi := -INF
	for p: Vector2 in sil:
		x_lo = minf(x_lo, p.x)
		x_hi = maxf(x_hi, p.x)
	var view := HullView.new()
	view.rec = rec
	view.u = scale * float(Ships.HULLS[base]["length"]) / 36.0
	view.position = at - Vector2((x_lo + x_hi) * 0.5 * view.u, 0.0)
	if turret:
		for s: Dictionary in rec["sockets"]:
			if str(s["weapon"]) == "light_turret":
				view.turret = true
				view.mount = s["at"]
				view.tu = float(TurretShapes.HULL_TU.get(base, TurretShapes.DEFAULT_TU))
	layer.add_child(view)


## Make the sheet, name its drawings, take the picture `file` and clean up.
static func sheet(gallery: Node, file: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	gallery.add_child(layer)
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	var back := ColorRect.new()
	back.color = Palette.INK
	back.size = size
	layer.add_child(back)
	var row_h := (size.y - 100.0) / float(ROWS.size())
	for r in ROWS.size():
		var row: Dictionary = ROWS[r]
		var base: String = row["base"]
		var y := 100.0 + row_h * (float(r) + 0.5)
		var big: float = float(row["big"]) * size.x / 1920.0
		var shown: Array = []
		var lefts: Array = row["left"]
		# One option stands 0.29 of the width left of the game's drawing; more stand closer.
		var gap := 0.29 if lefts.size() < 2 else 0.18
		for i in lefts.size():
			var oid: String = lefts[i]
			shown.append([oid, size.x * (0.46 - gap * float(lefts.size() - i)), str(OptionHulls.HULLS[oid]["label"]) + "  (not in the game)"])
		shown.append([str(row["right"]), size.x * 0.46, str(row["words"])])
		for s: Array in shown:
			_place(layer, str(s[0]), base, big, Vector2(float(s[1]), y - 14.0), true)
			gallery._label(str(s[2]), Vector2(float(s[1]), y + row_h * 0.5 - 12.0), 15, Palette.ICE)
		# The small drawings: every direction, one above the other, at each view.
		for k in VIEWS.size():
			var x := size.x * (0.70 + 0.11 * float(k))
			var scale := size.x / float(VIEWS[k])
			var n := shown.size()
			for i in n:
				var yy := y + (float(i) - float(n - 1) * 0.5) * 70.0
				_place(layer, str(shown[i][0]), base, scale, Vector2(x, yy), false)
	for k in VIEWS.size():
		gallery._label("%s (%d wide)" % [VIEW_NAMES[k], int(VIEWS[k])], Vector2(size.x * (0.70 + 0.11 * float(k)), 92.0), 13, Palette.MIST)
	gallery._label("Aurelian redesign: Scout options (Pin, Comet, Blade), Support Corvette options, and the new Fighter", Vector2(size.x * 0.5, 24.0), 20, Palette.ICE)
	await gallery.wait_frames(SETTLE_FRAMES)
	await RenderingServer.frame_post_draw
	var path: String = str(gallery.dir).path_join(file + ".png")
	gallery.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)
	gallery.count += 1
	for l in gallery.labels.get_children():
		l.queue_free()
	layer.queue_free()
