class_name EconBanner
extends CanvasLayer
## WHAT THIS IS: a small gold text banner at the top of the screen that the
## economy features of the fork economy_comebacks use to tell the player
## something about the match: "Halcyon are behind: comeback bounties are
## on", or the morale meters. It is only for looking at; it changes nothing
## in the game.
##
## HOW IT WORKS: a feature calls EconBanner.set_line(world, "name", "text").
## The first call makes one banner under the World (a "CanvasLayer" is a
## flat layer of screen items drawn on top of the game). Each named line
## stays until the same name is set again, with "" to remove it. All the
## lines are shown, one under the other, in one label. When the game runs
## with no window (--headless, as in every test match) no banner is made
## at all and set_line() does nothing, so such runs cost nothing.
##
## WHO USES IT: ComebackDirector (the comeback banner) and MoraleFeature
## (the morale meter).

## The lines to show: line name -> text. Insertion order is the order on
## screen.
var lines := {}
## The label that shows all the lines.
var _label: Label = null


## Set (or, with "", remove) the line called `key` on the banner of match
## `world`. Does nothing when there is no window.
static func set_line(world: World, key: String, text: String) -> void:
	# Step 1: no window, no banner.
	if DisplayServer.get_name() == "headless":
		return
	# Step 2: find the match's banner, or make it the first time.
	var b := world.get_node_or_null("EconBanner") as EconBanner
	if b == null:
		if text == "":
			return
		b = EconBanner.new()
		b.name = "EconBanner"
		world.add_child(b)
	b._put(key, text)


## Store one line and rewrite the label. The features write the internal
## team labels (Rules.TEAM_NAMES); Rules.display_label() turns them into the
## names the player sees ("Aurelian").
func _put(key: String, text: String) -> void:
	if text == "":
		lines.erase(key)
	else:
		lines[key] = Rules.display_label(text)
	if _label != null:
		_label.text = "\n".join(PackedStringArray(lines.values()))
		_label.visible = not lines.is_empty()


## Godot calls this when the banner joins the match: build the label, near
## the top of the screen under the clock, in gold with a dark outline.
func _ready() -> void:
	layer = 5
	_label = Label.new()
	add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 70.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Palette.AMBER)
	_label.add_theme_color_override("font_outline_color", Palette.VOID)
	_label.add_theme_constant_override("outline_size", 5)
	_label.text = "\n".join(PackedStringArray(lines.values()))
	_label.visible = not lines.is_empty()
