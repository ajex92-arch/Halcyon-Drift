class_name HudTopBar
extends PanelContainer
## WHAT THIS IS: the strip at the top centre of the HUD: the match clock,
## when the next minion wave launches, and for each team its mothership's
## hull bar, any mothership trouble, and how many turrets it has in each
## lane.
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_top_bar.tscn: a
## see-through dark panel (the "TopBarLook" look) 6 pixels below the top
## edge, centred, holding one row: Halcyon's column (Name, Hull bar,
## Turrets), the Middle column (Clock, Wave) and Cinder's column. Cinder's
## side is a mirror image: its text is right-aligned and its bar fills from
## the right. The mouse passes through it to the game. _ready() colours
## each team's name and bar; refresh() rewrites the text 10 times a second.
## Enemy turrets are only counted once our team has seen them.
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it and
## Hud._refresh() calls refresh(). It reads World (clock, motherships,
## teams, turrets) and MinionDirector (when the next wave launches).

## The match clock ("12:34").
@onready var _clock: Label = $Row/Middle/Clock
## "Next minion wave 0:21" (or that free waves have stopped).
@onready var _wave: Label = $Row/Middle/Wave
## Each team's mothership hull bar (index = team: 0 Halcyon, 1 Cinder).
@onready var _ms_bars: Array[ProgressBar] = [$Row/Halcyon/Hull, $Row/Cinder/Hull]
## Each team's name, hull percent and any mothership trouble.
@onready var _ms_labels: Array[Label] = [$Row/Halcyon/Name, $Row/Cinder/Name]
## Each team's turret count per lane.
@onready var _turret_labels: Array[Label] = [$Row/Halcyon/Turrets, $Row/Cinder/Turrets]


## Godot calls this when the bar joins the HUD: give each team's name line
## and hull bar the team's colour.
func _ready() -> void:
	for t in 2:
		_ms_labels[t].add_theme_color_override("font_color", Palette.team(t))
		UiKit.tint_bar(_ms_bars[t], Palette.team(t))


## Rewrite the clock, the wave timer and both teams' columns.
func refresh(world: World) -> void:
	# Step 1: the clock and the wave timer. Once BOTH teams have built the
	# Fleet Command module, no free minion waves launch any more.
	UiKit.set_text(_clock, Util.clock(world.time))
	var md := world.minion_director
	var w := ""
	if md.controlled(0) and md.controlled(1):
		w = "Fleet Command: no free waves"
	else:
		w = "Next minion wave %s" % Util.clock(maxf(0.0, md.next_wave - world.time))
	UiKit.set_text(_wave, w)
	# Step 2: each team's column. vt = the team we watch as (-1 = we see
	# everything, as a spectator).
	var vt := world.viewer_team
	for t in 2:
		_refresh_team(world, t, vt)


## Rewrite team `t`'s hull bar, name line and turret line.
func _refresh_team(world: World, t: int, vt: int) -> void:
	var ms := world.mothership(t)
	var ts := world.teams[t]
	_ms_bars[t].value = ms.hull_frac()
	# Step 1: mothership trouble. At 35% hull a mothership can have one
	# emergency, a "systems failure" (it counts down in seconds).
	# "Strained" means too many pilots respawned at once. "Plating holding"
	# means the ms_cap variant is capping the hull damage right now.
	var extra := ""
	if ms.failure_t > 0.0:
		extra = "  SYSTEMS FAILURE %ds" % int(ceil(ms.failure_t))
	elif ts.strain_t > 0.0:
		extra = "  STRAINED"
	elif ms.incoming_mults.has("ms_cap"):
		# The ms_cap variant (MsCapFeature) is holding the hull damage down.
		extra = "  PLATING HOLDING"
	# Step 2: the name line, "Halcyon (us)  87%  STRAINED". Cinder's is
	# written the other way round ("STRAINED  87%  Cinder (enemy)"), so on
	# both sides the team name sits at the outer edge.
	var tname: String = Rules.TEAM_NAMES[t]
	if vt >= 0:
		tname += " (us)" if t == vt else " (enemy)"
	var txt := "%s  %d%%%s" % [tname, int(ms.hull_frac() * 100.0), extra]
	if t == 1:
		txt = "%s  %d%%  %s" % [extra.strip_edges(), int(ms.hull_frac() * 100.0), tname]
	UiKit.set_text(_ms_labels[t], txt.strip_edges())
	# Step 3: live turrets per lane.
	var lanes := _count_turrets(world, t, vt)
	UiKit.set_text(_turret_labels[t], "Turrets  top %d · mid %d · bottom %d" % [lanes["top"], lanes["mid"], lanes["bot"]])


## Count team `t`'s live turrets in each lane ("top", "mid", "bot").
## Turrets of the other team only count once our team (vt) has seen them:
## seen_mask is a row of on/off switches ("bits"), one per team, and bit
## number vt (the value 1 << vt) is switched on once team vt has seen it.
func _count_turrets(world: World, t: int, vt: int) -> Dictionary:
	var lanes := {"top": 0, "mid": 0, "bot": 0}
	for tu: Turret in world.turrets:
		if tu.team != t or not tu.alive or tu.node == null:
			continue
		if vt >= 0 and t != vt and (tu.seen_mask & (1 << vt)) == 0:
			continue
		lanes[tu.node.lane] = int(lanes[tu.node.lane]) + 1
	return lanes
