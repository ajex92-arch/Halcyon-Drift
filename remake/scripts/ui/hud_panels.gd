class_name HudPanels
extends RefCounted
## WHAT THIS IS: the part of the HUD that opens and closes the big panels
## that cover the screen: the hangar, the Admiral board, the scoreboard and
## the help pages. Only one of them is open at a time.
##
## HOW IT WORKS: each panel is made from its scene file the first time it
## is needed, and after that it is only shown or hidden. Opening a panel
## hides the others (close_others). Where a panel sits: its side margins
## are fixed (the hangar 70 pixels in from the side edges, the board 24, the
## help 110), and its top and bottom come from HudLayout, so a panel starts
## under the top bar and the "me" panel and leaves a strip at the bottom for
## the pop-up hint (relayout() moves them when those change). The pieces of
## the HUD that a panel would cover are hidden while it is open (HudLayout).
## The hangar, the Admiral board and the
## help lay out their cards and paragraphs for their own width. That width
## is the window's width less the panel's side margins (UiKit.panel_width()), never
## the panel's current size: a panel is at least as wide as its cards, so a
## size measured from the panel itself could never get smaller again after
## the window shrank. When the window is resized and a panel's width changes
## by more than 20 pixels, the panel rebuilds its current tab.
##
## WHO USES IT: Hud makes one (hud.panels) and forwards _open_hangar(),
## _toggle_board(), _show_scoreboard(), _toggle_help(), _close_others() and
## _any_panel_open() here. The panels themselves are kept on the Hud
## (hud.hangar, hud.board, hud.scoreboard, hud.help), because HudInput,
## HudBanner and tests/ui_tour.gd read them there. HudLayout calls
## relayout().

## The hangar panel's scene (scenes/ui/hangar.tscn).
const HANGAR_SCENE := preload("res://scenes/ui/hangar.tscn")
## The Admiral board's scene.
const BOARD_SCENE := preload("res://scenes/ui/admiral_board.tscn")
## The scoreboard's scene.
const SCORE_SCENE := preload("res://scenes/ui/scoreboard.tscn")
## The help pages' scene.
const HELP_SCENE := preload("res://scenes/ui/help_panel.tscn")

## How far (pixels) each panel keeps in from the left and right edges of
## the window: the hangar's.
const HANGAR_SIDE := 70.0
## The Admiral board's side margin (see HANGAR_SIDE).
const BOARD_SIDE := 24.0
## The help's side margin (see HANGAR_SIDE).
const HELP_SIDE := 110.0

## The HUD this part belongs to (we add the panels to it and store them
## in its hangar / board / scoreboard / help variables).
var hud: Hud
## The hangar's width (pixels) when its cards were last laid out.
var _hangar_w := 0.0
## The Admiral board's width (pixels) when its cards were last laid out.
var _board_w := 0.0
## The help's width (pixels) when its paragraphs were last laid out.
var _help_w := 0.0


## Remember which HUD we belong to, and hear when the window is resized.
func _init(owner: Hud) -> void:
	hud = owner
	hud.resized.connect(on_window_resized)



## Stretch panel `c` over the window, `side` pixels in from the left and
## right edges. Its top and bottom edges are where HudLayout says.
func panel_rect(c: Control, side: float) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = side
	c.offset_right = -side
	c.offset_top = hud.layout.panel_top(side)
	c.offset_bottom = -hud.layout.panel_bottom(true)


## Put the panels' top and bottom edges where HudLayout says (they move when
## the top bar or the "me" panel changes height), centre the scoreboard in
## the room that is left and tell it how tall it may be. Does nothing for a
## panel that is already right.
func relayout() -> void:
	var bottom := hud.layout.panel_bottom(true)
	for pair: Array in [[hud.hangar, HANGAR_SIDE], [hud.board, BOARD_SIDE], [hud.help, HELP_SIDE]]:
		var c: Control = pair[0]
		var top := hud.layout.panel_top(pair[1])
		if c != null and (absf(c.offset_top - top) > 0.5 or absf(c.offset_bottom + bottom) > 0.5):
			c.offset_top = top
			c.offset_bottom = -bottom
	if hud.scoreboard != null:
		# It is centred on the window (its left edge is where that puts it),
		# and the free room is lower than the middle of the window by half the
		# difference of the two gaps.
		var vp := hud.get_viewport_rect().size
		var top := hud.layout.panel_top((vp.x - hud.scoreboard.get_combined_minimum_size().x) * 0.5)
		var room_bottom := hud.layout.panel_bottom(false)
		var shift := (top - room_bottom) * 0.5
		if absf(hud.scoreboard.offset_top - shift) > 0.5:
			hud.scoreboard.offset_top = shift
			hud.scoreboard.offset_bottom = shift
		hud.scoreboard.max_height = vp.y - top - room_bottom


## The window was resized: when a panel's width changed by more than 20
## pixels, rebuild its current tab or page, so the cards fit the new width.
## (Connected to the HUD's own `resized`, which fires on every window size
## change; a panel's own `resized` does not fire when it cannot shrink.)
func on_window_resized() -> void:
	if hud.hangar != null and absf(UiKit.panel_width(hud.hangar) - _hangar_w) > 20.0:
		_hangar_w = UiKit.panel_width(hud.hangar)
		hud.hangar._set_tab(hud.hangar.tab)
	if hud.board != null and absf(UiKit.panel_width(hud.board) - _board_w) > 20.0:
		_board_w = UiKit.panel_width(hud.board)
		hud.board._set_tab(hud.board.tab)
	if hud.help != null and absf(UiKit.panel_width(hud.help) - _help_w) > 20.0:
		_help_w = UiKit.panel_width(hud.help)
		hud.help.rebuild()


## Show the hangar (making it first if needed) and hide the other panels.
## Does nothing when there is no human pilot profile (a spectator).
func open_hangar() -> void:
	var world := hud.world
	if world.human == null:
		return
	# Step 1: first time only: make the hangar, 70 pixels in from the sides.
	if hud.hangar == null:
		hud.hangar = HANGAR_SCENE.instantiate()
		hud.add_child(hud.hangar)
		panel_rect(hud.hangar, HANGAR_SIDE)
		_hangar_w = UiKit.panel_width(hud.hangar)
		hud.hangar.setup(world, world.human)
		hud.hangar.closed.connect(func() -> void: hud.hangar.visible = false)
	# Step 2: show it alone.
	hud.hangar.visible = true
	close_others(hud.hangar)


## Show the Admiral board if hidden, or hide it if showing (making it first
## if needed). Opening it cancels any armed map tool and hides the others.
## Arming a map tool on the board hides the board, so you can click the map.
func toggle_board() -> void:
	# Step 1: first time only: make the board (24 pixels in from the sides),
	# hidden. on_window_resized() rebuilds its tab when the window's width
	# changes by > 20.
	if hud.board == null:
		hud.board = BOARD_SCENE.instantiate()
		hud.add_child(hud.board)
		panel_rect(hud.board, BOARD_SIDE)
		_board_w = UiKit.panel_width(hud.board)
		hud.board.setup(hud.world, hud.overlay)
		hud.board.closed.connect(func() -> void: hud.board.visible = false)
		hud.board.tool_armed.connect(func(_t: String) -> void: hud.board.visible = false)
		hud.board.visible = false
	# Step 2: flip it.
	hud.board.visible = not hud.board.visible
	if hud.board.visible:
		hud.overlay.disarm()
		close_others(hud.board)
	else:
		hud.layout.apply()


## Show (`on` = true) or hide the scoreboard, making it first if needed.
## It sits in the middle of the room the panels have (see relayout()), sized
## to its contents, but never taller than that room (a taller table scrolls
## inside it). Pilots see it only while they hold Tab, so this doesn't close
## other panels.
func show_scoreboard(on: bool) -> void:
	if hud.scoreboard == null:
		hud.scoreboard = SCORE_SCENE.instantiate()
		hud.add_child(hud.scoreboard)
		hud.scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		hud.scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
		hud.scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
		relayout()
		hud.scoreboard.setup(hud.world)
	hud.scoreboard.visible = on
	hud.layout.apply()


## Show the help pages if hidden, or hide them if showing (making them
## first if needed, 110 pixels in from the sides). Opening them hides the
## other panels.
func toggle_help() -> void:
	if hud.help == null:
		# The panel gets its margins BEFORE it joins the HUD: its first page
		# is laid out in _ready(), for the width the margins leave.
		hud.help = HELP_SCENE.instantiate()
		panel_rect(hud.help, HELP_SIDE)
		hud.add_child(hud.help)
		_help_w = UiKit.panel_width(hud.help)
		hud.help.closed.connect(func() -> void: hud.help.visible = false)
		hud.help.visible = false
	hud.help.visible = not hud.help.visible
	if hud.help.visible:
		close_others(hud.help)
	else:
		hud.layout.apply()


## Hide every big panel except `keep` (pass null to hide them all). Panels
## that were never made are skipped. Then the rest of the HUD makes room
## for whatever is left open (HudLayout).
func close_others(keep: Control) -> void:
	for c: Control in [hud.hangar, hud.board, hud.help, hud.scoreboard]:
		if c != null and c != keep:
			c.visible = false
	hud.layout.apply()


## Is any big panel showing right now? (HudToast moves its pop-up out of
## the way when one is.)
func any_open() -> bool:
	for c: Control in [hud.hangar, hud.board, hud.help, hud.scoreboard]:
		if c != null and c.visible:
			return true
	return false
