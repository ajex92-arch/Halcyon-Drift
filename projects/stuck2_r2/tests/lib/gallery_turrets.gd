class_name GalleryTurrets
extends RefCounted
## WHAT THIS IS: the turret sheet of the hull gallery (tests/hull_gallery.gd): one
## picture that shows every turret silhouette of both team styles (Aurelian on the
## left, Vhorr on the right), each weapon class on its own row, turned three ways
## and at the sizes it has on the ships, so the silhouettes can be judged.
##
## HOW IT WORKS: it covers the screen with a plain backdrop and a small drawing
## node that draws the turrets through TurretPaint.draw_turret(), exactly the
## way a ship's own painter does, in screen pixels (one world unit = one pixel).
## The first three turrets of a row are big (each turned a quarter further, to show
## the barrels turn), the last three are small, at the sizes of a corvette's, a
## frigate's and a capital ship's turrets at the usual zoom. The names of the
## classes are written with Label nodes by the gallery.
##
## WHO USES IT: tests/hull_gallery.gd calls sheet() after its other pictures.

## Screen pixels per turret unit of the big turrets.
const BIG := 20.0
## The turns of the three big turrets of a row, in radians (the barrel's
## direction: right, down, left).
const TURNS := [0.0, PI * 0.5, PI]
## Screen pixels per turret unit of the three small turrets of a row.
const SMALL := [4.0, 8.0, 14.0]
## The words written in front of each class's row.
const NAMES := {
	"pd": "point defense", "flak": "flak", "light": "light turret", "heavy": "heavy cannon", "ion": "ion turret",
	"tail": "tail gun", "torp": "torpedo turret",
}


## The drawing node of the sheet: draws every turret of both styles.
class Sheet extends Node2D:
	## The size of the screen in pixels.
	var size := Vector2(1920.0, 1080.0)

	## Draw every turret of both styles: three big ones turned three ways and three small ones, per class.
	func _draw() -> void:
		var rows := TurretShapes.CLASSES.size()
		var row_h := (size.y - 120.0) / float(rows)
		for t in 2:
			var team := Rules.HALCYON if t == 0 else Rules.CINDER
			var x0 := size.x * 0.5 * float(t) + 150.0
			for r in rows:
				var cls: String = TurretShapes.CLASSES[r]
				var rec := TurretPaint.turret(cls, team)
				var y := 100.0 + row_h * (float(r) + 0.5)
				for k in 3:
					TurretPaint.draw_turret(self, rec, Vector2(x0 + float(k) * 105.0, y), float(TURNS[k]), BIG, 1.0)
				for k in 3:
					TurretPaint.draw_turret(self, rec, Vector2(x0 + 340.0 + float(k) * 60.0, y), 0.0, float(SMALL[k]), 1.0)


## Make the sheet, name its rows, take the picture `file` and clean up.
static func sheet(gallery: Node, file: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	gallery.add_child(layer)
	var size: Vector2 = gallery.get_viewport().get_visible_rect().size
	var back := ColorRect.new()
	back.color = Palette.INK
	back.size = size
	layer.add_child(back)
	var node := Sheet.new()
	node.size = size
	layer.add_child(node)
	var rows := TurretShapes.CLASSES.size()
	var row_h := (size.y - 120.0) / float(rows)
	for r in rows:
		var y := 100.0 + row_h * (float(r) + 0.5)
		gallery._label(NAMES[TurretShapes.CLASSES[r]], Vector2(80.0, y), 14, Palette.MIST)
	await gallery._snap(file, "Turret silhouettes (big, turned three ways, and at the sizes on the ships)")
	layer.queue_free()
