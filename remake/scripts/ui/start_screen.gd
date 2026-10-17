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
##
## WHO USES IT: main.gd shows it from scenes/ui/start_screen.tscn and
## connects `chosen` to its start(role).

## Sent once the player picks a seat: role is "admiral" or "pilot".
signal chosen(role: String)

## The main card (its width follows the window, up to 980 pixels).
@onready var _card: PanelContainer = $Scroll/Center/Card
## The wrapped texts that run across the whole card: the rules and the
## controls. A new wrapping label in the scene must be added here (or to
## _seat_texts), or it comes out far too tall (see _layout()).
@onready var _wide_texts: Array[Label] = [$Scroll/Center/Card/Col/Rules, $Scroll/Center/Card/Col/Controls]
## The wrapped texts inside the two seat cards (half the card each).
@onready var _seat_texts: Array[Label] = [$Scroll/Center/Card/Col/Seats/Admiral/Col/Body, $Scroll/Center/Card/Col/Seats/Pilot/Col/Body]


## Called once when the node joins the scene: give the screen the game's
## look, darken the cover, make each seat's button send its role, then fit
## everything to the window (now and on every resize).
func _ready() -> void:
	theme = UiKit.make_theme()
	$Cover.color = Palette.with_alpha(Palette.VOID, 0.82)
	$Scroll/Center/Card/Col/Seats/Admiral/Col/Pick.pressed.connect(func() -> void: chosen.emit("admiral"))
	$Scroll/Center/Card/Col/Seats/Pilot/Col/Pick.pressed.connect(func() -> void: chosen.emit("pilot"))
	resized.connect(_layout)
	_layout()


## Fit the card to the window: w = the window width minus 40 pixels, but at
## most 980. Then give every wrapping label a fixed width (UiKit.pin_width),
## because a wrapping label can't measure its height until it knows its
## width: text inside a seat card gets (w - 74) / 2 pixels (half the card,
## after padding and the gap between the cards), all other text w - 46.
func _layout() -> void:
	var w := minf(980.0, size.x - 40.0)
	_card.custom_minimum_size = Vector2(w, 0)
	for l in _wide_texts:
		UiKit.pin_width(l, w - 46.0)
	for l in _seat_texts:
		UiKit.pin_width(l, (w - 74.0) * 0.5)
