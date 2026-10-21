class_name AdmiralBoard
extends PanelContainer
## WHAT THIS IS: the human Admiral's command board, the big panel that
## opens with Tab. From it the Admiral spends the team treasury (the
## team's shared money) and picks map tools. DESIGN.md A11-A13, A15.
##
## HOW IT WORKS: the frame that never changes is the scene
## scenes/ui/admiral_board.tscn: a nearly solid dark box (the "BoardLook"
## look) that takes mouse clicks and wheel turns, so they don't reach the
## map (the scene turns off mouse_force_pass_scroll_events, so a wheel
## turn the list cannot use stops here instead of zooming the camera;
## tests/wheel_check.gd checks it). It holds one column, Col, with these
## rows from top to bottom:
##   Head (Texts (Title, Status), Close): the title with the treasury, the
##     status line under it (what is building and researching), and Close
##     (at least 40 pixels tall);
##   Away: the amber note shown while the Admiral is out flying their own
##     ship;
##   Tabs (Research, Build, Mothership, Fleet, Pilots): one button per tab
##     (page), 120 pixels wide; each button's text is its tab's name;
##   Scroll > Content: the scroll area (at least 120 pixels tall) and the
##     column inside it that holds the current tab's cards;
##   Detail: the details line (at least 36 pixels tall), which explains the
##     last card or button the mouse moved onto.
## Only one tab shows at a time:
##   Research    - mothership modules (facilities) on top, then the
##                 Homeworld 2 style research board: one column per
##                 facility. (AdmiralBoardResearch)
##   Build       - mining drones, turrets at each node, repair bays, wards.
##                 (AdmiralBoardBuild)
##   Mothership  - status, upgrades, moving it (from 20:00).
##                 (AdmiralBoardMothership)
##   Fleet       - rally waypoint and Fleet Command minion control.
##                 (AdmiralBoardFleet)
##   Pilots      - the scoreboard (scenes/ui/scoreboard.tscn, placed
##                 inside the board).
## A tab's "cards" (its buttons and labels) depend on the game: which
## nodes, techs and minions there are, and how wide the board is. So they
## are made in code: picking a tab (_set_tab) throws the old tab's cards
## away and builds the new tab's cards once. Then, 4 times a second,
## _refresh() rewrites their texts and colours, so prices, timers and
## reasons stay up to date.
## Every action goes through AdmiralCommand (world.command), so the human
## follows the same rules as the AI admiral. Map tools (bay, ward,
## waypoint, move, fleet orders) "arm" the CommandOverlay (the Admiral's
## clickable map layer) and close the board, so the Admiral can click the
## map. The Admiral can command while flying their own ship, except moving
## the mothership, which needs them docked.
##
## WHO USES IT: the HUD makes it from scenes/ui/admiral_board.tscn
## (HudPanels.toggle_board), calls setup(), hides it on `closed` and
## `tool_armed`, and calls _set_tab(tab) again when the board's width
## changes by more than 20 pixels (so the cards fit the new width).
## tests/ui_tour.gd calls _set_tab() to visit each tab. Each tab's cards
## are built and refreshed by its own static library (see above, files
## scripts/ui/admiral_board_*.gd); they read this board's fields (world,
## team, overlay, _content, _cards) directly.

## Sent when the board wants to close (the Close button, or a "View"
## button moved the camera). The HUD then hides the board.
signal closed
## Sent when a map tool was armed; `tool` is its name ("bay", "ward",
## "waypoint", "move", "fleet_move" or "fleet_hold"). The HUD then hides
## the board so the Admiral can click the map.
signal tool_armed(tool: String)

## The scoreboard's scene, placed inside the board on the Pilots tab.
const SCOREBOARD_SCENE := preload("res://scenes/ui/scoreboard.tscn")

## The game world (teams, map, AdmiralCommand). Set by setup().
var world: World
## The Admiral's map layer: map tools, the minion selection, and whether
## the human may give orders right now (can_command). Set by setup().
var overlay: CommandOverlay
## The team this board commands: Aurelian (team 0). Nothing changes it.
var team := Rules.HALCYON
## The tab being shown (one tab button's text: "Research", "Build",
## "Mothership", "Fleet" or "Pilots"). The HUD reads it to rebuild the same
## tab after a resize.
var tab := "Research"
## key -> CardButton / Label / Button, refreshed at 4 Hz (4 times a
## second). Each key starts with what it is, e.g. "fac:<facility id>",
## "tech:<tech id>", "node:<node id>", or is a plain name like "drones".
var _cards := {}
## Seconds left until the next refresh (counts down from 0.25).
var _t := 0.0
## The scoreboard on the Pilots tab, or null on the other tabs. (Only
## kept here; nothing else reads it.)
var _scoreboard: Scoreboard = null

## The title line: "Admiral board · treasury N".
@onready var _title: Label = $Col/Head/Texts/Title
## The line under the title: what is building and researching, and how
## many mining drones we have.
@onready var _status: Label = $Col/Head/Texts/Status
## The amber warning shown while the Admiral is out flying their own ship.
@onready var _away: Label = $Col/Away
## The tab buttons in the Tabs row, in the order they appear. Each one's
## text is its tab's name; _set_tab() colours the selected one amber.
@onready var _tab_buttons: Array[Button] = [$Col/Tabs/Research, $Col/Tabs/Build, $Col/Tabs/Mothership, $Col/Tabs/Fleet, $Col/Tabs/Pilots]
## The column inside the scroll area that holds the current tab's cards.
@onready var _content: VBoxContainer = $Col/Scroll/Content
## The details line at the bottom: the details of the last card or button
## the mouse moved onto (it stays after the mouse leaves).
@onready var _detail: Label = $Col/Detail


## Godot calls this when the board joins the HUD (the frame is already
## there, from the scene): Close sends `closed`, and each tab button shows
## the tab it names. The tab contents come later, from _set_tab().
func _ready() -> void:
	$Col/Head/Close.pressed.connect(func() -> void: closed.emit())
	for b in _tab_buttons:
		b.pressed.connect(_set_tab.bind(b.text))


## Connect the board to world `w` and map layer `ov`, then build the
## current tab. The HUD calls this once, right after making the board.
func setup(w: World, ov: CommandOverlay) -> void:
	world = w
	overlay = ov
	_set_tab(tab)


## Show tab `t` (one tab button's text): colour its button amber, throw
## away the old cards, build the new tab's cards and fill them in at once.
## Other files call it too (the HUD after a resize, tests/ui_tour.gd).
func _set_tab(t: String) -> void:
	tab = t
	# Step 1: the selected tab's button gets amber text and border.
	for b in _tab_buttons:
		b.add_theme_color_override("font_color", Palette.AMBER if b.text == t else Palette.ICE)
		b.add_theme_stylebox_override("normal", UiKit.box(Palette.INK, Palette.AMBER if b.text == t else Palette.LINE, 8))
	# Step 2: remove the old cards (queue_free deletes a node at the end of
	# this frame).
	for c in _content.get_children():
		c.queue_free()
	_cards.clear()
	_scoreboard = null
	# Step 3: build the new tab. Each tab's library adds its cards to
	# _content and remembers them in _cards. The Pilots tab is the
	# scoreboard, told it is `embedded` (no box of its own, the mouse passes
	# through) before it joins the board.
	match t:
		"Research":
			AdmiralBoardResearch.build(self)
		"Build":
			AdmiralBoardBuild.build(self)
		"Mothership":
			AdmiralBoardMothership.build(self)
		"Fleet":
			AdmiralBoardFleet.build(self)
		"Pilots":
			_scoreboard = SCOREBOARD_SCENE.instantiate()
			_scoreboard.embedded = true
			_content.add_child(_scoreboard)
			_scoreboard.setup(world)
	# Step 4: fill in the texts straight away.
	_refresh()


## Our team's shared state (treasury, research, buildings and more).
func _ts() -> TeamState:
	return world.teams[team]


## May the human give orders right now? Asks the CommandOverlay
## (can_command); false while there is no overlay.
func _ok() -> bool:
	return overlay != null and overlay.can_command()


## Make control `c` show `text` in the details line when the mouse moves
## onto it.
func _hover(c: Control, text: String) -> void:
	c.mouse_entered.connect(func() -> void: _detail.text = text)


## The width in pixels that a tab's cards may use: the board's width minus
## 50, but never less than 700. The board's width is the one it is meant to
## have (UiKit.panel_width), not its `size`: the cards make the board at
## least as wide as they are, so `size` could never shrink.
func _inner_w() -> float:
	return maxf(700.0, UiKit.panel_width(self) - 50.0)


## Add a grid with `cols` columns and 6-pixel gaps to the tab's content and
## return it. The grid itself ignores the mouse; its cards still get it.
func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(g)
	return g


# --- shared --------------------------------------------------------------------------------

## Arm map tool `tool` (see the tool_armed signal for the names) on the
## CommandOverlay, so the Admiral's next map click uses it. If the overlay
## took it, send tool_armed (the HUD then hides the board). Does nothing
## while the human may not give orders.
func _arm(tool: String) -> void:
	if not _ok():
		return
	overlay.arm(tool)
	if overlay.tool != "":
		tool_armed.emit(tool)


## A "View" button: point the camera at world position `p` and close the
## board. That needs the free camera (C switches to it); otherwise a toast
## (a short message on screen) says so.
func _view(p: Vector2) -> void:
	if world.camera.free:
		world.camera.look_at_point(p)
		closed.emit()
	else:
		Events.toast.emit("Press C to switch to the free camera first.")


## Every frame while the board is shown: count `dt` (seconds since the
## last frame) down and refresh every 0.25 seconds.
func _process(dt: float) -> void:
	if not visible or world == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 0.25
		_refresh()


## Rewrite everything that changes: the title (treasury), the status line,
## the "away" warning, and the current tab's cards. (The Pilots tab has
## nothing to refresh here.)
func _refresh() -> void:
	if world == null:
		return
	var ts := _ts()
	UiKit.set_text(_title, "Admiral board  ·  treasury %s" % Util.money(ts.treasury))
	# Step 1: the status line: the facility building now (first in its
	# queue) and the research running now, with seconds left.
	var bits: Array = []
	if not ts.building.is_empty():
		var b: Dictionary = ts.building[0]
		bits.append("Building %s (%ds)" % [Tech.FACILITIES[b["id"]]["label"], int(ceil(float(b["left"])))])
	if not ts.research.is_empty():
		var r: Dictionary = ts.research[0]
		var s := "Researching %s (%ds)" % [Tech.TECHS[r["id"]]["label"], int(ceil(float(r["left"])))]
		if ts.research.size() > 1:
			s += " +%d queued" % (ts.research.size() - 1)
		bits.append(s)
	# Step 2: "nothing going on", then the drone count, joined with dots.
	if bits.is_empty():
		bits.append("Nothing building or researching")
	bits.append("%d drones" % world.mining_drone_count(team))
	UiKit.set_text(_status, "  ·  ".join(bits))
	_away.visible = not ts.admiral_docked
	# Step 3: the current tab's own cards.
	match tab:
		"Research":
			AdmiralBoardResearch.refresh(self)
		"Build":
			AdmiralBoardBuild.refresh(self)
		"Mothership":
			AdmiralBoardMothership.refresh(self)
		"Fleet":
			AdmiralBoardFleet.refresh(self)
