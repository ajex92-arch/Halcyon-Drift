extends Node
## WHAT THIS IS: the "team check": a quick test that the team the human chose (the
## launch option --team) is the team the human really plays for, in either seat
## (pilot or Admiral), and that nothing human is left on the other team. Without a
## human seat (--all-ai) it checks that --team changes nothing.
##
## HOW IT WORKS: setup() looks at the launch (--team: aurelian or vhorr, Aurelian
## when it is not given; --role; --difficulty) and works out what it should find (the
## team numbers and the difficulty table are written out here again, so the check
## does not copy the game's), then checks, one PASS or FAIL line each:
##   1. The settings: Game.human_team, World.human_team and World.viewer_team (the
##      team whose fog the screen shows; -1 for a spectator).
##   2. The seats: the human's pilot record is on the chosen team (slot 0 for a
##      pilot; the extra Admiral record, slot 12, for an Admiral); the human Admiral
##      sits on the chosen team only; every pilot of the other team has an AI brain
##      and no pilot there is human; the computer Admiral exists for exactly the
##      teams that have no human Admiral.
##   3. The money: the team without the human earns the difficulty's multiple of its
##      income, the human's team and a match with no human exactly x1.0 (the team's
##      treasury and every pilot of it).
##   4. Sight: the human's mothership is lit in the human's fog and drawn, the
##      enemy mothership is neither.
##   5. The ship: the human launches a Fighter, which is on the chosen team, flies
##      under the keyboard and mouse, appears beside the human's own mothership and
##      points toward the middle of the map.
##   6. The camera starts in front of the human's own mothership, toward the middle.
##   7. With --force-hud: the HUD's map tools and (for an Admiral) the Admiral board
##      command the chosen team, the pop-up hint names it, and the top bar says "(us)"
##      on its side only.
##   8. With --force-hud: the interface's highlight colour is the human's team's:
##      Aurelian's amber for an Aurelian pilot or Admiral and for a spectator, Vhorr's
##      red for a Vhorr one. It reads what the HUD really uses: UiKit.accent(), the
##      HUD's theme (the pressed buttons, the filled button, the named highlight text),
##      the first line of the top-left panel, the selected tab of the hangar (pilot) or
##      of the Admiral board, and a card's border. The colours the interface keeps
##      whatever the team (the energy bar, good and bad news) are not tested.
##   9. Always: a start screen made with each team chosen (nothing is written) is
##      highlighted in that team's colour.
##  10. With --settings-check=<text>: the start screen's team row and the remembered
##      pick (see below), and that its highlight colour changes the moment a team
##      button is pressed.
## It prints "team_check: N failures" (0 = all good), then quits.
## With --settings-check=<text> it also builds the start screen, presses a team's
## button, checks the game's setting, the texts, the highlight colour and the settings
## file, then builds the screen again as a new run would (the pick must come back), and
## checks that --team beats the remembered pick, that a damaged file is ignored and that
## an unknown --team blocks the seat buttons until a team is picked. That writes the
## settings file, so <text> must be part of the name of the user data folder (a scratch
## one: start the game with the environment variable APPDATA pointing at an empty folder
## whose name holds the text); with any other folder this part only reports a failure
## and writes nothing.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder that
## holds remake/; --bot=team keeps main.gd from launching the human's ship, because
## the check launches it itself):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --team=vhorr --difficulty=hard --bot=team --force-hud --test=team_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=admiral --team=vhorr --difficulty=hard --bot=team --force-hud --test=team_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --team=vhorr --test=team_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --team=vhorr --force-hud --test=team_check
## Try --role=pilot and --role=admiral with --team=aurelian, --team=vhorr and no --team.
## A launch with an unknown team (--team=vhoor) stops at the match's start with
## "TEAM UNKNOWN: ..." (exit code 3); run_checks looks for that line.
##
## WHO USES IT: main.gd loads it for --test=team_check. It launches the human's
## ship, so it is only for this check.

## The enemy income multiplier of each difficulty level, as the check expects it.
const EXPECTED := {"easy": 0.75, "medium": 1.0, "hard": 1.25, "very_hard": 1.5, "extreme": 2.0}
## Two numbers closer than this count as equal (float noise).
const TOLERANCE := 1e-9
## How far in front of the human's mothership the camera starts (world units).
const CAMERA_AHEAD := 1800.0
## The highlight colour of an Aurelian human (and of a spectator), written out here
## again so the check does not copy the game's: the amber.
const ACCENT_AUREL := Color(0.8863, 0.6314, 0.2902)
## The highlight colour of a Vhorr human: the red of the glowing veins on a Vhorr ship.
const ACCENT_VHORR := Color(1.0, 0.38, 0.22)
## Vhorr's team red, which the start screen's Vhorr button keeps whatever the
## highlight colour is.
const TEAM_VHORR := Color(0.8314, 0.3255, 0.2353)

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## The team the human should be on (0 Aurelian, 1 Vhorr), worked out from --team.
var _want := 0
## The Fighter the human launched (null for a spectator).
var _ship: Ship = null


## main.gd calls this once, right after the World is built. Run every check and
## quit.
func setup(w: World) -> void:
	world = w
	var named := str(Game.opt("team", "aurelian")).to_lower()
	_want = 1 if named == "vhorr" else 0
	var seat := world.human_role
	# A spectator has no side: the launch option changes nothing for them.
	var human_team := -1 if seat == "spectator" else _want
	print("team_check: seat=%s --team=%s, the human should be on team %d" % [seat, named, human_team])
	_check_settings_of_match(seat, human_team)
	_check_seats(seat, human_team)
	_check_money(human_team)
	_check_sight(human_team)
	_check_ship(seat, human_team)
	_check_camera()
	if Game.opt("force-hud", false):
		_check_hud(seat, human_team)
		_check_accent(seat, human_team)
	_check_start_accent()
	var marker := str(Game.opt("settings-check", ""))
	if marker != "":
		_check_start_screen(marker)
	print("team_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Check that `got` is `want` (within TOLERANCE), as the check `what`.
func _near(what: String, got: float, want: float) -> void:
	_check(what, absf(got - want) <= TOLERANCE, "got %.9f, wanted %.9f" % [got, want])


## Step 1: the settings the match was built with.
func _check_settings_of_match(seat: String, human_team: int) -> void:
	var side := human_team if human_team >= 0 else 0
	_check("Game.human_team follows --team", Game.human_team == _want and Game.team_error == "", "human_team %d, error '%s'" % [Game.human_team, Game.team_error])
	_check("World.human_team is the human's side (Aurelian for a spectator)", world.human_team == side, str(world.human_team))
	_check("World.viewer_team is the human's team (-1 for a spectator)", world.viewer_team == (-1 if seat == "spectator" else human_team), str(world.viewer_team))


## Step 2: who sits where.
func _check_seats(seat: String, human_team: int) -> void:
	var humans: Array = []
	for p: PilotProfile in world.profiles:
		if p.is_human:
			humans.append(p)
	_check("exactly %d human pilot record(s)" % (0 if seat == "spectator" else 1), humans.size() == (0 if seat == "spectator" else 1), str(humans.size()))
	_check("World.human is the human record (or nobody for a spectator)", (world.human == null) == (seat == "spectator") and (humans.is_empty() or world.human == humans[0]))
	if human_team >= 0:
		var h := world.human
		_check("the human's record is on team %d" % human_team, h.team == human_team, str(h.team))
		var want_slot := Rules.PILOTS_PER_TEAM if seat == "admiral" else 0
		_check("the human's seat number is %d" % want_slot, h.slot == want_slot, str(h.slot))
		_check("the human has no AI brain", not world.pilot_ai.has(h))
	for t in 2:
		var mine := t == human_team
		var pilots := 0
		var humans_here := 0
		var without_brain := 0
		for p: PilotProfile in world.profiles:
			if p.team != t:
				continue
			pilots += 1
			if p.is_human:
				humans_here += 1
			elif not world.pilot_ai.has(p):
				without_brain += 1
		var want_pilots := Rules.PILOTS_PER_TEAM + (1 if (mine and seat == "admiral") else 0)
		_check("team %d has %d pilot records" % [t, want_pilots], pilots == want_pilots, str(pilots))
		_check("team %d: %d human record(s) there" % [t, 1 if (mine and seat != "spectator") else 0], humans_here == (1 if (mine and seat != "spectator") else 0), str(humans_here))
		_check("team %d: every pilot but the human has an AI brain" % t, without_brain == 0, str(without_brain))
		var human_admiral := mine and seat == "admiral"
		_check("team %d: the Admiral's chair is %s" % [t, "the human's" if human_admiral else "the computer's"], world.teams[t].admiral == ("human" if human_admiral else "ai"), world.teams[t].admiral)
		_check("team %d: the computer Admiral is %s" % [t, "absent" if human_admiral else "there"], (world.admiral_ai[t] == null) == human_admiral)


## Step 3: the difficulty's income multiplier lands on the team without the human.
func _check_money(human_team: int) -> void:
	var enemy_mult := float(EXPECTED.get(Game.difficulty, 1.0)) if human_team >= 0 else 1.0
	for t in 2:
		var mult := enemy_mult if (human_team >= 0 and t != human_team) else 1.0
		_near("team %d treasury multiplier is x%.2f" % [t, mult], world.teams[t].income_mult, mult)
		var worst := 0.0
		for p: PilotProfile in world.profiles:
			if p.team == t:
				worst = maxf(worst, absf(p.income_mult - mult))
		_check("team %d: every pilot's multiplier is x%.2f" % [t, mult], worst <= TOLERANCE, "largest error %.12f" % worst)
		# One real payment through the gate of each team, to see the number is used.
		var before := world.teams[t].treasury
		world.teams[t].earn(100.0)
		_near("team %d earns x%.2f of 100 into its treasury" % [t, mult], world.teams[t].treasury - before, 100.0 * mult)


## Step 4: sight and drawing: the human's mothership is theirs, the enemy's is fogged.
func _check_sight(human_team: int) -> void:
	if human_team < 0:
		_check("a spectator sees both motherships drawn", world.mothership(0).visible and world.mothership(1).visible)
		return
	var enemy := Rules.enemy_of(human_team)
	var own_ms := world.mothership(human_team)
	var enemy_ms := world.mothership(enemy)
	_check("the human's mothership is in the human's lit fog", world.vision.is_visible(human_team, own_ms.global_position))
	_check("the enemy mothership is not in the human's lit fog", not world.vision.is_visible(human_team, enemy_ms.global_position))
	_check("the human's mothership is drawn", own_ms.visible)
	_check("the enemy mothership is not drawn yet", not enemy_ms.visible)
	_check("the human's team cannot see the enemy mothership", not enemy_ms.visible_to(human_team))


## Step 5: the human launches a Fighter.
func _check_ship(seat: String, human_team: int) -> void:
	if human_team < 0:
		_check("a spectator has no ship", world.human == null)
		return
	var h := world.human
	h.buy_hull("fighter", world.teams[h.team])
	_ship = world.launch(h)
	if _ship == null:
		_check("the human's Fighter launched", false)
		return
	var own_ms := world.mothership(human_team)
	var enemy_ms := world.mothership(Rules.enemy_of(human_team))
	var toward := 1.0 if human_team == Rules.HALCYON else -1.0
	_check("the human's ship is on team %d" % human_team, _ship.team == human_team, str(_ship.team))
	_check("the human's ship flies under the keyboard and mouse", _ship.controller is PlayerController)
	_check("the human's ship launched beside its own mothership", _ship.global_position.distance_to(own_ms.global_position) < _ship.global_position.distance_to(enemy_ms.global_position) and _ship.global_position.distance_to(own_ms.global_position) < 1500.0, "%.0f from it" % _ship.global_position.distance_to(own_ms.global_position))
	_check("the human's ship points toward the middle of the map", Vector2.from_angle(_ship.rotation).x * toward > 0.9, "%.2f" % (Vector2.from_angle(_ship.rotation).x * toward))
	var others_human := 0
	for s: Ship in world.ships:
		if s.team != human_team and (s.controller is PlayerController or (s.profile != null and s.profile.is_human)):
			others_human += 1
	_check("no ship of the other team is under a person", others_human == 0, str(others_human))
	_check("the %s seat has its ship's pilot record" % seat, h.ship == _ship and h.state == "flying", h.state)


## Step 6: the camera starts in front of the human's own mothership.
func _check_camera() -> void:
	var side := world.human_team
	var own_ms := world.mothership(side)
	var enemy_ms := world.mothership(Rules.enemy_of(side))
	var cam := world.camera.global_position
	var toward := 1.0 if side == Rules.HALCYON else -1.0
	var ahead := cam.distance_to(own_ms.global_position)
	_check("the camera starts %d units from its own mothership" % int(CAMERA_AHEAD), absf(ahead - CAMERA_AHEAD) < 0.01, "%.3f" % ahead)
	_check("the camera starts nearer its own mothership than the enemy's", cam.distance_to(own_ms.global_position) < cam.distance_to(enemy_ms.global_position))
	_check("the camera starts toward the middle of the map from its own mothership", (cam.x - own_ms.global_position.x) * toward > 0.0, "x %.0f, mothership x %.0f" % [cam.x, own_ms.global_position.x])


## Step 7: the HUD (needs --force-hud): map tools, board, pop-up hint, top bar.
func _check_hud(seat: String, human_team: int) -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		_check("the HUD exists (--force-hud)", false)
		return
	var side := world.human_team
	_check("the HUD's map tools command team %d" % side, hud.overlay.team == side, str(hud.overlay.team))
	if seat == "admiral":
		hud._toggle_board()
		_check("the Admiral board commands team %d" % side, hud.board != null and hud.board.team == side, str(hud.board.team if hud.board != null else -1))
		hud._toggle_board()
		var hint: String = hud.toast_box._label.text
		_check("the pop-up hint says \"You command %s.\"" % Rules.TEAM_DISPLAY[side], hint.begins_with("You command %s." % Rules.TEAM_DISPLAY[side]), hint)
	hud.top_bar.refresh(world)
	for t in 2:
		var line: String = hud.top_bar._ms_labels[t].text
		var want_us := human_team >= 0 and t == human_team
		_check("the top bar marks team %d %s" % [t, "(us)" if want_us else "(enemy)" if human_team >= 0 else "without a side"], line.contains("(us)") == want_us and line.contains("(enemy)") == (human_team >= 0 and not want_us), line)


## Is colour `got` the colour `want` (float noise allowed)?
func _same(got: Color, want: Color) -> bool:
	return got.is_equal_approx(want)


## Step 8: the HUD's highlight colour (needs --force-hud) is the colour of the human's
## team: amber for Aurelian and for a spectator, red for Vhorr (see the top of the
## file for what is read).
func _check_accent(seat: String, human_team: int) -> void:
	var hud := get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null:
		_check("the HUD exists for the highlight colour (--force-hud)", false)
		return
	var want := ACCENT_VHORR if human_team == Rules.CINDER else ACCENT_AUREL
	var who := "Vhorr red" if human_team == Rules.CINDER else "amber"
	_check("the interface highlights in %s" % who, _same(UiKit.accent(), want), str(UiKit.accent()))
	# The HUD's theme: the pressed buttons, the filled button, the named highlight text.
	var th := hud.theme
	_check("HUD theme: a pressed button's border is %s" % who, _same((th.get_stylebox("pressed", "Button") as StyleBoxFlat).border_color, want))
	_check("HUD theme: a hovered button's border is %s" % who, _same((th.get_stylebox("hover", "Button") as StyleBoxFlat).border_color, want))
	_check("HUD theme: a pressed button's text is %s" % who, _same(th.get_color("font_pressed_color", "Button"), want))
	_check("HUD theme: the filled button is %s" % who, _same((th.get_stylebox("normal", "PrimaryButton") as StyleBoxFlat).bg_color, want))
	_check("HUD theme: the highlight text is %s" % who, _same(th.get_color("font_color", "AccentText"), want))
	# What the widgets really show.
	var title: Label = hud.me_panel._me_title
	_check("the top-left panel's first line is %s" % who, _same(title.get_theme_color("font_color"), want), str(title.get_theme_color("font_color")))
	var card := CardButton.new("Card", "", "", 0.0)
	card.set_state(false, true)
	_check("a selected card's border is %s" % who, _same((card.get_theme_stylebox("panel") as StyleBoxFlat).border_color, want))
	_check("a card's price line starts as %s" % who, _same(card.foot.get_theme_color("font_color"), want))
	card.free()
	if seat == "pilot":
		_check_tabs("hangar", hud.hangar._tab_buttons, hud.hangar.tab, want, who)
		_check("the hangar's Launch button is %s" % who, _same((hud.hangar._launch.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, want))
	elif seat == "admiral":
		if hud.board == null:
			hud._toggle_board()
		_check("the Admiral board commands the chosen team", hud.board != null and hud.board.team == world.human_team)
		_check_tabs("Admiral board", hud.board._tab_buttons, hud.board.tab, want, who)
		_check("the Admiral board's note is %s" % who, _same(hud.board._away.get_theme_color("font_color"), want))


## The selected tab of a tab row is in colour `want` (text and border) and the
## others are not.
func _check_tabs(what: String, tabs: Array, selected: String, want: Color, who: String) -> void:
	var seen := 0
	for b: Button in tabs:
		var font := b.get_theme_color("font_color")
		var border := (b.get_theme_stylebox("normal") as StyleBoxFlat).border_color
		if b.text == selected:
			seen += 1
			_check("%s: the selected tab \"%s\" is %s" % [what, b.text, who], _same(font, want) and _same(border, want), "text %s, border %s" % [font, border])
		else:
			_check("%s: the tab \"%s\" is not %s" % [what, b.text, who], not _same(font, want) and not _same(border, want), "text %s, border %s" % [font, border])
	_check("%s: one tab is selected" % what, seen == 1, str(seen))


## Is start screen `screen` highlighted in colour `want`? Its chosen difficulty button
## (the theme's pressed look), the two seat buttons and the top line are; the two team
## buttons keep their own team colours whatever the highlight is. `when` says when.
func _check_screen_accent(screen: StartScreen, want: Color, when: String) -> void:
	var who := "Vhorr red" if want == ACCENT_VHORR else "amber"
	var level: Button = screen._difficulty_buttons[Game.difficulty]
	_check("%s: the chosen difficulty button is %s" % [when, who], level.button_pressed and _same((level.get_theme_stylebox("pressed") as StyleBoxFlat).border_color, want) and _same(level.get_theme_color("font_pressed_color"), want))
	for seat: String in ["Admiral", "Pilot"]:
		var pick := screen.get_node("Scroll/Center/Card/Col/Seats/%s/Col/Pick" % seat) as Button
		_check("%s: the %s seat button is %s" % [when, seat, who], _same((pick.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, want))
	var tagline := screen.get_node("Scroll/Center/Card/Col/Tagline") as Label
	_check("%s: the top line is %s" % [when, who], _same(tagline.get_theme_color("font_color"), want))
	_check("%s: the Aurelian button keeps its amber" % when, _same((screen._team_buttons[0] as Button).get_theme_color("font_pressed_color"), ACCENT_AUREL))
	_check("%s: the Vhorr button keeps its team red" % when, _same((screen._team_buttons[1] as Button).get_theme_color("font_pressed_color"), TEAM_VHORR))


## Step 9: a start screen made with Aurelian chosen is amber, and one made with Vhorr
## chosen is red (nothing is written: the screen reads no settings file here).
func _check_start_accent() -> void:
	var launched_team := Game.human_team
	var launched_error := Game.team_error
	for side: int in [Rules.HALCYON, Rules.CINDER]:
		Game.human_team = side
		Game.team_error = ""
		Game._difficulty_open = false
		Game._team_open = false
		var screen: StartScreen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
		add_child(screen)
		_check_screen_accent(screen, ACCENT_VHORR if side == Rules.CINDER else ACCENT_AUREL, "start screen made with %s chosen" % Rules.TEAM_DISPLAY[side])
		screen.free()
	Game.human_team = launched_team
	Game.team_error = launched_error
	UiKit.set_accent_team(world.human_team)


## Make a start screen as a new run would: the team is open again, then the scene is
## added to the tree (which builds the rows).
func _new_screen() -> StartScreen:
	Game.human_team = Rules.HALCYON
	Game.team_error = ""
	Game._team_open = true
	var screen: StartScreen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	return screen


## The team whose button is pressed on start screen `screen` (-1 if none, -2 if more
## than one).
func _pressed_team(screen: StartScreen) -> int:
	var found := -1
	for side: int in screen._team_buttons:
		if (screen._team_buttons[side] as Button).button_pressed:
			found = side if found == -1 else -2
	return found


## Is the Pilot card's seat button on `screen` disabled?
func _seat_blocked(screen: StartScreen) -> bool:
	return (screen.get_node("Scroll/Center/Card/Col/Seats/Pilot/Col/Pick") as Button).disabled


## The Pilot card's description text on `screen`.
func _pilot_text(screen: StartScreen) -> String:
	return (screen.get_node("Scroll/Center/Card/Col/Seats/Pilot/Col/Body") as Label).text


## The start screen's team row and the remembered pick (see the top of the file).
## `marker` must be part of the user data folder's name, so the settings file
## written here is a scratch one.
func _check_start_screen(marker: String) -> void:
	var dir := OS.get_user_data_dir()
	if not dir.contains(marker):
		_check("settings check: the user data folder holds \"%s\"" % marker, false, "it is %s, so nothing was written" % dir)
		return
	var launched_team := Game.human_team
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	# Step 1: nothing remembered yet: Aurelian is pressed, and the texts name it.
	var screen := _new_screen()
	_check("settings: Aurelian is pressed when nothing is remembered", _pressed_team(screen) == 0, "pressed: %d" % _pressed_team(screen))
	_check("settings: the team text describes Aurelian", screen._team_blurb.text.begins_with("Aurelian:") and screen._team_blurb.text.contains("left of the map"), screen._team_blurb.text)
	_check("settings: the Pilot card names Aurelian's computer Admiral", _pilot_text(screen).contains("commands Aurelian."))
	_check_screen_accent(screen, ACCENT_AUREL, "settings: Aurelian chosen")
	# Step 2: press Vhorr: the setting, the texts, the highlight colour and the file follow.
	(screen._team_buttons[1] as Button).pressed.emit()
	_check_screen_accent(screen, ACCENT_VHORR, "settings: after pressing Vhorr")
	_check("settings: pressing Vhorr sets Game.human_team", Game.human_team == Rules.CINDER, str(Game.human_team))
	_check("settings: Vhorr is the pressed button", _pressed_team(screen) == 1, "pressed: %d" % _pressed_team(screen))
	_check("settings: the team text describes Vhorr", screen._team_blurb.text.begins_with("Vhorr:") and screen._team_blurb.text.contains("right of the map"), screen._team_blurb.text)
	_check("settings: the Pilot card names Vhorr's computer Admiral", _pilot_text(screen).contains("commands Vhorr.") and not _pilot_text(screen).contains("commands Aurelian."), _pilot_text(screen))
	var cfg := ConfigFile.new()
	_check("settings: the file was written", cfg.load(Game.SETTINGS_FILE) == OK and str(cfg.get_value("game", "team", "")) == "vhorr")
	(screen._team_buttons[0] as Button).pressed.emit()
	_check("settings: pressing Aurelian again gives the team back", Game.human_team == Rules.HALCYON and _pressed_team(screen) == 0 and _pilot_text(screen).contains("commands Aurelian."))
	_check_screen_accent(screen, ACCENT_AUREL, "settings: after pressing Aurelian again")
	(screen._team_buttons[1] as Button).pressed.emit()
	screen.free()
	# Step 3: a new run: the pick comes back, and so does its highlight colour.
	screen = _new_screen()
	_check("settings: the next run shows Vhorr, as remembered", Game.human_team == Rules.CINDER and _pressed_team(screen) == 1, "setting %d, pressed: %d" % [Game.human_team, _pressed_team(screen)])
	_check_screen_accent(screen, ACCENT_VHORR, "settings: the next run, Vhorr remembered")
	screen.free()
	# Step 4: --team beats the remembered pick (the game settles it at launch, before the screen).
	Game.human_team = Rules.HALCYON
	Game._team_open = false
	screen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	_check("settings: a launch option beats the remembered pick", Game.human_team == Rules.HALCYON and _pressed_team(screen) == 0, "setting %d, pressed: %d" % [Game.human_team, _pressed_team(screen)])
	screen.free()
	# Step 5: a damaged file is ignored.
	cfg.set_value("game", "team", "banana")
	cfg.save(Game.SETTINGS_FILE)
	screen = _new_screen()
	_check("settings: a word that is not a team is ignored", Game.human_team == Rules.HALCYON and _pressed_team(screen) == 0, "setting %d" % Game.human_team)
	screen.free()
	# Step 6: an unknown --team: no button pressed, the seat buttons wait, and the text says so;
	# picking a team clears it.
	Game.human_team = Rules.HALCYON
	Game.team_error = "unknown team \"vhoor\" (the teams are: aurelian, vhorr)"
	Game._team_open = false
	screen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	_check("settings: an unknown --team presses no button", _pressed_team(screen) == -1, "pressed: %d" % _pressed_team(screen))
	_check("settings: an unknown --team blocks the seat buttons", _seat_blocked(screen))
	_check("settings: an unknown --team says so", screen._team_blurb.text.contains("--team") and screen._team_blurb.text.contains("vhoor"), screen._team_blurb.text)
	(screen._team_buttons[1] as Button).pressed.emit()
	_check("settings: picking a team clears the error and frees the seat buttons", Game.team_error == "" and not _seat_blocked(screen) and _pressed_team(screen) == 1)
	screen.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	Game.human_team = launched_team
	Game.team_error = ""
	Game._team_open = false
	UiKit.set_accent_team(world.human_team)
