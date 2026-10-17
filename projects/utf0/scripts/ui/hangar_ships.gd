class_name HangarShips
extends RefCounted
## WHAT THIS IS: the Ships tab of the hangar: one card per hull (ship
## type) the pilot can buy for their next launch.
##
## HOW IT WORKS: build() writes a short intro, then makes a grid of cards,
## 2 per row, in Ships.ORDER. Each card shows the hull's size class, its
## description and its numbers (hull, shields, top speed, special
## ability). refresh_card() writes each card's footer 4 times a second:
##   - "Locked: needs ..." while the Admiral hasn't researched it yet;
##   - "Your ship for the next launch" for the hull already chosen (the
##     card is selected, with a green footer);
##   - otherwise the price ("Free" for a Scout). If the pilot already has
##     a hull, the old one is traded in: they get back
##     Rules.HULL_TRADE_IN (half) of its price and Rules.MODULE_TRADE_IN
##     (40%) of its modules' prices, so the footer adds the price after
##     trade-in, and how much is missing if they can't afford it.
## A card that can't be bought right now is dim (see-through, ignores
## clicks). Clicking a card buys that hull (buy()).
## This is a "static library": plain functions with no state of their
## own. As a part of Hangar it reads the panel's fields directly.
##
## WHO USES IT: Hangar._set_tab() calls build() and Hangar._refresh() calls
## refresh_card() for every "ship:" card. Buying goes through
## PilotProfile.buy_hull(), which does the same trade-in sums.


## Build the Ships tab's cards on hangar `h` (see HOW IT WORKS).
static func build(h: Hangar) -> void:
	# Step 1: the intro, as wide as the tab.
	var intro := UiKit.label("Strike craft (Scout to Bomber) fit through the jungle's narrow gaps. Corvettes and bigger stay in the lanes, see farther and hit harder, but are slow to turn and easy prey out of position. Buying a different ship trades your current one in for half its price (modules 40%).", 13, Palette.MIST, true)
	UiKit.pin_width(intro, h._card_width(1))
	h._content.add_child(intro)
	# Step 2: one card per hull, 2 per row.
	var g := h._grid(2)
	var w := h._card_width(2)
	for id: String in Ships.ORDER:
		var d: Dictionary = Ships.HULLS[id]
		# The hull's "size" (0..3) picks its size class.
		var size_label: String = ["Strike craft · fits the jungle", "Corvette", "Frigate", "Capital ship"][int(d["size"])]
		var sub := "%s\n%s\nHull %d · Shields %d · Top speed %d · Ability: %s (%s)" % [size_label, d["blurb"], int(d["hull"]), int(d["shield"]), int(d["max"]), d["special_label"], d["special_info"]]
		var hid := id
		h._make_card(g, "ship:" + id, String(d["label"]), sub, w, func() -> void: buy(h, hid))


## Write the footer of card `c` for hull `id` on hangar `h` (see HOW IT
## WORKS). `shop` = the pilot may buy right now (Hangar.can_shop); `ts` =
## our team's state, which says which hulls are unlocked.
static func refresh_card(h: Hangar, c: CardButton, id: String, shop: bool, ts: TeamState) -> void:
	var p := h.profile
	var d: Dictionary = Ships.HULLS[id]
	var owned := p.hull_id == id
	var foot := ""
	var blocked := false
	# Step 1: locked, already ours, or for sale?
	if not ts.ship_unlocked(id):
		foot = "Locked: needs %s (the Admiral researches it)" % Tech.ship_unlock_label(id)
		blocked = true
	elif owned:
		foot = "Your ship for the next launch"
	else:
		# Step 2: what the current hull and its modules would trade in for.
		var refund := 0.0
		if p.hull_id != "":
			refund = float(Ships.HULLS[p.hull_id]["price"]) * Rules.HULL_TRADE_IN
			for mid: String in p.modules:
				refund += Modules.price_for(mid, p.hull_id) * Rules.MODULE_TRADE_IN
		# Step 3: the price, the price after trade-in (or the money back
		# when the trade-in is worth more), and any shortfall.
		var net := float(d["price"]) - refund
		foot = "Free" if float(d["price"]) <= 0.0 else "%d credits" % int(d["price"])
		if refund > 0.0:
			foot += " (%s after trade-in)" % (("%d" % int(net)) if net > 0.0 else "you get %d back" % int(-net))
		if p.credits + refund < float(d["price"]):
			foot += "  ·  %d short" % int(ceil(float(d["price"]) - p.credits - refund))
			blocked = true
	# Step 4: away from the shop, every hull but ours is blocked.
	if not shop and not owned:
		blocked = true
	# Step 5: show it: green when ours, grey when blocked, amber otherwise.
	c.foot.text = foot
	c.foot.visible = true
	c.foot.add_theme_color_override("font_color", Palette.REPAIR if owned else (Palette.MIST if blocked else Palette.AMBER))
	c.set_state(blocked, owned, 0.55)


## A ship card was clicked: buy hull `id` for hangar `h`'s pilot (only
## where we may shop). A refusal shows as a toast (a short message on
## screen); a purchase plays the "buy" sound (Events.cue). Then refresh.
static func buy(h: Hangar, id: String) -> void:
	if not h.can_shop():
		return
	var err := h.profile.buy_hull(id, h.world.teams[h.profile.team])
	if err != "":
		Events.toast.emit(err)
	else:
		Events.cue.emit("buy", Vector2.ZERO)
	h._refresh()
