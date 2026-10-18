class_name StartScreen
extends Control
## WHAT THIS IS: the first screen of the game, where the human picks their
## seat: command Aurelian as its Admiral, or fly as one of its 12 pilots
## (then an AI admiral commands). The choice is locked for the whole match.
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
## Under the rules text, _ready() also adds the rule-set row (made in code,
## not in the scene): "Standard rules" and one button per preset
## (CouncilPresets: "Within requirements", "Council's pick"), with the
## chosen set's description below. A button calls Game.apply_preset() at
## once, so the match the seat buttons start plays with it. It starts on
## the rule set that Game holds: the standard rules, or the preset the game
## was launched with (--preset). Game keeps the last choice across "New
## match".
##
## WHO USES IT: main.gd shows it from scenes/ui/start_screen.tscn and
## connects `chosen` to its start(role). The rule-set row reads
## CouncilPresets and calls Game.apply_preset().

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
## The rule-set buttons, by preset name ("" = the standard rules, else a name in
## CouncilPresets.ORDER). Made by _build_rule_sets().
var _rule_buttons := {}
## The chosen rule set's description, under its buttons.
var _rule_blurb: Label = null


## Called once when the node joins the scene: give the screen the game's
## look, darken the cover, make each seat's button send its role, add the
## rule-set row, then fit everything to the window (now and on every
## resize).
func _ready() -> void:
	theme = UiKit.make_theme()
	$Cover.color = Palette.with_alpha(Palette.VOID, 0.82)
	$Scroll/Center/Card/Col/Seats/Admiral/Col/Pick.pressed.connect(func() -> void: chosen.emit("admiral"))
	$Scroll/Center/Card/Col/Seats/Pilot/Col/Pick.pressed.connect(func() -> void: chosen.emit("pilot"))
	_build_rule_sets()
	resized.connect(_layout)
	_layout()


## Add the rule-set row right under the rules text: a heading, a button for
## the standard rules and one per preset (CouncilPresets.ORDER), then the
## chosen set's description (a wrapping label, so it joins _wide_texts).
func _build_rule_sets() -> void:
	# Step 1: the heading, the button row and the description go in the
	# card's column, in that order, just below the Rules label.
	var col: VBoxContainer = $Scroll/Center/Card/Col
	var at: int = $Scroll/Center/Card/Col/Rules.get_index() + 1
	var heading := UiKit.label("RULE SET", 12, Palette.MIST)
	var row := UiKit.hbox(8)
	_rule_blurb = UiKit.label("", 13, Palette.MIST, true)
	for node: Control in [heading, row, _rule_blurb]:
		col.add_child(node)
		col.move_child(node, at)
		at += 1
	_wide_texts.append(_rule_blurb)
	# Step 2: one toggle button per rule set ("" = the standard rules). The
	# chosen one shows pressed (amber).
	for preset_name: String in [""] + CouncilPresets.ORDER:
		var pn := preset_name
		var text := CouncilPresets.TODAY_LABEL if pn == "" else String(CouncilPresets.LABELS[pn])
		var b := UiKit.button(text, func() -> void: _choose_rules(pn))
		b.toggle_mode = true
		row.add_child(b)
		_rule_buttons[pn] = b
	_show_rules()


## Rule set `preset_name` ("" = the standard rules) was picked: use it for the
## coming match (Game.apply_preset()) and show it.
func _choose_rules(preset_name: String) -> void:
	Game.apply_preset(preset_name)
	_show_rules()


## Show the rule set in Game.preset as chosen: its button pressed, the
## others not, and its description under the row. If the game was launched
## with an unknown --preset (Game.preset_error), say so instead: the match
## would refuse to start until a rule set is picked here, so both seat
## buttons wait too (any rule-set button clears the error, and this runs
## again).
func _show_rules() -> void:
	for pn: String in _rule_buttons:
		(_rule_buttons[pn] as Button).set_pressed_no_signal(pn == Game.preset and Game.preset_error == "")
	var blocked: bool = Game.preset_error != ""
	$Scroll/Center/Card/Col/Seats/Admiral/Col/Pick.disabled = blocked
	$Scroll/Center/Card/Col/Seats/Pilot/Col/Pick.disabled = blocked
	if Game.preset_error != "":
		_rule_blurb.text = "The launch option --preset was not understood: %s. Pick a rule set above before you choose a seat." % Game.preset_error
	else:
		_rule_blurb.text = CouncilPresets.TODAY_BLURB if Game.preset == "" else String(CouncilPresets.BLURBS[Game.preset])


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
