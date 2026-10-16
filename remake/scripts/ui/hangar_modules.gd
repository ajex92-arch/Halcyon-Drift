class_name HangarModules
extends RefCounted
## WHAT THIS IS: the Modules tab of the hangar: one card per ship module
## (an add-on fitted to a hull, such as an extra gun), up to
## Modules.MAX_PER_SHIP (2) per ship.
##
## HOW IT WORKS: build() writes a note line, then makes a grid of cards,
## 2 per row, in Modules.ORDER. refresh_card() writes each card's footer
## 4 times a second. It looks at the hull for the next launch, or, while
## flying, at the ship being flown:
##   - "Pick a ship first" when there is no hull yet;
##   - "Installed · click to sell for N" for a fitted module (selected,
##     green footer); selling gives back Rules.MODULE_TRADE_IN (40%);
##   - why it doesn't fit this hull, "ship already has 2 modules", or the
##     price (it depends on the ship's size) and any shortfall.
## Modules can be changed docked, while waiting to respawn, or flying
## inside one of our repair bays' range ("bay" mode); anywhere else the
## cards are blocked. A blocked card is dim (see-through, ignores clicks).
## Clicking a card buys or sells the module (toggle()). refresh_note()
## keeps the note line up to date.
## This is a "static library": plain functions with no state of their
## own. As a part of Hangar it reads the panel's fields directly.
##
## WHO USES IT: Hangar._set_tab() calls build() and Hangar._refresh() calls
## refresh_card() for every "mod:" card and refresh_note() for the "note".
## Buying and selling go through PilotProfile.toggle_module() at the
## mothership, or World.swap_module_in_bay() inside a repair bay's range.


## Build the Modules tab's cards on hangar `h` (see HOW IT WORKS).
static func build(h: Hangar) -> void:
	var w := h._card_width(2)
	# Step 1: the note line, as wide as the tab (refresh_note fills it).
	var note := UiKit.label("", 13, Palette.MIST, true)
	UiKit.pin_width(note, h._card_width(1))
	h._content.add_child(note)
	h._cards["note"] = note
	# Step 2: one card per module, 2 per row.
	var g := h._grid(2)
	for id: String in Modules.ORDER:
		var d: Dictionary = Modules.MODULES[id]
		var mid := id
		h._make_card(g, "mod:" + id, String(d["label"]), String(d["blurb"]), w, func() -> void: toggle(h, mid))


## Write the footer of card `c` for module `id` on hangar `h` in mode `m`
## (Hangar.mode) (see HOW IT WORKS).
static func refresh_card(h: Hangar, c: CardButton, id: String, m: String) -> void:
	var p := h.profile
	# Step 1: which hull and modules: the next launch's, or, in flight, the
	# ship being flown.
	var hull := p.hull_id
	var mods: Array = p.modules
	if (m == "bay" or m == "flying") and p.ship != null and is_instance_valid(p.ship):
		hull = p.ship.hull_id
		mods = p.ship.modules
	if hull == "":
		c.foot.text = "Pick a ship first"
		c.foot.visible = true
		c.set_state(true, false)
		return
	# Step 2: installed already, and may we change modules here?
	var installed := mods.has(id)
	var price := Modules.price_for(id, hull)
	var editable := m == "dock" or m == "dead" or m == "bay"
	var foot := ""
	var blocked := not editable
	if installed:
		foot = "Installed  ·  click to sell for %d" % int(floorf(price * Rules.MODULE_TRADE_IN))
	else:
		# Step 3: a "blocker" is a reason it can't be fitted ("" = none).
		var fit := Modules.fit_blocker(id, hull)
		if fit != "":
			foot = fit
			blocked = true
		elif mods.size() >= Modules.MAX_PER_SHIP:
			foot = "%d credits  ·  ship already has 2 modules" % int(price)
			blocked = true
		else:
			# Step 4: the price, plus the shortfall if we can't pay.
			foot = "%d credits" % int(price)
			if p.credits < price:
				foot += "  ·  %d short" % int(ceil(price - p.credits))
				blocked = true
	# Step 5: show it: green when installed, grey when blocked, amber
	# otherwise. An installed module stays clickable (to sell) where
	# modules can be changed.
	c.foot.text = foot
	c.foot.visible = true
	c.foot.add_theme_color_override("font_color", Palette.REPAIR if installed else (Palette.MIST if blocked else Palette.AMBER))
	c.set_state(blocked and not (installed and editable), installed, 0.55)


## Write hangar `h`'s note line `note` for mode `m`: "Pick a ship first"
## while there is no hull and we are not flying; otherwise the module
## rules (2 per ship, lost with the ship, sold back for 40%).
static func refresh_note(h: Hangar, note: Label, m: String) -> void:
	if h.profile.hull_id == "" and m != "flying" and m != "bay":
		note.text = "Pick a ship first; modules are fitted to it. Prices scale with ship size."
	else:
		note.text = "Up to 2 modules per ship. They are lost if your ship is destroyed. Click an installed module to sell it for 40%. Prices scale with ship size."


## A module card was clicked: buy module `id`, or sell it if it is fitted.
## Inside a repair bay's range this goes through World.swap_module_in_bay
## (it changes the ship being flown); docked or waiting to respawn,
## through PilotProfile.toggle_module (the next launch's ship); anywhere
## else it is refused. A refusal shows as a toast (a short message on
## screen); success plays the "buy" sound (Events.cue). Then refresh.
static func toggle(h: Hangar, id: String) -> void:
	var m := h.mode()
	var err := ""
	if m == "bay":
		err = h.world.swap_module_in_bay(h.profile, id)
	elif m == "dock" or m == "dead":
		err = h.profile.toggle_module(id)
	else:
		err = "Dock, or fly inside a repair bay's range, to change modules"
	if err != "":
		Events.toast.emit(err)
	else:
		Events.cue.emit("buy", Vector2.ZERO)
	h._refresh()
