class_name UiKit
extends RefCounted
## WHAT THIS IS: the shared toolbox for building screens: the game's look
## (a Godot "theme": default colours, boxes and fonts for every kind of
## control) and small helpers that make a styled label, button, box or
## row in one line.
##
## HOW IT WORKS: every function is "static": you call it on the class
## itself (UiKit.label("Hi")) without making a UiKit first. Each screen is
## its own scene (scenes/ui/*.tscn). The parts that never change (panels,
## rows, headings, fixed labels) are nodes in the scene, and each node
## picks its look by name: its theme_type_variation is one of the named
## looks make_theme() adds (MistText, AccentText, PrimaryButton and the
## PANEL_LOOKS boxes). Lists that change while playing (cards, rows of
## pilots, feed lines) are still built in code with the helpers below.
## Colours always come from Palette, never from the scene files.
## The interface has one highlight colour (the "accent"): the first line of the
## top-left panel, the pressed and chosen buttons, the selected tabs, the prices.
## It follows the human's team: amber for Aurelian (and for a spectator), red for
## Vhorr. Palette.accent() decides the colour; accent_team says for which side
## the interface is built, and accent() gives the colour. Whoever builds a screen
## (Hud.setup(), StartScreen) sets the side first with set_accent_team().
## Buttons never take keyboard focus: WASD, Space, Tab and the arrows
## belong to the pilot, not to whichever button was clicked last.
##
## WHO USES IT: the scripts in scripts/ui/: Hud and its widgets, Hangar,
## AdmiralBoard, Scoreboard, HelpPanel, EndScreen, StartScreen, CardButton
## and ShipStatus.

## The named box looks for scenes: [name, fill colour, how solid (0..1),
## space inside in pixels]. make_theme() turns each into a PanelContainer
## look that a scene node picks with its theme_type_variation.
const PANEL_LOOKS := [
	["TopBarLook", Palette.PANEL, 0.85, 6],   # HUD top bar
	["MeLook", Palette.PANEL, 0.8, 8],        # HUD "me" panel (top left)
	["ToastLook", Palette.VOID, 0.88, 5],     # HUD pop-up hint
	["SlotLook", Palette.INK, 0.85, 4],       # one HUD gear slot
	["BoardLook", Palette.PANEL, 0.97, 12],   # Admiral board
	["HangarLook", Palette.PANEL, 0.97, 14],  # hangar
	["HelpLook", Palette.PANEL, 0.97, 16],    # help pages
	["ScoreLook", Palette.PANEL, 0.96, 14],   # scoreboard
	["SeatLook", Palette.INK, 1.0, 14],       # start screen seat card
	["StartLook", Palette.PANEL, 0.95, 22],   # start screen main card
	["EndLook", Palette.PANEL, 0.95, 24],     # end screen card
]

## The team the interface highlights for (Rules.HALCYON or Rules.CINDER): the
## human's team, or Aurelian for a spectator. Change it only with
## set_accent_team().
static var accent_team := Rules.HALCYON


## Build the interface for team `t` from now on: accent() gives that team's
## highlight colour (Palette.accent()). A theme made before this call keeps the
## old colour, so the caller makes a new one with make_theme().
static func set_accent_team(t: int) -> void:
	accent_team = t


## The interface's highlight colour: Palette.accent() of accent_team.
static func accent() -> Color:
	return Palette.accent(accent_team)


## Build the game's theme. Hud and StartScreen set it on themselves, and
## every control inside them uses it unless it overrides a look itself. It is
## made with the accent() colour of the moment.
static func make_theme() -> Theme:
	var t := Theme.new()
	var hi := accent()
	t.default_font_size = 15
	# Step 1: panels and buttons. Buttons get a border in the accent colour on
	# hover and when pressed, and an empty focus box (no focus outline).
	t.set_stylebox("panel", "PanelContainer", box(Palette.with_alpha(Palette.PANEL, 0.94), Palette.LINE, 12))
	t.set_stylebox("panel", "Panel", box(Palette.PANEL, Palette.LINE, 0))
	t.set_stylebox("normal", "Button", box(Palette.INK, Palette.LINE, 8))
	t.set_stylebox("hover", "Button", box(Palette.INK, hi, 8))
	t.set_stylebox("pressed", "Button", box(Palette.PANEL, hi, 8))
	t.set_stylebox("hover_pressed", "Button", box(Palette.PANEL, hi, 8))
	t.set_stylebox("disabled", "Button", box(Palette.with_alpha(Palette.INK, 0.6), Palette.with_alpha(Palette.LINE, 0.6), 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	# Step 2: text colours for buttons and labels.
	t.set_color("font_color", "Button", Palette.ICE)
	t.set_color("font_hover_color", "Button", Palette.ICE)
	t.set_color("font_pressed_color", "Button", hi)
	t.set_color("font_hover_pressed_color", "Button", hi)
	t.set_color("font_focus_color", "Button", Palette.ICE)
	t.set_color("font_disabled_color", "Button", Palette.with_alpha(Palette.MIST, 0.5))
	t.set_color("font_color", "Label", Palette.ICE)
	# Step 3: progress bars (dark background, accent fill).
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Palette.INK
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = hi
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	# Step 4: scroll areas: no background, slim scroll bars. The "grabber"
	# is the part of the scroll bar you drag; the "scroll" box is its track.
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var grab := StyleBoxFlat.new()
	grab.bg_color = Palette.LINE
	grab.set_content_margin_all(3)
	for sb: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", sb, grab)
		t.set_stylebox("grabber_highlight", sb, grab)
		t.set_stylebox("grabber_pressed", sb, grab)
		var track := StyleBoxFlat.new()
		track.bg_color = Palette.with_alpha(Palette.INK, 0.6)
		track.set_content_margin_all(3)
		t.set_stylebox("scroll", sb, track)
	# Step 5: tooltips (the little boxes that appear when you hover).
	var tip := box(Palette.INK, Palette.LINE, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Palette.ICE)
	# Step 6: named looks ("type variations"). A node in a scene picks one
	# by name (its theme_type_variation), so the colours stay in Palette.
	# Text colours: MistText (grey) and AccentText (the highlight colour). Plain
	# labels are ICE.
	t.set_type_variation("MistText", "Label")
	t.set_color("font_color", "MistText", Palette.MIST)
	t.set_type_variation("AccentText", "Label")
	t.set_color("font_color", "AccentText", hi)
	# The button filled with the accent colour for a screen's main choice
	# (Launch, New match, the start screen's seat buttons).
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(hi, hi, 8))
	t.set_stylebox("hover", "PrimaryButton", box(hi.lightened(0.12), hi, 8))
	t.set_stylebox("pressed", "PrimaryButton", box(hi.darkened(0.15), hi, 8))
	t.set_stylebox("hover_pressed", "PrimaryButton", box(hi.darkened(0.15), hi, 8))
	t.set_stylebox("disabled", "PrimaryButton", box(Palette.with_alpha(hi, 0.35), Palette.with_alpha(hi, 0.35), 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		t.set_color(k, "PrimaryButton", Palette.VOID)
	t.set_font_size("font_size", "PrimaryButton", 18)
	# The boxes (PanelContainer looks): fill colour and see-through amount,
	# a 1-pixel LINE border, and the space inside (see box()).
	for look: Array in PANEL_LOOKS:
		t.set_type_variation(look[0], "PanelContainer")
		t.set_stylebox("panel", look[0], box(Palette.with_alpha(look[1], look[2]), Palette.LINE, look[3]))
	return t


## A box style: fill colour `bg`, a 1-pixel `border`, corners rounded by
## 4 pixels, and `pad` pixels of space inside (2 more on the left and
## right).
static func box(bg: Color, border: Color, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = pad + 2
	s.content_margin_right = pad + 2
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


## A label with `text` at font `size` (pixels) in `color`. With `wrap`, long
## text breaks onto new lines between words. Labels let the mouse pass
## through.
static func label(text: String, size: int = 15, color: Color = Palette.ICE, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A button showing `text` that calls `on_press` when clicked, at least
## `min_h` pixels tall. It never takes keyboard focus.
static func button(text: String, on_press: Callable, min_h: float = 36.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, min_h)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(on_press)
	return b


## Make progress bar `p` fill with `color` (for bars whose colour depends
## on the team, set in code after the scene is loaded).
static func tint_bar(p: ProgressBar, color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	p.add_theme_stylebox_override("fill", fill)


## A column that stacks its children top to bottom, `sep` pixels apart.
static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## A row that lines its children up left to right, `sep` pixels apart.
static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


## Small capital-letters section heading (12 px, grey).
static func heading(text: String) -> Label:
	return label(text.to_upper(), 12, Palette.MIST)


## A panel (a box that holds one child) with `pad` pixels of space inside.
## It takes mouse clicks, so clicks on it don't reach the game.
static func panel(pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.add_theme_stylebox_override("panel", box(Palette.with_alpha(Palette.PANEL, 0.95), Palette.LINE, pad))
	return p


## A scroll area that scrolls up and down only, and takes the spare height.
static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	return s


## Set label (or button) `l`'s text only when it changed, so the
## 10-times-a-second refreshes don't make Godot lay the screen out again.
static func set_text(l, text: String) -> void:
	if l.text != text:
		l.text = text


## The width big panel `c` is meant to have: the window's width less its
## left and right margins (HudPanels.panel_rect sets them). Panels size their
## cards and paragraphs from this and not from their own `size`: a panel is
## at least as wide as the cards inside it, so its `size` can never get
## smaller after the window shrinks.
static func panel_width(c: Control) -> float:
	return c.get_viewport_rect().size.x + c.offset_right - c.offset_left


## Give a wrapping label a fixed width `w` (at least 40 pixels). A wrapping
## label measures its height at its current width, which is zero until it
## is first laid out, so without this it would come out far too tall.
static func pin_width(l: Label, w: float) -> void:
	w = maxf(40.0, w)
	if absf(l.custom_minimum_size.x - w) > 0.5:
		l.custom_minimum_size = Vector2(w, 0)
