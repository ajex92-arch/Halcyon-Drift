class_name CommandOrders
extends RefCounted
## WHAT THIS IS: the shared "order desk" that the admiral_command feature
## modules (Sensor Sweep, Supply Drop, Barrage, Bounty, Fortify) plug their
## orders into. It gives every such order the same treatment: a price, a
## cooldown per team, the rule checks, a news line, a button on the admiral
## board, a map tool, a status tag on the top bar, a mark on the map and the
## minimap, and a line in the help panel. A human admiral and the AI admiral
## both give an order through run(), so they play by the same rules.
##
## HOW IT WORKS: a feature module calls add() once with a Dictionary that
## describes its order (the keys are listed at add()). The description is
## kept in world.command.orders (AdmiralCommand.orders), which is empty in
## today's game. run() does the common steps: check the cooldown and the
## price (blocker()), pay from the treasury, let the order's own `run`
## function carry it out, start the cooldown and send
## Events.admiral_result (action = the order's id), which the HUD shows
## to a human admiral. Marks (rings drawn on the map and minimap) are
## kept in world.command.marks; add_mark() makes one and prune() drops the
## old ones.
## An order is given an id such as "sweep". The ids used by the modules:
## "sweep", "supply", "barrage" (AdmiralAssetsFeature), "bounty"
## (AdmiralOrdersFeature) and "fortify" (FortifyFeature).
##
## WHO USES IT: the feature modules (add, run, add_mark, prune), the AI
## parts that give orders (run, ready_in), CommandOrdersUi (the board
## buttons), CommandOverlay (the map tool: hint, radius, blocker, run),
## CommandOverlayDraw and Minimap (draw_marks, draw_minimap), HudTopBar
## (hud_tag) and HelpPanel (help_entries).
## This is a "static library": no state of its own, so you call it on the
## class name (CommandOrders.run(...)).


## Register an order in `world`. `def` is a Dictionary with these keys
## (the ones marked * are needed):
##   id *          the order's name, also its Events.admiral_result action
##   label *       the name on the button ("Sensor Sweep")
##   hint *        the instruction shown while the map tool is armed
##   tip           a longer description for the board's details line
##   help          a paragraph for the help panel (the Admiral page)
##   cost          credits taken from the treasury when it is given (0)
##   cost_fn       a Callable(team) -> credits, instead of `cost`
##   cooldown      seconds before the same team may use it again (0)
##   needs_point   true = the admiral clicks a spot first (a map tool)
##   radius        the ring drawn at the mouse while the tool is armed
##   blocker       a Callable(team, point) -> "" or the reason it can't go
##   run *         a Callable(team, point, paid) that carries the order out
##                 (`paid` is the price just taken from the treasury)
##   tag           a Callable(team, viewer_team) -> short status text for the
##                 top bar ("" for none)
##   color         the order's colour on the map
## The cooldown clock is kept in the entry ("ready_at": one time per team).
static func add(world: World, def: Dictionary) -> void:
	var d := def.duplicate()
	d["ready_at"] = [0.0, 0.0]
	world.command.orders[str(def["id"])] = d


## The price of order `d` for `team` in credits: cost_fn if there is one,
## else cost, else 0.
static func cost_of(d: Dictionary, team: int) -> float:
	if d.has("cost_fn"):
		return float((d["cost_fn"] as Callable).call(team))
	return float(d.get("cost", 0.0))


## Seconds until `team` may use order `id` again (0 = ready now).
static func ready_in(world: World, id: String, team: int) -> float:
	if not world.command.orders.has(id):
		return 0.0
	var d: Dictionary = world.command.orders[id]
	return maxf(0.0, float((d["ready_at"] as Array)[team]) - world.time)


## Make the cooldown of order `id` for `team` end right now (Fortify uses it
## when a team loses its first inner turret).
static func reset_cooldown(world: World, id: String, team: int) -> void:
	if world.command.orders.has(id):
		var d: Dictionary = world.command.orders[id]
		(d["ready_at"] as Array)[team] = 0.0


## Why `team` can't give order `id` at `p` right now, or "" if it can. It
## checks that the order exists, its cooldown and its price, then the
## order's own rules (its `blocker` function).
static func blocker(world: World, id: String, team: int, p: Vector2) -> String:
	if not world.command.orders.has(id):
		return "No such order"
	var d: Dictionary = world.command.orders[id]
	# Step 1: the cooldown.
	var wait := ready_in(world, id, team)
	if wait > 0.0:
		return "%s is recharging (%ds)" % [d["label"], int(ceil(wait))]
	# Step 2: the price.
	var cost := cost_of(d, team)
	var ts := world.teams[team]
	if not ts.can_afford(cost):
		return "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury))
	# Step 3: the order's own rules.
	if d.has("blocker"):
		return str((d["blocker"] as Callable).call(team, p))
	return ""


## Give order `id` for `team` at point `p` (ignored by orders that need no
## point). Returns "" when it worked, or the reason it did not. A refusal
## costs nothing. On success: pay, carry the order out, start the cooldown
## and tell the HUD (Events.admiral_result, plus a pop-up for the human).
static func run(world: World, id: String, team: int, p: Vector2) -> String:
	var b := blocker(world, id, team, p)
	if b != "":
		Events.admiral_result.emit(team, id, false, b)
		return b
	var d: Dictionary = world.command.orders[id]
	# Step 1: pay, then carry the order out.
	var ts := world.teams[team]
	var cost := cost_of(d, team)
	ts.spend(cost)
	(d["run"] as Callable).call(team, p, cost)
	# Step 2: start the cooldown.
	(d["ready_at"] as Array)[team] = world.time + float(d.get("cooldown", 0.0))
	# Step 3: tell everyone who listens. The human admiral (Halcyon) gets a
	# short pop-up.
	Events.admiral_result.emit(team, id, true, "")
	if world.human_role == "admiral" and team == Rules.HALCYON:
		Events.toast.emit("%s ordered." % d["label"])
	return ""


## The instruction to show while map tool `id` is armed ("" if unknown).
static func hint(world: World, id: String) -> String:
	if world.command.orders.has(id):
		return str((world.command.orders[id] as Dictionary)["hint"])
	return ""


## The ring radius (world units) to draw at the mouse while tool `id` is
## armed: the order's `radius`, or 300 when it has none.
static func radius(world: World, id: String) -> float:
	if world.command.orders.has(id):
		return float((world.command.orders[id] as Dictionary).get("radius", 300.0))
	return 300.0


## True if `id` is a registered order that needs a clicked point.
static func needs_point(world: World, id: String) -> bool:
	return world.command.orders.has(id) and bool((world.command.orders[id] as Dictionary).get("needs_point", false))


# --- marks ---------------------------------------------------------------------------------

## Add a mark to the map and the minimap. `m` is a Dictionary:
##   pos      the world position (used when there is no `unit`)
##   unit     optional: a Unit the mark follows (the mark ends when it dies)
##   r        ring radius in world units
##   col      the colour
##   until    match time (seconds) when it ends
##   teams    the teams that see it, for example [0, 1] for both
##   label    optional text above the ring
##   kind     "ring" | "fill" (ring plus a faint disc) | "shimmer" (a pulsing
##            ring) | "gold" (a gold diamond: a bounty)
## Old marks are dropped first. Returns the mark.
static func add_mark(world: World, m: Dictionary) -> Dictionary:
	prune(world)
	world.command.marks.append(m)
	return m


## Drop marks that have run out or whose unit is gone.
static func prune(world: World) -> void:
	var keep: Array = []
	for m: Dictionary in world.command.marks:
		if world.time >= float(m["until"]):
			continue
		if m.has("unit"):
			var u: Variant = m["unit"]
			if u == null or not is_instance_valid(u) or not (u as Unit).alive:
				continue
		keep.append(m)
	world.command.marks = keep


## Where mark `m` is now (its unit's place, or its own `pos`).
static func mark_pos(m: Dictionary) -> Vector2:
	if m.has("unit") and m["unit"] != null and is_instance_valid(m["unit"]):
		return (m["unit"] as Unit).global_position
	return m["pos"]


## Does viewer team `vt` see mark `m`? (-1 = a spectator sees everything.)
static func mark_visible(m: Dictionary, vt: int) -> bool:
	return vt < 0 or (m["teams"] as Array).has(vt)


## Draw every mark `vt` can see on the map layer `ov` (CommandOverlay).
## `px` is how many world units one screen pixel covers, so lines and text
## keep their size at any zoom. CommandOverlayDraw calls this.
static func draw_marks(ov: CommandOverlay, vt: int, px: float) -> void:
	var world := ov.world
	for m: Dictionary in world.command.marks:
		if world.time >= float(m["until"]) or not mark_visible(m, vt):
			continue
		var p := mark_pos(m)
		var col: Color = m["col"]
		var r := float(m["r"])
		match str(m.get("kind", "ring")):
			"fill":
				ov.draw_circle(p, r, Palette.with_alpha(col, 0.18))
				ov.draw_arc(p, r, 0.0, TAU, 64, col, 2.5 * px, true)
			"shimmer":
				var a := 0.35 + 0.25 * sin(world.time * 9.0)
				ov.draw_arc(p, r, 0.0, TAU, 32, Palette.with_alpha(col, a), 3.0 * px, true)
			"gold":
				var s := 26.0 * px
				var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0), p + Vector2(0, -s)])
				ov.draw_polyline(pts, col, 3.0 * px, true)
				ov.draw_arc(p, r, 0.0, TAU, 32, Palette.with_alpha(col, 0.5), 2.0 * px, true)
			_:
				ov.draw_arc(p, r, 0.0, TAU, 64, col, 2.0 * px, true)
		if str(m.get("label", "")) != "":
			CommandOverlayDraw._label(ov, p + Vector2(0, -r - 30.0 * px), str(m["label"]), col, px)


## Draw every mark `vt` can see on the minimap `mm`: a ring as big as the
## mark (but at least 3 pixels), or a small diamond for a bounty.
static func draw_minimap(mm: Minimap, vt: int) -> void:
	var world := mm.world
	for m: Dictionary in world.command.marks:
		if world.time >= float(m["until"]) or not mark_visible(m, vt):
			continue
		var c := mm.to_map(mark_pos(m))
		var col: Color = m["col"]
		if str(m.get("kind", "ring")) == "gold":
			var s := 4.0
			mm.draw_polyline(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0), c + Vector2(0, -s)]), col, 1.5, true)
		else:
			mm.draw_arc(c, maxf(3.0, float(m["r"]) * mm.k), 0.0, TAU, 20, col, 1.5, true)


# --- tags and help -----------------------------------------------------------------------------

## The status text that the top bar adds to team `team`'s name line, for
## the viewer `viewer` ("" when no order has anything to say): every
## registered order's `tag` function, joined by spaces.
static func hud_tag(world: World, team: int, viewer: int) -> String:
	var out := ""
	for id in world.command.orders:
		var d: Dictionary = world.command.orders[id]
		if d.has("tag"):
			var t := str((d["tag"] as Callable).call(team, viewer))
			if t != "":
				out += "  " + t
	return out


## The help paragraphs of the registered orders, as [heading, paragraph]
## pairs for the Admiral page of the help panel. Empty when no order is
## registered or there is no match.
static func help_entries() -> Array:
	var out: Array = []
	var world := Game.world as World
	if world == null or world.command == null:
		return out
	for id in world.command.orders:
		var d: Dictionary = world.command.orders[id]
		if d.has("help"):
			out.append([str(d["label"]), str(d["help"])])
	return out
