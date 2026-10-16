class_name RecallBar
extends Control
## WHAT THIS IS: the small bar on the HUD that counts down the human pilot's
## recall (the Recall feature, key T). It is only on the screen while a
## recall is running.
##
## HOW IT WORKS: every frame it asks the feature for the human's progress
## (RecallFeature.human_progress()). With no recall it draws nothing. With
## one it draws a bar above the ship readout that fills as the seconds pass,
## with the text "RECALL 7.2 s: hold still and hold fire".
##
## WHO USES IT: RecallFeature.install() makes it (only when there is a
## window) and sets `feature`.

## Width of the bar (pixels).
const W := 300.0
## Height of the bar (pixels).
const H := 20.0
## How far above the bottom edge of the screen the bar sits (pixels).
const LIFT := 180.0

## The feature to ask for the human's progress.
var feature: RecallFeature
## The font for the text (Godot's built-in default font).
var font: Font


## Fix the bar's place (bottom centre) and let the mouse pass through.
func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE)
	offset_top -= LIFT
	offset_bottom -= LIFT


## Every frame: redraw (the countdown changes all the time).
func _process(_dt: float) -> void:
	queue_redraw()


## Draw the bar when the human is recalling.
func _draw() -> void:
	if feature == null:
		return
	var prog := feature.human_progress()
	if prog.is_empty():
		return
	var left: float = prog[0]
	var total: float = prog[1]
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Palette.INK)
	draw_rect(Rect2(Vector2.ZERO, Vector2(W * clampf(1.0 - left / total, 0.0, 1.0), H)), Palette.AMBER)
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Palette.LINE, false, 1.0)
	draw_string(font, Vector2(8, 15), "RECALL %.1f s: hold still and hold fire" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.ICE)
