class_name FogView
extends Sprite2D
## WHAT THIS IS: the dark cover drawn over the map where the viewing team
## can't see: the fog of war on the screen.
##
## HOW IT WORKS: it is one small picture with one pixel per Vision cell,
## stretched over the whole map. Linear filtering blends neighbouring
## pixels, which gives the fog soft edges. Every pixel has the fog colour
## (Palette.FOG) and a see-through amount ("alpha": 0 = clear, 1 = solid):
##   - lit cells (seen right now): clear (alpha 0);
##   - explored cells (seen before, not now): ALPHA_EXPLORED (0.5);
##   - never-seen cells: ALPHA_DARK (0.78).
## The picture is redrawn every 0.2 s (5 times a second, as often as
## Vision updates each team). A spectator (World.viewer_team -1) sees no
## fog: the picture is hidden and never redrawn.
##
## WHO USES IT: it is the "FogView" child node of the World scene.
## WorldSetup calls setup(). It reads World.vision (lit, explored, stamp)
## and World.viewer_team. The Minimap shows this same picture.

## How dark never-seen cells are (alpha, 0..1).
const ALPHA_DARK := 0.78
## How dark explored cells are when not seen right now (alpha, 0..1).
const ALPHA_EXPLORED := 0.5

## The world whose fog we draw.
var world: World
## The fog picture: one pixel per Vision cell (cols x rows pixels).
var image: Image
## The picture as a texture the graphics card can draw; updated from image.
var tex: ImageTexture
## Seconds until the next redraw of the picture (counts down every frame).
var _t := 0.0


## Make the picture (all dark at first), stretch it over the map (each
## pixel as big as one Vision cell) and draw it above the effects
## (z_index 8). Hidden for a spectator. WorldSetup calls this once. With
## --sim-only (Game.sim_only) nothing is drawn, so no picture is made at all:
## we hide ourselves and stop the per-frame work.
func setup(w: World) -> void:
	world = w
	if Game.sim_only:
		visible = false
		set_process(false)
		return
	z_index = 8
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image = Image.create(w.vision.cols, w.vision.rows, false, Image.FORMAT_RGBA8)
	image.fill(Color(Palette.FOG.r, Palette.FOG.g, Palette.FOG.b, ALPHA_DARK))
	tex = ImageTexture.create_from_image(image)
	texture = tex
	scale = Vector2(w.vision.cell, w.vision.cell)
	visible = w.viewer_team >= 0


## Every frame (`dt` seconds): every 0.2 s, paint the picture again from
## the viewing team's lit and explored cells.
func _process(dt: float) -> void:
	# Step 1: nothing to do for a spectator, or before the next redraw.
	if world == null or world.viewer_team < 0:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.2
	# Step 2: the viewing team's lists, and the colour values as whole
	# numbers 0-255 (how the picture stores them).
	var v := world.vision
	var team := world.viewer_team
	var lit: PackedInt32Array = v.lit[team]
	var explored: PackedByteArray = v.explored[team]
	var s: int = v.stamp[team]
	var data := PackedByteArray()
	data.resize(v.cols * v.rows * 4)
	var fr := int(Palette.FOG.r * 255.0)
	var fg := int(Palette.FOG.g * 255.0)
	var fb := int(Palette.FOG.b * 255.0)
	var a_dark := int(ALPHA_DARK * 255.0)
	var a_exp := int(ALPHA_EXPLORED * 255.0)
	# Step 3: four numbers per pixel (red, green, blue, alpha). The alpha
	# says lit (clear), explored (half dark) or never seen (dark).
	for i in v.cols * v.rows:
		var o := i * 4
		data[o] = fr
		data[o + 1] = fg
		data[o + 2] = fb
		if lit[i] == s:
			data[o + 3] = 0
		elif explored[i] == 1:
			data[o + 3] = a_exp
		else:
			data[o + 3] = a_dark
	# Step 4: put the new pixels into the picture and the texture.
	image.set_data(v.cols, v.rows, false, Image.FORMAT_RGBA8, data)
	tex.update(image)
