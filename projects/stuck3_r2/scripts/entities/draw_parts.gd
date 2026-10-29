class_name DrawParts
extends RefCounted
## WHAT THIS IS: the test-only "parts switches" of the ship and unit
## drawing. Every ship and minion draws itself again every frame from several
## parts (its flames, shield arcs, drift arrow, bars, name, hull outline). Each
## switch here turns ONE part off, so a test can measure what that part costs
## (the draw-cost table) without changing anything else. With no switch
## given, every part is drawn exactly as always: nothing here changes a match
## or a picture.
##
## HOW IT WORKS:
##   - One plain true/false variable per part, all true ("drawn") at the start.
##     The painters (ShipVisual, UnitVisual, CinderPaint) read them where they
##     draw: `if DrawParts.arcs:` before the shield arcs, and so on.
##   - read_options() reads the command-line option --bench-off=<parts> ONCE
##     (through Game.opt) and turns the named parts off. The painters call it
##     when they are made, and only the first call reads anything. The parts:
##       flames    the three flame emitters of a ship stop and are hidden. They
##                 are still MADE: each CPUParticles2D takes one number from the
##                 game's shared random sequence when it is made, so leaving them
##                 out would change every later dice roll of the match. The
##                 switch never changes how many numbers are taken.
##       arcs      the four shield arcs round a ship
##       arrow     the drift arrow (and its slip tick)
##       bars      the hull and shield bars of ships, minions, turrets and bays
##       name      the name tag above a ship
##       outline   the line round a hull (the fill stays), for every hull
##       redraw    a painter draws once and then stops asking for a new picture
##                 every frame (Godot keeps the last picture). Only right for a
##                 crowd that stands still, which is what the bench uses it for.
##     `all` names every part; `drawing` names every part except redraw (the six
##     things that are drawn, with the picture still redrawn every frame); `none`
##     names none. Example:
##       --bench-off=flames,arcs
##   - set_off() is the same switch for code: the hull gallery's parts bench
##     turns parts on and off while it runs.
##
## WHO USES IT: ShipVisual and UnitVisual (they read the switches and call
## read_options() when they are made), CinderPaint (the outline of the alien
## shapes), and the hull gallery test's parts bench (GalleryMeasure.bench_parts),
## which calls set_off(). The option --bench-off is read here.

## The parts, in the order the bench and its table list them.
const PARTS := ["flames", "arcs", "arrow", "bars", "name", "outline", "redraw"]
## The six parts that are things drawn (every part but the redraw): the word
## `drawing` names them all.
const DRAWING := ["flames", "arcs", "arrow", "bars", "name", "outline"]

## True = the flame emitters are used (the normal game); false = stopped and hidden.
static var flames := true
## True = the four shield arcs are drawn (the normal game).
static var arcs := true
## True = the drift arrow is drawn (the normal game).
static var arrow := true
## True = the hull and shield bars are drawn (the normal game).
static var bars := true
## True = the name tag is drawn (the normal game). (The option calls it "name".)
static var name_tag := true
## True = the outline round a hull is drawn (the normal game).
static var outline := true
## True = a painter asks for a new picture every frame (the normal game);
## false = it draws once and then keeps that picture.
static var redraw := true

## True once the option has been read (or set_off() was called), so it is read
## only once and never overrides a setting made by code.
static var _read := false


## Read --bench-off=<parts> (a comma-separated list of PARTS, `drawing` or `all`) from the
## command line and turn those parts off. Only the first call does anything;
## the painters call it when they are made. A word that is not a part is
## ignored, with a line in the log, so a typo is easy to see. Nothing is
## printed when no part is switched off.
static func read_options() -> void:
	if _read:
		return
	_read = true
	var raw = Game.opt("bench-off", "")
	# A bare --bench-off (no list) has no meaning: say so, change nothing.
	if raw is bool:
		print("bench-off: needs a list, for example --bench-off=%s (or all); nothing switched off" % ",".join(PackedStringArray(PARTS)))
		return
	var text := str(raw)
	if text == "":
		return
	var unknown := set_off(text)
	print("bench-off: parts switched off (test only): %s" % off_list())
	if unknown.size() > 0:
		print("bench-off: not a part, ignored: %s (the parts are %s)" % [", ".join(unknown), ", ".join(PackedStringArray(PARTS))])


## Turn the parts named in `list` (comma-separated; `all` = every part, `drawing` =
## every part but the redraw, `none` = no part) off and every other part on.
## Returns the words that are not parts.
static func set_off(list: String) -> PackedStringArray:
	_read = true
	var off := PackedStringArray()
	var unknown := PackedStringArray()
	for word: String in list.split(",", false):
		var w := word.strip_edges().to_lower()
		if w == "all":
			off.append_array(PackedStringArray(PARTS))
		elif w == "drawing":
			off.append_array(PackedStringArray(DRAWING))
		elif w == "none" or w == "":
			continue
		elif PARTS.has(w):
			off.append(w)
		else:
			unknown.append(w)
	flames = not off.has("flames")
	arcs = not off.has("arcs")
	arrow = not off.has("arrow")
	bars = not off.has("bars")
	name_tag = not off.has("name")
	outline = not off.has("outline")
	redraw = not off.has("redraw")
	return unknown


## The parts that are off right now, as text: "none", "all", "drawing" (every part
## but the redraw), or names joined with "+" (for example "flames+arcs").
static func off_list() -> String:
	var off := PackedStringArray()
	if not flames:
		off.append("flames")
	if not arcs:
		off.append("arcs")
	if not arrow:
		off.append("arrow")
	if not bars:
		off.append("bars")
	if not name_tag:
		off.append("name")
	if not outline:
		off.append("outline")
	if not redraw:
		off.append("redraw")
	if off.size() == 0:
		return "none"
	if off.size() == PARTS.size():
		return "all"
	if off.size() == DRAWING.size() and redraw:
		return "drawing"
	return "+".join(off)
