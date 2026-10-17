class_name CommandOverlay
extends Node2D
## WHAT THIS IS: the human Admiral's "map tools": placing a repair bay or a
## ward, setting the rally waypoint, moving the mothership, and giving
## orders to minions by clicking on the map. DESIGN.md A15.
##
## HOW IT WORKS: the Admiral board "arms" a tool (arm). The next left click
## on the map (or on the minimap) carries it out through AdmiralCommand
## (world.command), which checks whether it is allowed and reports back via
## Events.admiral_result. A right click or Esc "disarms" it (cancels it).
## Tools: "bay" (deploy a repair bay), "ward", "waypoint", "move" (the
## mothership), "fleet_move" / "fleet_hold" (selected minions).
## With the Fleet Command module and no tool armed, the Admiral can drag a
## box on the map to select our minions, and right-click to send the
## selection there.
## This node lives under World (not under the HUD), so it draws in world
## positions and gets the clicks the HUD's buttons didn't take, before the
## ship's guns do. For everyone it also draws the team's rally waypoint
## (CommandOverlayDraw does all the drawing).
##
## WHO USES IT: Hud makes it from scenes/ui/command_overlay.tscn (hud.overlay).
## AdmiralBoard arms tools and uses select_all(), order_lane(), selected and
## can_command(); Minimap calls apply_at() and order_at(); HudInput and
## HudBanner use tool, disarm() and hint(); tests/ui_tour.gd arms "bay".

## The instruction shown while each tool is armed (on the banner and next
## to the mouse).
const TOOL_TEXT := {
	"bay": "Click where the repair bay should anchor",
	"ward": "Click a spot your team can see to place a ward",
	"waypoint": "Click to set the rally waypoint",
	"move": "Click a spot in a lane to move the mothership",
	"fleet_move": "Click where the selected minions should fly",
	"fleet_hold": "Click where the selected minions should hold",
}

## The game world (set by setup()).
var world: World
## The team these tools command: the human Admiral is always Aurelian.
var team := Rules.HALCYON
## The armed tool's name (see TOOL_TEXT), or "" when none is armed.
var tool := ""
## The minions the Admiral has selected (may hold destroyed ones until
## _live_selection() tidies the list).
var selected: Array = []
## Where a box-select drag started (world position), or Vector2.INF
## ("infinity", meaning no drag is happening).
var _drag_from := Vector2.INF
## Where the box-select drag is now (world position).
var _drag_to := Vector2.ZERO
## The font for labels drawn on the map (Godot's built-in default font).
var _font: Font


## Remember the world, and draw above most of the game (z_index 20: a
## higher z_index draws on top).
func setup(w: World) -> void:
	world = w
	team = Rules.HALCYON
	z_index = 20
	_font = ThemeDB.fallback_font


## Is the human playing as the Admiral?
func is_admiral() -> bool:
	return world != null and world.human_role == "admiral"


## The Admiral commands from anywhere, even while flying their own ship
## (only moving the mothership needs them docked: AdmiralCommand checks).
func can_command() -> bool:
	return is_admiral() and world.phase == "play"


## Arm tool `t`, so the next map click uses it. The fleet tools need some
## minions selected first; without any, a hint pops up and nothing is armed.
func arm(t: String) -> void:
	if not can_command():
		return
	tool = t
	if t.begins_with("fleet") and _live_selection().is_empty():
		Events.toast.emit("Select minions first: drag a box around them on the map.")
		tool = ""


## Cancel the armed tool and any box-select drag.
func disarm() -> void:
	tool = ""
	_drag_from = Vector2.INF


## The banner text while a tool is armed ("" when none is).
func hint() -> String:
	if tool == "":
		return ""
	return "%s.  Right-click or Esc to cancel." % tool_text()


## The instruction for the armed tool: its line in TOOL_TEXT, or (for the
## orders that feature modules add, see CommandOrders) the order's hint,
## else "Click the map".
func tool_text() -> String:
	if TOOL_TEXT.has(tool):
		return TOOL_TEXT[tool]
	var h := CommandOrders.hint(world, tool)
	return h if h != "" else "Click the map"


## Why the armed tool can't go at world point `p` (AdmiralCommand's
## reason), or "" when it can. The mothership also refuses the jungle.
func blocker_at(p: Vector2) -> String:
	var cmd := world.command
	match tool:
		"bay":
			return cmd.bay_blocker(team, p)
		"ward":
			return cmd.ward_blocker(team, p)
		"move":
			var b := cmd.move_blocker(team)
			if b == "" and not world.map.in_open_lane(p):
				b = "Too big for the jungle: pick a lane or the base"
			return b
		_:
			# An order that a feature module added (CommandOrders).
			if world.command.orders.has(tool):
				return CommandOrders.blocker(world, tool, team, p)
	return ""


## Carry out the armed tool at world point `p` (a map click or a minimap
## click). AdmiralCommand returns "" when the order worked: then the tool
## is used up. On a refusal the tool stays armed so the Admiral can try
## another spot.
func apply_at(p: Vector2) -> void:
	if not can_command():
		disarm()
		return
	var cmd := world.command
	var msg := ""
	match tool:
		"bay":
			msg = cmd.deploy_bay(team, p)
		"ward":
			msg = cmd.place_ward(team, p)
		"waypoint":
			msg = cmd.set_waypoint(team, p)
		"move":
			msg = cmd.move_mothership(team, p)
		"fleet_move":
			msg = cmd.order_minions(team, _live_selection(), {"type": "move", "pos": p})
		"fleet_hold":
			msg = cmd.order_minions(team, _live_selection(), {"type": "hold", "pos": p})
		_:
			# An order that a feature module added (CommandOrders).
			if cmd.orders.has(tool):
				msg = CommandOrders.run(world, tool, team, p)
	if msg == "":
		tool = ""


## A right click at world point `p`: cancels an armed tool; otherwise, with
## Fleet Command and some minions selected, sends them to fly there.
func order_at(p: Vector2) -> void:
	if tool != "":
		disarm()
		return
	if can_command() and world.minion_director.controlled(team) and not _live_selection().is_empty():
		world.command.order_minions(team, _live_selection(), {"type": "move", "pos": p})


## Send the selected minions down lane `lane` ("top", "mid" or "bot").
func order_lane(lane: String) -> void:
	if can_command():
		world.command.order_minions(team, _live_selection(), {"type": "lane", "lane": lane})


## Select every live minion of our team.
func select_all() -> void:
	selected.clear()
	for m: Minion in world.minions:
		if m.team == team and m.alive:
			selected.append(m)


## The selected minions that still exist and are alive. Also tidies
## `selected` so it holds only those.
func _live_selection() -> Array:
	var out: Array = []
	for m in selected:
		if m != null and is_instance_valid(m) and m.alive:
			out.append(m)
	selected = out
	return out


## Mouse clicks on the map that no button took (only for the Admiral):
## left click uses the armed tool, or starts / ends a box-select drag;
## right click cancels the tool, or orders the selection to fly there.
## Each click we use is marked "handled" so the ship's guns don't fire.
func _unhandled_input(event: InputEvent) -> void:
	if world == null or not is_admiral():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var p := get_global_mouse_position()
		# Left button: use the tool, start a drag, or finish the drag.
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and tool != "":
				apply_at(p)
				get_viewport().set_input_as_handled()
			elif mb.pressed and _fleet_select_allowed():
				_drag_from = p
				_drag_to = p
				get_viewport().set_input_as_handled()
			elif not mb.pressed and _drag_from != Vector2.INF:
				_finish_drag()
				get_viewport().set_input_as_handled()
		# Right button: cancel the tool, or send the selection.
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if tool != "":
				disarm()
				get_viewport().set_input_as_handled()
			elif _fleet_select_allowed() and not _live_selection().is_empty():
				order_at(p)
				get_viewport().set_input_as_handled()
	# Moving the mouse during a drag stretches the box.
	elif event is InputEventMouseMotion and _drag_from != Vector2.INF:
		_drag_to = get_global_mouse_position()


## Box select only while the admiral is in the chair (not flying a ship:
## then the camera follows their ship and left click fires the guns).
func _fleet_select_allowed() -> bool:
	return can_command() and world.minion_director.controlled(team) and world.camera.followed() == null


## The drag ended: select our live minions inside the box. A tiny box
## (diagonal under 60 world units, i.e. a plain click) is grown by 250 on
## every side so a click near some minions still picks them up.
func _finish_drag() -> void:
	var r := Rect2(_drag_from, Vector2.ZERO).expand(_drag_to)
	_drag_from = Vector2.INF
	if r.size.length() < 60.0:
		r = r.grow(250.0)
	selected.clear()
	for m: Minion in world.minions:
		if m.team == team and m.alive and r.has_point(m.global_position):
			selected.append(m)
	Events.toast.emit("%d minions selected. Right-click to send them, or use the Fleet tab." % selected.size())


## Every frame: ask Godot to redraw us (queue_redraw makes it call _draw).
func _process(_dt: float) -> void:
	if world != null:
		queue_redraw()


## Draw the waypoint, the Admiral's marks and the armed tool's preview.
## The real code is in CommandOverlayDraw.draw().
func _draw() -> void:
	CommandOverlayDraw.draw(self)
