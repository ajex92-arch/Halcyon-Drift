class_name RoleHud
extends RefCounted
## WHAT THIS IS: the small bit of the pilot's ship status panel (ShipStatus)
## that belongs to the combat_roles features: the words ESCORTED or ISOLATED
## for a big ship (escort_pd variant), and a pip that lights when the ship's
## energy routing is charged, with the seconds left of a weapons overcharge
## (routing_payoff variant).
##
## HOW IT WORKS: ShipStatus calls draw() at the end of its own drawing. When
## no feature of this fork is on (World.features has no entry for the two
## keys) it returns at once and draws nothing. Otherwise it writes the
## words in the empty strip at the bottom right of the panel, and draws a
## coloured pip (amber = Weapons, blue = Shields, green = Thrusters) at the
## right end of that strip while the ship is charged.
##
## WHO USES IT: ShipStatus._draw() (one line). It reads EscortPdFeature
## and RoutingPayoffFeature through World.features.

## Where the strip starts, from the panel's left edge (pixels): the same x as
## the bars above it.
const X := 140.0
## The strip's baseline, from the panel's bottom edge (pixels up).
const BASE_UP := 6.0


## Draw the feature words and pip for `ship` onto panel `panel`. Called from
## inside the panel's _draw().
static func draw(panel: Control, ship: Ship) -> void:
	var feats := ship.world.features if ship.world != null else {}
	if feats.is_empty():
		return
	var y := panel.size.y - BASE_UP
	var font := ThemeDB.fallback_font
	# The escort status of a big ship.
	var esc = feats.get(EscortPdFeature.KEY)
	if esc != null:
		var words: String = (esc as EscortPdFeature).status(ship)
		if words != "":
			var col := Palette.REPAIR if words.begins_with("ESCORTED") else Palette.CINDER
			panel.draw_string(font, Vector2(X, y), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	# The routing pip, and the overcharge timer.
	var rp = feats.get(RoutingPayoffFeature.KEY)
	if rp != null:
		var r := rp as RoutingPayoffFeature
		var mode := r.charged_mode(ship)
		var over := r.overcharge_left(ship)
		var x := panel.size.x - 22.0
		if mode >= 0:
			var pip := Palette.AMBER
			if mode == Rules.ENERGY_SHIELDS:
				pip = Palette.SHIELD
			elif mode == Rules.ENERGY_THRUSTERS:
				pip = Palette.REPAIR
			panel.draw_circle(Vector2(x, y - 4.0), 5.0, pip)
			panel.draw_string(font, Vector2(x - 60.0, y), "CHARGED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pip)
		if over > 0.0:
			panel.draw_string(font, Vector2(x - 140.0, y), "OVERCHARGE %.1fs" % over, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.AMBER)
