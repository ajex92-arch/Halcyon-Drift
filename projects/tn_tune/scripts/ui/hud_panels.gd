class_name HudPanels
extends RefCounted
## WHAT THIS IS: the part of the HUD that opens and closes the big panels
## that cover the screen: the hangar, the Admiral board, the scoreboard and
## the help pages. Only one of them is open at a time.
##
## HOW IT WORKS: each panel is made from its scene file the first time it
## is needed, and after that it is only shown or hidden. Opening a panel
## hides the others (close_others). The hangar and the Admiral board lay
## out their cards for their own width, so when the window is resized and
## a panel's width changes by more than 20 pixels, the panel rebuilds its
## current tab.
##
## WHO USES IT: Hud makes one (hud.panels) and forwards _open_hangar(),
## _toggle_board(), _show_scoreboard(), _toggle_help(), _close_others() and
## _any_panel_open() here. The panels themselves are kept on the Hud
## (hud.hangar, hud.board, hud.scoreboard, hud.help), because HudInput,
## HudBanner and tests/ui_tour.gd read them there.

## The hangar panel's scene (scenes/ui/hangar.tscn).
const HANGAR_SCENE := preload("res://scenes/ui/hangar.tscn")
## The Admiral board's scene.
const BOARD_SCENE := preload("res://scenes/ui/admiral_board.tscn")
## The scoreboard's scene.
const SCORE_SCENE := preload("res://scenes/ui/scoreboard.tscn")
## The help pages' scene.
const HELP_SCENE := preload("res://scenes/ui/help_panel.tscn")

## The HUD this part belongs to (we add the panels to it and store them
## in its hangar / board / scoreboard / help variables).
var hud: Hud
## The hangar's width (pixels) when its cards were last laid out.
var _hangar_w := 0.0
## The Admiral board's width (pixels) when its cards were last laid out.
var _board_w := 0.0


## Remember which HUD we belong to.
func _init(owner: Hud) -> void:
	hud = owner


## Stretch panel `c` over the whole window, leaving a gap of `margin`
## pixels (x = left and right, y = top and bottom).
func panel_rect(c: Control, margin: Vector2) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = margin.x
	c.offset_right = -margin.x
	c.offset_top = margin.y
	c.offset_bottom = -margin.y


## Show the hangar (making it first if needed) and hide the other panels.
## Does nothing when there is no human pilot profile (a spectator).
func open_hangar() -> void:
	var world := hud.world
	if world.human == null:
		return
	# Step 1: first time only: make the hangar, 70 pixels in from the edges.
	if hud.hangar == null:
		hud.hangar = HANGAR_SCENE.instantiate()
		hud.add_child(hud.hangar)
		panel_rect(hud.hangar, Vector2(70, 70))
		hud.hangar.setup(world, world.human)
		hud.hangar.closed.connect(func() -> void: hud.hangar.visible = false)
		hud.hangar.resized.connect(_rebuild_hangar_cards)
	# Step 2: show it alone.
	hud.hangar.visible = true
	close_others(hud.hangar)


## The hangar changed size: when its width changed by more than 20 pixels,
## rebuild its current tab so the cards fit the new width.
func _rebuild_hangar_cards() -> void:
	if hud.hangar != null and absf(hud.hangar.size.x - _hangar_w) > 20.0:
		_hangar_w = hud.hangar.size.x
		hud.hangar._set_tab(hud.hangar.tab)


## Show the Admiral board if hidden, or hide it if showing (making it first
## if needed). Opening it cancels any armed map tool and hides the others.
## Arming a map tool on the board hides the board, so you can click the map.
func toggle_board() -> void:
	# Step 1: first time only: make the board (24 / 40 pixels in from the
	# edges), hidden, and rebuild its tab when its width changes by > 20.
	if hud.board == null:
		hud.board = BOARD_SCENE.instantiate()
		hud.add_child(hud.board)
		panel_rect(hud.board, Vector2(24, 40))
		hud.board.setup(hud.world, hud.overlay)
		hud.board.closed.connect(func() -> void: hud.board.visible = false)
		hud.board.tool_armed.connect(func(_t: String) -> void: hud.board.visible = false)
		hud.board.visible = false
		hud.board.resized.connect(func() -> void:
			if absf(hud.board.size.x - _board_w) > 20.0:
				_board_w = hud.board.size.x
				hud.board._set_tab(hud.board.tab))
	# Step 2: flip it.
	hud.board.visible = not hud.board.visible
	if hud.board.visible:
		hud.overlay.disarm()
		close_others(hud.board)


## Show (`on` = true) or hide the scoreboard, making it first if needed.
## It sits in the middle of the window, sized to its contents. Pilots see
## it only while they hold Tab, so this doesn't close other panels.
func show_scoreboard(on: bool) -> void:
	if hud.scoreboard == null:
		hud.scoreboard = SCORE_SCENE.instantiate()
		hud.add_child(hud.scoreboard)
		hud.scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		hud.scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
		hud.scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
		hud.scoreboard.setup(hud.world)
	hud.scoreboard.visible = on


## Show the help pages if hidden, or hide them if showing (making them
## first if needed, 110 / 60 pixels in from the edges). Opening them hides
## the other panels.
func toggle_help() -> void:
	if hud.help == null:
		hud.help = HELP_SCENE.instantiate()
		hud.add_child(hud.help)
		panel_rect(hud.help, Vector2(110, 60))
		hud.help.closed.connect(func() -> void: hud.help.visible = false)
		hud.help.visible = false
	hud.help.visible = not hud.help.visible
	if hud.help.visible:
		close_others(hud.help)


## Hide every big panel except `keep` (pass null to hide them all). Panels
## that were never made are skipped.
func close_others(keep: Control) -> void:
	for c: Control in [hud.hangar, hud.board, hud.help, hud.scoreboard]:
		if c != null and c != keep:
			c.visible = false


## Is any big panel showing right now? (HudToast moves its pop-up out of
## the way when one is.)
func any_open() -> bool:
	for c: Control in [hud.hangar, hud.board, hud.help, hud.scoreboard]:
		if c != null and c.visible:
			return true
	return false
