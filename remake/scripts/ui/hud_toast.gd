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
## bottom edge. While a big panel is open it drops to 6 pixels above the
## bottom (the strip that only has key hints) so it doesn't cover the
## panel. It is also kept as the HUD's last child, so it draws on top of
## everything.
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it and
## Hud.setup() gives it the HUD. Hud.toast() (connected to Events.toast,
## so any script can pop a hint up) calls show_text(), and Hud._process()
## calls tick() every frame. It asks the Hud whether a panel is open
## (Hud._any_panel_open).

## The HUD this widget belongs to (Hud.setup() sets it).
var hud: Hud
## The hint text.
@onready var _label: Label = $Text
## Seconds the hint has left to show (0 = hidden).
var _t := 0.0


## Show `text` for 3.5 seconds (a new hint replaces the old one).
func show_text(text: String) -> void:
	_label.text = text
	_t = 3.5
	visible = true
	place()


## Put the box in its spot: 6 pixels above the bottom while a big panel is
## open, else 150. We shrink the box to a point first; its minimum size
## then grows it back, centred and upward from that point.
func place() -> void:
	var y := -6.0 if hud._any_panel_open() else -150.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = y
	offset_bottom = y
	# Make sure we are the HUD's last child, so we draw on top.
	if get_index() != hud.get_child_count() - 1:
		move_to_front()


## Count the hint's time down by `dt` seconds. Over its last 0.6 seconds
## it fades out (modulate.a is how solid it is: 1 = solid, 0 = invisible);
## at 0 it hides.
func tick(dt: float) -> void:
	if _t > 0.0:
		_t -= dt
		modulate.a = clampf(_t / 0.6, 0.0, 1.0)
		place()
		if _t <= 0.0:
			visible = false
