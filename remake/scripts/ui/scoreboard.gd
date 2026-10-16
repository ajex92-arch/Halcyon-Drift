class_name Scoreboard
extends PanelContainer
## WHAT THIS IS: the table of both teams' pilots: who they are, their ship,
## K/D/A (kills / deaths / assists), minion last hits, derelicts cleared,
## credits earned and what they are doing now.
##
## HOW IT WORKS: the layout is the scene scenes/ui/scoreboard.tscn: a box
## (the "ScoreLook" look) holding one column, Col > HalcyonHead, Halcyon,
## CinderHead, Cinder. Each team has a heading line and a grid (a table)
## whose first row is the column titles (Pilot, Ship, K / D / A, Minions,
## Derelicts, Earned, Status); each title's minimum width in the scene is
## its column's width in pixels. Twice a second while it is on screen,
## _refresh() rewrites the headings (team kills, turrets destroyed,
## mothership hull) and one row per pilot, best first (kills count 3,
## assists 1). Rows are added or removed so each grid always has exactly
## one per pilot; a new cell is as wide as the title at the top of its
## column. An enemy's ship is shown only while our team can see it ("?"
## and "Unseen" otherwise). Your own row is amber, dead pilots grey.
##
## WHO USES IT: HudPanels makes it from scenes/ui/scoreboard.tscn for
## pilots (shown while Tab is held). AdmiralBoard makes one from the same
## scene for its Pilots tab, setting `embedded` first.

## The game world (set by setup()).
var world: World
## True when shown inside another panel (the Admiral board): then it has no
## background box of its own and lets the mouse pass through. Must be set
## before the node joins the scene.
var embedded := false
## Seconds until the next refresh (counts down from 0.5).
var _t := 0.0
## One grid per team (index = team: 0 Halcyon, 1 Cinder). Its first row is
## the column titles.
@onready var _grids: Array[GridContainer] = [$Col/Halcyon, $Col/Cinder]
## One heading label per team.
@onready var _heads: Array[Label] = [$Col/HalcyonHead, $Col/CinderHead]


## Called once when the node joins the scene: inside the Admiral board,
## drop our box and let the mouse pass through; give each team's heading
## the team's colour.
func _ready() -> void:
	if embedded:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for t in 2:
		_heads[t].add_theme_color_override("font_color", Palette.team(t))


## Remember the world and fill the table once.
func setup(w: World) -> void:
	world = w
	_refresh()


## Every frame: while on screen, refresh twice a second (every 0.5 s).
func _process(dt: float) -> void:
	if not is_visible_in_tree() or world == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 0.5
		_refresh()


## Rewrite both teams' headings and rows (see HOW IT WORKS).
func _refresh() -> void:
	if world == null or _grids.is_empty():
		return
	var vt := world.viewer_team
	for t in 2:
		# Step 1: the heading.
		var ts := world.teams[t]
		var ms := world.mothership(t)
		UiKit.set_text(_heads[t], "%s  ·  %d kills  ·  %d turrets destroyed  ·  mothership %d%%" % [Rules.TEAM_NAMES[t], ts.kills, ts.turrets_destroyed, int(ms.hull_frac() * 100.0)])
		# Step 2: this team's pilots, best score first.
		var rows: Array = []
		for p: PilotProfile in world.profiles:
			if p.team == t:
				rows.append(p)
		rows.sort_custom(func(a: PilotProfile, b: PilotProfile) -> bool: return a.kills * 3 + a.assists > b.kills * 3 + b.assists)
		# Step 3: make the grid exactly the right size: the title row plus
		# one row per pilot (each row is one label per column). A new cell
		# copies the size of the title at the top of its column.
		var g := _grids[t]
		var need := (rows.size() + 1) * g.columns
		while g.get_child_count() < need:
			var title: Label = g.get_child(g.get_child_count() % g.columns)
			var l := UiKit.label("", 13, Palette.ICE)
			l.custom_minimum_size = title.custom_minimum_size
			l.clip_text = true
			g.add_child(l)
		while g.get_child_count() > need:
			var last := g.get_child(g.get_child_count() - 1)
			g.remove_child(last)
			last.queue_free()
		# Step 4: fill each pilot's row.
		for r in rows.size():
			var p: PilotProfile = rows[r]
			_fill_row(g, r, p, t, vt)


## Write pilot `p` (of team `t`) into row `r` of grid `g` (row 0 is the
## first pilot, just under the titles). `vt` is the team we see as
## (-1 = a spectator who sees everything).
func _fill_row(g: GridContainer, r: int, p: PilotProfile, t: int, vt: int) -> void:
	# Step 1: the ship and the status, by what the pilot is doing.
	var ship := "—"
	var status := ""
	match p.state:
		"flying":
			var visible_to_us := vt < 0 or t == vt or (p.ship != null and is_instance_valid(p.ship) and p.ship.visible_to(vt))
			ship = String(Ships.HULLS[p.ship.hull_id]["label"]) if visible_to_us and p.ship != null and is_instance_valid(p.ship) else "?"
			status = "Flying" if visible_to_us else "Unseen"
		"docked":
			status = "At the mothership"
		"spooling":
			status = "Hyperspace jump"
		"dead":
			status = "Respawn in %ds" % int(ceil(p.respawn_t))
	if p.role == "admiral":
		status = "Admiral · " + status
	# Step 2: the cells, left to right, and the row's colour.
	var vals := [p.callsign + (" (you)" if p.is_human else ""), ship, p.kda(), str(p.minion_kills), str(p.monster_kills), Util.money(p.earned), status]
	for c in g.columns:
		var l: Label = g.get_child((r + 1) * g.columns + c)
		UiKit.set_text(l, vals[c])
		l.add_theme_color_override("font_color", Palette.AMBER if p.is_human else (Palette.MIST if p.state == "dead" else Palette.ICE))
