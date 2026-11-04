class_name AsteroidFieldChunk
extends Node2D
## WHAT THIS IS: one drawing "chunk" of the AsteroidField: a square patch
## of the map (AsteroidField.CHUNK, 4,000 world units wide) that draws the
## rocks whose centres are inside it.
##
## HOW IT WORKS: Godot remembers what a node drew last time, so _draw() only
## runs again when someone asks for it (queue_redraw()). The field asks
## once after all rocks are added, and again whenever a rock in this chunk
## is destroyed. Each live rock is drawn as a filled lumpy shape (its
## outline) with an edge line in Palette.ROCK_EDGE; destroyed rocks are
## simply left out.
## Splitting the map into chunks means a destroyed rock only redraws its
## own patch, not the whole map.
##
## WHO USES IT: AsteroidField._add() makes the chunks (as its children,
## drawn behind the units) and adds rock numbers to `members`;
## AsteroidField.build() and destroy() ask them to redraw.

## The asteroid field whose rocks we draw (we read its pos, alive, outline,
## shade and node_rock lists).
var field: AsteroidField
## The numbers of the rocks drawn by this chunk.
var members := PackedInt32Array()


## Draw every live rock in this chunk. Its colour is a mix of
## Palette.ROCK_A and Palette.ROCK_B (by its shade); ore rocks are tinted
## 25% towards Palette.ORE_ROCK.
func _draw() -> void:
	for i in members:
		if field.alive[i] == 0:
			continue
		# The outline's corners, moved to where the rock is.
		var p := field.pos[i]
		var poly: PackedVector2Array = field.outline[i]
		var pts := PackedVector2Array()
		pts.resize(poly.size())
		for k in poly.size():
			pts[k] = p + poly[k]
		# The fill colour.
		var s := field.shade[i]
		var fill := Palette.ROCK_A.lerp(Palette.ROCK_B, s)
		if field.node_rock[i] == 1:
			fill = fill.lerp(Palette.ORE_ROCK, 0.25)
		# The filled shape, then its edge (4 units wide, closed by repeating
		# the first corner at the end).
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, Palette.ROCK_EDGE, 4.0, true)
