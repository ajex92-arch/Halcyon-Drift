class_name StartScreen
extends Control
## WHAT THIS IS: the first screen of the game, where the human picks their
## team (Aurelian or Vhorr) and their seat: command the team as its Admiral,
## or fly as one of its 12 pilots (then an AI admiral commands). The other
## team is all computer. The choice is locked for the whole match.
## DESIGN.md A3.
##
## HOW IT WORKS: the layout is the scene scenes/ui/start_screen.tscn: a
## dark Cover that blocks clicks to the game behind it, and a Scroll area
## with the Card (the "StartLook" box) centred in it: Scroll > Center >
## Card > Col (Tagline, Title, Rules, SeatHeading, Seats, ControlsHeading,
## Controls). Seats holds the two "seat cards" side by side, Admiral and
## Pilot (the "SeatLook" box), each a column of Title, Body and Pick (a big
## button with the same title). Body takes the spare height, so both
## cards' buttons line up. Pressing a Pick button sends `chosen(role)`.
## _ready() gives the screen the game's look (UiKit.make_theme()), and
## _layout() keeps the card at most 980 pixels wide and fits the wrapped
## text to it whenever the window is resized.
## The rules of the match are not chosen here: every match plays the standard
## rules (Game.preset, set from the launch option --preset, which is for tests
## and research). Only when the game was launched with a --preset that was not
## understood (Game.preset_error), _ready() adds one wrapping line under the
## rules text (made in code, not in the scene) that says so and to relaunch the
## game without the option or with a known name, and both seat buttons stay off,
## since no screen can clear the error.
## Below that, _build_difficulty() adds the difficulty row (also made in code):
## the heading DIFFICULTY with one button per level (Difficulty.ORDER: Easy,
## Medium, Hard, Very hard, Extreme) and the chosen level's one-line description,
## which says that the setting changes the enemy's income in single player only.
## A button calls
## Game.choose_difficulty(), which also remembers the pick for the next run. The
## row starts on the level Game holds: the one last picked on this computer
## (Game.use_remembered_difficulty(), called here), Medium the first time, or the
## level the game was launched with (--difficulty).
## Below the difficulty row, _build_team() adds the team row (also made in code):
## the heading TEAM with two buttons, Aurelian and Vhorr (each in its team's
## colour), and the chosen team's one-line description. A button calls
## Game.choose_team(), which also remembers the pick for the next run. The row
## starts on the team Game holds: the one last picked on this computer
## (Game.use_remembered_team(), called here), Aurelian the first time, or the team
## the game was launched with (--team). The Pilot card's sentence about the
## computer Admiral names the chosen team. The screen's highlight colour follows
## the pick: _use_team_accent() makes the theme again with Aurelian's amber or
## Vhorr's red (Palette.accent()), so the chosen buttons, the two seat buttons and
## the top line change colour the moment a team button is pressed. (The two team
## buttons keep their own team colours.)
##
## WHO USES IT: main.gd shows it from scenes/ui/start_screen.tscn and
## connects `chosen` to its start(role). The launch line reads
## Game.preset_error; the difficulty row reads Difficulty and calls
## Game.choose_difficulty(); the team row calls Game.choose_team().

## Sent once the player picks a seat: role is "admiral" or "pilot".
signal chosen(role: String)

## The main card (its width follows the window, up to about 1030 pixels).
@onready var _card: PanelContainer = $Scroll/Center/Card
## The wrapped texts that run across the whole card: the rules and the
## controls. A new wrapping label in the scene must be added here (or to
## _seat_texts), or it comes out far too tall (see _layout()).
@onready var _wide_texts: Array[Label] = [$Scroll/Center/Card/Col/Rules, $Scroll/Center/Card/Col/Controls]
## The wrapped texts inside the two seat cards (half the card each).
@onready var _seat_texts: Array[Label] = [$Scroll/Center/Card/Col/Seats/Admiral/Col/Body, $Scroll/Center/Card/Col/Seats/Pilot/Col/Body]
## The line under the rules text that names a launch option that was not
## understood. Null unless Game.preset_error is set. Made by
## _build_launch_note().
var _launch_note: Label = null
## The difficulty buttons, by level id (Difficulty.ORDER). Made by
## _build_difficulty().
var _difficulty_buttons := {}
## The chosen level's description, under its buttons.
var _difficulty_blurb: Label = null
## The one-line description of each team the human can play for, by team number.
const TEAM_BLURBS := {
	Rules.HALCYON: "Aurelian: you play the amber team and start at its mothership on the left of the map. The computer plays Vhorr.",
	Rules.CINDER: "Vhorr: you play the red team and start at its mothership on the right of the map. The computer plays Aurelian.",
}
## The team buttons, by team number (Rules.HALCYON, Rules.CINDER). Made by
## _build_team().
var _team_buttons := {}
## The chosen team's description, under its buttons.
var _team_blurb: Label = null
## The Pilot card's text as the scene has it (it names Aurelian as the computer
## Admiral's team); _show_team() puts the other team's name into a copy.
var _pilot_text := ""


## Called once when the node joins the scene: take up the difficulty and the team
## last picked on this computer, give the screen the game's look in the chosen
## team's highlight colour, darken the cover, make each seat's button send its
## role, add the launch line, the difficulty row and the team row, then fit
## everything to the window (now and on every resize).
func _ready() -> void:
	Game.use_remembered_difficulty()
	Game.use_remembered_team()
	_use_team_accent()
	$Cover.color = Palette.with_alpha(Palette.VOID, 0.82)
	$Scroll/Center/Card/Col/Seats/Admiral/Col/Pick.pressed.connect(func() -> void: chosen.emit("admiral"))
	$Scroll/Center/Card/Col/Seats/Pilot/Col/Pick.pressed.connect(func() -> void: chosen.emit("pilot"))
	_build_launch_note()
	_build_difficulty()
	_build_team()
	resized.connect(_layout)
	_layout()


## Give the screen the game's look in the highlight colour of the team the human
## has chosen (Game.human_team): amber for Aurelian, red for Vhorr
## (Palette.accent()). The theme is made again, and every control under the screen
## takes the new one at once: the chosen difficulty button, the two seat buttons
## and the top line. The launch line has a colour of its own, which is set by
## hand. Runs when the screen is made and whenever a team button is pressed.
func _use_team_accent() -> void:
	UiKit.set_accent_team(Game.human_team)
	theme = UiKit.make_theme()
	if _launch_note != null:
		_launch_note.add_theme_color_override("font_color", UiKit.accent())


## Add the launch line right under the rules text, but only when the game was
## launched with a --preset that was not understood (Game.preset_error): the
## match would refuse to start and no screen picks other rules, so the line
## says to relaunch the game without the option or with a known name, and both
## seat buttons stay off (_refresh_seats()). Otherwise nothing is added. The
## line is a wrapping label, so it joins _wide_texts.
func _build_launch_note() -> void:
	if Game.preset_error == "":
		return
	var col: VBoxContainer = $Scroll/Center/Card/Col
	_launch_note = UiKit.label("The launch option --preset was not understood: %s. Relaunch the game without it, or with one of those names. The seat buttons stay off until you do." % Game.preset_error, 13, UiKit.accent(), true)
	col.add_child(_launch_note)
	col.move_child(_launch_note, $Scroll/Center/Card/Col/Rules.get_index() + 1)
	_wide_texts.append(_launch_note)


## Add the difficulty row right under the rules text (and the launch line,
## when it shows): a row with the heading DIFFICULTY and one button per level
## (Difficulty.ORDER), then the chosen level's description (a wrapping label,
## so it joins _wide_texts).
func _build_difficulty() -> void:
	# Step 1: the row (its heading first, then the buttons) and the description
	# go in the card's column, in that order, just below the rules text (below
	# the launch line when there is one). The heading shares the row with the
	# buttons and the text is one line, so the row takes little height and the
	# two seat buttons below it stay in view on a 1080p screen.
	var col: VBoxContainer = $Scroll/Center/Card/Col
	var above: Control = $Scroll/Center/Card/Col/Rules
	if _launch_note != null:
		above = _launch_note
	var at: int = above.get_index() + 1
	var row := UiKit.hbox(8)
	var heading := UiKit.label("DIFFICULTY", 12, Palette.MIST)
	heading.custom_minimum_size = Vector2(100, 0)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(heading)
	_difficulty_blurb = UiKit.label("", 13, Palette.MIST, true)
	for node: Control in [row, _difficulty_blurb]:
		col.add_child(node)
		col.move_child(node, at)
		at += 1
	_wide_texts.append(_difficulty_blurb)
	# Step 2: one toggle button per level. The chosen one shows pressed (in the
	# highlight colour).
	for level: String in Difficulty.ORDER:
		var lv := level
		var b := UiKit.button(String(Difficulty.LABELS[lv]), func() -> void: _choose_difficulty(lv))
		b.toggle_mode = true
		row.add_child(b)
		_difficulty_buttons[lv] = b
	_show_difficulty()


## Level `level` was picked: use it for the coming match and remember it for the
## next run (Game.choose_difficulty()), and show it.
func _choose_difficulty(level: String) -> void:
	Game.choose_difficulty(level)
	_show_difficulty()


## Show the level in Game.difficulty as chosen: its button pressed, the others
## not, and its description under the row. If the game was launched with an
## unknown --difficulty (Game.difficulty_error), say so instead: the match would
## refuse to start until a level is picked here, so both seat buttons wait too
## (any level button clears the error, and this runs again).
func _show_difficulty() -> void:
	for lv: String in _difficulty_buttons:
		(_difficulty_buttons[lv] as Button).set_pressed_no_signal(lv == Game.difficulty and Game.difficulty_error == "")
	_refresh_seats()
	if Game.difficulty_error != "":
		_difficulty_blurb.text = "The launch option --difficulty was not understood: %s. Pick a level above before you choose a seat." % Game.difficulty_error
	else:
		_difficulty_blurb.text = Difficulty.blurb(Game.difficulty)


## Add the team row right under the difficulty description: a row with the
## heading TEAM and one button per team the human can play for (Aurelian, Vhorr),
## then the chosen team's description (a wrapping label, so it joins _wide_texts).
func _build_team() -> void:
	# Step 1: the row (its heading first, then the buttons) and the description
	# go in the card's column, in that order, just below the difficulty
	# description. Like the difficulty row, the heading shares the row with the
	# buttons and the text is one line.
	var col: VBoxContainer = $Scroll/Center/Card/Col
	var at: int = _difficulty_blurb.get_index() + 1
	var row := UiKit.hbox(8)
	var heading := UiKit.label("TEAM", 12, Palette.MIST)
	heading.custom_minimum_size = Vector2(100, 0)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(heading)
	_team_blurb = UiKit.label("", 13, Palette.MIST, true)
	for node: Control in [row, _team_blurb]:
		col.add_child(node)
		col.move_child(node, at)
		at += 1
	_wide_texts.append(_team_blurb)
	_pilot_text = _seat_texts[1].text
	# Step 2: one toggle button per team, in the team's colour. The chosen one
	# shows pressed (a box in the team's colour).
	for side: int in [Rules.HALCYON, Rules.CINDER]:
		var b := _team_button(side)
		row.add_child(b)
		_team_buttons[side] = b
	_show_team()


## A toggle button for team `side`, with the team's name in the team's colour,
## and a border in that colour when hovered or chosen (the theme's is the
## highlight colour).
func _team_button(side: int) -> Button:
	var tint := Palette.team(side)
	var b := UiKit.button(String(Rules.TEAM_DISPLAY[side]), func() -> void: _choose_team(side))
	b.toggle_mode = true
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, tint)
	b.add_theme_stylebox_override("hover", UiKit.box(Palette.INK, tint, 8))
	b.add_theme_stylebox_override("pressed", UiKit.box(Palette.PANEL, tint, 8))
	b.add_theme_stylebox_override("hover_pressed", UiKit.box(Palette.PANEL, tint, 8))
	return b


## Team `side` was picked: use it for the coming match and remember it for the
## next run (Game.choose_team()), turn the screen's highlight colour into that
## team's, and show the pick.
func _choose_team(side: int) -> void:
	Game.choose_team(side)
	_use_team_accent()
	_show_team()


## Show the team in Game.human_team as chosen: its button pressed, the other not,
## its description under the row, and the Pilot card naming it as the team the
## computer Admiral commands. If the game was launched with an unknown --team
## (Game.team_error), say so instead: the match would refuse to start, so both
## seat buttons wait too (a team button clears the error, and this runs again).
func _show_team() -> void:
	for side: int in _team_buttons:
		(_team_buttons[side] as Button).set_pressed_no_signal(side == Game.human_team and Game.team_error == "")
	_refresh_seats()
	if Game.team_error != "":
		_team_blurb.text = "The launch option --team was not understood: %s. Pick a team above before you choose a seat." % Game.team_error
	else:
		_team_blurb.text = String(TEAM_BLURBS[Game.human_team])
	_seat_texts[1].text = _pilot_text.replace("commands Aurelian.", "commands %s." % Rules.TEAM_DISPLAY[Game.human_team])


## Enable the two seat buttons, unless a launch option was not understood (an
## unknown --preset, --difficulty or --team): the match would refuse to start, so
## both stay off. A level above clears an unknown --difficulty and a team above
## clears an unknown --team; an unknown --preset stays until the game is launched
## again.
func _refresh_seats() -> void:
	var blocked: bool = Game.preset_error != "" or Game.difficulty_error != "" or Game.team_error != ""
	$Scroll/Center/Card/Col/Seats/Admiral/Col/Pick.disabled = blocked
	$Scroll/Center/Card/Col/Seats/Pilot/Col/Pick.disabled = blocked


## Fit the card to the window: w = the window width minus 80 pixels, but at
## most 980. (The card comes out 52 pixels wider than w, with its padding and
## the seat cards' gap, and a scroll bar can take 6 more: 80 leaves the
## card 10 pixels from each side of the window.) Then give every wrapping
## label a fixed width (UiKit.pin_width),
## because a wrapping label can't measure its height until it knows its
## width: text inside a seat card gets (w - 74) / 2 pixels (half the card,
## after padding and the gap between the cards), all other text w - 46.
func _layout() -> void:
	var w := minf(980.0, size.x - 80.0)
	_card.custom_minimum_size = Vector2(w, 0)
	for l in _wide_texts:
		UiKit.pin_width(l, w - 46.0)
	for l in _seat_texts:
		UiKit.pin_width(l, (w - 74.0) * 0.5)
