class_name HudToast
extends PanelContainer
## WHAT THIS IS: the short pop-up hint near the bottom of the screen ("a
## toast", because it pops up like toast from a toaster), for example
## "Rally waypoint set." or "Camera: following your ship".
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_toast.tscn: a dark
## box (the "ToastLook" look), hidden at first, at the bottom centre and
## growing upward and to both sides, holding one centred label, Text. The
## mouse passes through it. show_text() puts the text in the box and shows
## it for 3.5 seconds; tick() counts that time down and fades the box out
## over the last 0.6 seconds. Normally the box sits 150 pixels above the
## bottom edge, clear of the ship readout. While a big panel is open it drops
## to 6 pixels above the bottom, into the strip under the panel, so it doesn't
## cover the panel: in the middle, or, while the ship readout shows there, in
## the bottom-right corner beside it (HudLayout.toast_spot); while the
## scoreboard (which has no such strip) is held open, or the match is over,
## it waits, hidden, and its time stops. A text too long for the room it has
## (HudLayout.toast_width: in flight it must stay clear of the minimap)
## wraps onto more lines. It is also kept as the HUD's last child, so it
## draws on top of everything.
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it and
## Hud.setup() gives it the HUD. Hud.toast() (connected to Events.toast,
## so any script can pop a hint up) calls show_text(), and Hud._process()
## calls tick() every frame. It asks the Hud whether a panel is open
## (Hud._any_panel_open) and HudLayout where it sits and how wide it may be.

## The HUD this widget belongs to (Hud.setup() sets it).
var hud: Hud
## The hint text.
@onready var _label: Label = $Text
## Seconds the hint has left to show (0 = hidden).
var _t := 0.0


## Godot calls this when the box joins the HUD: let long text wrap.
func _ready() -> void:
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Show `text` for 3.5 seconds (a new hint replaces the old one).
func show_text(text: String) -> void:
	_label.text = text
	_t = 3.5
	visible = true
	place()


## Put the box in its spot (HudLayout.toast_spot: 150 pixels above the
## bottom, or in the strip under an open panel) and make it no wider than
## HudLayout allows (the text wraps instead). We shrink the box to a point
## first; its minimum size then grows it back, centred and upward from that
## point.
func place() -> void:
	var open := hud._any_panel_open()
	var spot := hud.layout.toast_spot(open)
	# The label is as wide as its text, or as wide as the box may be less
	# the box's own space on the left and right.
	var font := _label.get_theme_font("font")
	var text_w := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _label.get_theme_font_size("font_size")).x
	var room := hud.layout.toast_width(open) - get_theme_stylebox("panel").get_minimum_size().x
	UiKit.pin_width(_label, minf(ceilf(text_w) + 2.0, room))
	offset_left = spot.x
	offset_right = spot.x
	offset_top = -spot.y
	offset_bottom = -spot.y
	# Make sure we are the HUD's last child, so we draw on top.
	if get_index() != hud.get_child_count() - 1:
		move_to_front()


## Count the hint's time down by `dt` seconds. Over its last 0.6 seconds
## it fades out (modulate.a is how solid it is: 1 = solid, 0 = invisible);
## at 0 it hides.
func tick(dt: float) -> void:
	if _t > 0.0:
		# While the scoreboard is held open the hint waits (it would sit over
		# the table), and its time does not run. Once the match is over it
		# waits for good (the end screen has the whole window).
		var waiting := (hud.scoreboard != null and hud.scoreboard.visible) or hud.end_screen != null
		visible = not waiting
		if waiting:
			return
		_t -= dt
		modulate.a = clampf(_t / 0.6, 0.0, 1.0)
		place()
		if _t <= 0.0:
			visible = false
