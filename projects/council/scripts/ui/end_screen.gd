class_name EndScreen
extends Control
## WHAT THIS IS: the screen shown when a mothership is destroyed and the
## match ends: who won, why, how long it took, each team's totals and the
## top pilots, with "New match" and "Quit" buttons.
##
## HOW IT WORKS: the layout is the scene scenes/ui/end_screen.tscn: a dark
## Cover over the whole window (it blocks clicks to the game) and, in the
## middle (Center), a Card (the "EndLook" box) holding one column: Col >
## Title, Reason, Teams (Halcyon and Cinder, each: Name, Kills, Turrets,
## Ore, Research, Hull), TopHeading, Buttons (NewMatch, Quit). setup() is
## called before the screen joins the scene, so _ready() can fill it all
## in at once. If we watch as a team the title is "Victory" (amber) or
## "Defeat" (red); a spectator sees "<team> wins". The top 5 pilots are
## ranked by damage done; if you are not among them, your own line is added
## under them. Those lines are made in code and go between TopHeading and
## Buttons. "New match" reloads the main scene, which goes back to the seat
## choice (StartScreen).
##
## WHO USES IT: Hud._on_match_over() makes it from
## scenes/ui/end_screen.tscn, calls setup() and adds it on top of the HUD.

## The game world (set by setup()).
var world: World
## The winning team (0 Aurelian, 1 Cinder; -1 until set).
var winner := -1
## Why the match ended, as a sentence from the game.
var reason := ""
## The card's column (the top pilot lines are added to it).
@onready var _col: VBoxContainer = $Center/Card/Col
## Each team's column of totals (index = team: 0 Aurelian, 1 Cinder).
@onready var _teams: Array[VBoxContainer] = [$Center/Card/Col/Teams/Halcyon, $Center/Card/Col/Teams/Cinder]


## Remember the world, the winning team `win` and the reason `why`.
func setup(w: World, win: int, why: String) -> void:
	world = w
	winner = win
	reason = why


## Called once when the node joins the scene: darken the cover, connect
## the buttons and fill in the results.
func _ready() -> void:
	# Step 1: the cover is 80% dark. "New match" clears Game.world and
	# reloads the main scene; "Quit" closes the game.
	$Cover.color = Palette.with_alpha(Palette.VOID, 0.8)
	$Center/Card/Col/Buttons/NewMatch.pressed.connect(func() -> void:
		Game.world = null
		get_tree().reload_current_scene())
	$Center/Card/Col/Buttons/Quit.pressed.connect(func() -> void: get_tree().quit())
	# No world means setup() was never called (tests/load_all.gd builds
	# every UI scene once that way): leave the texts empty.
	if world == null:
		return
	# Step 2: the title, the reason and the match time.
	var us := world.viewer_team
	var title := "%s wins" % Rules.TEAM_DISPLAY[winner]
	var tint := Palette.team(winner)
	if us >= 0:
		title = "Victory" if winner == us else "Defeat"
		tint = Palette.AMBER if winner == us else Palette.CINDER
	$Center/Card/Col/Title.text = title
	$Center/Card/Col/Title.add_theme_color_override("font_color", tint)
	$Center/Card/Col/Reason.text = "%s  Match time %s." % [Rules.display_label(reason), Util.clock(world.time)]
	# Step 3: one column of totals per team.
	for t in 2:
		_fill_team_totals(t)
	# Step 4: the top 5 pilots by damage done, and you if you're not
	# there. New lines land below the buttons, so afterwards the buttons
	# move back to the bottom.
	var best: Array = world.profiles.duplicate()
	best.sort_custom(func(a: PilotProfile, b: PilotProfile) -> bool: return a.damage_done > b.damage_done)
	for i in mini(5, best.size()):
		var p: PilotProfile = best[i]
		_col.add_child(UiKit.label("%s (%s)  ·  %s K/D/A  ·  %s damage  ·  %d last hits  ·  %s credits earned" % [p.callsign, Rules.TEAM_DISPLAY[p.team], p.kda(), Util.money(p.damage_done), p.minion_kills, Util.money(p.earned)], 14, Palette.AMBER if p.is_human else Palette.ICE))
	var me := world.human
	if me != null and best.find(me) >= 5:
		_col.add_child(UiKit.label("You: %s K/D/A · %s damage · %d last hits" % [me.kda(), Util.money(me.damage_done), me.minion_kills], 14, Palette.AMBER))
	_col.move_child($Center/Card/Col/Buttons, -1)


## Fill team `t`'s column of totals (Name, Kills, Turrets, Ore, Research,
## Hull, top to bottom): its name in its colour, then pilot kills / deaths
## (added up over its pilots), turrets destroyed, ore delivered, research
## done and mothership hull left.
func _fill_team_totals(t: int) -> void:
	var ts := world.teams[t]
	var k := 0
	var d := 0
	for p: PilotProfile in world.profiles:
		if p.team == t:
			k += p.kills
			d += p.deaths
	var lines := [
		Rules.TEAM_DISPLAY[t],
		"Pilot kills / deaths: %d / %d" % [k, d],
		"Turrets destroyed: %d" % ts.turrets_destroyed,
		"Ore delivered: %s" % Util.money(ts.ore_delivered),
		"Research done: %d" % ts.done.size(),
		"Mothership hull left: %d%%" % int(world.mothership(t).hull_frac() * 100.0),
	]
	for i in lines.size():
		(_teams[t].get_child(i) as Label).text = lines[i]
	(_teams[t].get_child(0) as Label).add_theme_color_override("font_color", Palette.team(t))
