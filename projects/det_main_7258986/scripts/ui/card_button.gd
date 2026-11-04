class_name CardButton
extends PanelContainer
## WHAT THIS IS: a clickable card: a title, an optional wrapped
## description, and a footer line (price / status / reason). Unlike a plain
## Button, it grows to fit its text.
##
## HOW IT WORKS: _init() builds the three labels (plus an empty `extra`
## column that callers may fill). A left click sends `pressed`, unless the
## card is disabled. _restyle() draws the border: in the interface's highlight
## colour (`accent`) when selected or when the mouse is over an enabled card,
## otherwise the plain line colour; a selected card also gets a dark fill. A disabled card is
## drawn see-through (its `dim` amount).
##
## WHO USES IT: Hangar (ship, module, gear and slot cards) and AdmiralBoard
## (facility and research cards) make them with CardButton.new(...) and
## call set_state() and set_lines() as things change. (The start screen
## used to be listed here too, but it uses plain buttons.)

## Sent when the card is clicked with the left mouse button (and is not
## disabled).
signal pressed

## The title line (15 px text).
var title: Label
## The wrapped description under the title (hidden when empty).
var sub: Label
## The footer line, in the interface's highlight colour unless the caller
## colours it (hidden when empty).
var foot: Label
## An empty column under the footer where callers can add more lines.
var extra: VBoxContainer
## A disabled card ignores clicks and is drawn see-through.
var disabled := false
## A selected card has an accent border and a dark fill.
var selected := false
## The border colour for selected / hovered cards: the interface's highlight
## colour (UiKit.accent()) when the card is made.
var accent := UiKit.accent()
## True while the mouse is over the card.
var _hover := false
## How solid a disabled card is (0..1; 1 = fully solid).
var _dim := 0.45


## Build the card with its texts (an empty `sub_text` or `foot_text` hides
## that line) and at least `min_w` pixels wide, 40 tall. Cards never take
## keyboard focus, so the game's keys keep working after a click.
func _init(title_text: String = "", sub_text: String = "", foot_text: String = "", min_w: float = 0.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(min_w, 40.0)
	# Step 1: the labels, top to bottom.
	var v := UiKit.vbox(2)
	add_child(v)
	title = UiKit.label(title_text, 15, Palette.ICE)
	sub = UiKit.label(sub_text, 12, Palette.MIST, true)
	foot = UiKit.label(foot_text, 12, accent)
	v.add_child(title)
	v.add_child(sub)
	v.add_child(foot)
	extra = UiKit.vbox(2)
	v.add_child(extra)
	sub.visible = sub_text != ""
	foot.visible = foot_text != ""
	# Step 2: hovering changes the border.
	mouse_entered.connect(func() -> void:
		_hover = true
		_restyle())
	mouse_exited.connect(func() -> void:
		_hover = false
		_restyle())
	_restyle()


## Set whether the card is disabled and selected, and how solid (`dim`,
## 0..1) it is while disabled. Restyles only when something changed.
func set_state(is_disabled: bool, is_selected: bool, dim: float = 0.45) -> void:
	if is_disabled == disabled and is_selected == selected and dim == _dim:
		return
	disabled = is_disabled
	selected = is_selected
	_dim = dim
	_restyle()


## Change the three texts (an empty sub or footer is hidden).
func set_lines(title_text: String, sub_text: String, foot_text: String) -> void:
	UiKit.set_text(title, title_text)
	UiKit.set_text(sub, sub_text)
	UiKit.set_text(foot, foot_text)
	sub.visible = sub_text != ""
	foot.visible = foot_text != ""


## Mouse input on the card: a left-button press is a click. We always
## take the click (so the game doesn't also get it), but only send
## `pressed` when the card is enabled.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if not disabled:
				pressed.emit()


## Redraw the card's look from its state (see HOW IT WORKS).
func _restyle() -> void:
	var border := Palette.LINE
	if selected or (_hover and not disabled):
		border = accent
	var bg := Palette.INK if selected else Palette.with_alpha(Palette.PANEL, 0.0)
	add_theme_stylebox_override("panel", UiKit.box(bg, border, 7))
	modulate.a = _dim if disabled else 1.0
