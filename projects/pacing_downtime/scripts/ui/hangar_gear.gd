class_name HangarGear
extends RefCounted
## WHAT THIS IS: the Gear tab of the hangar, and the row of the pilot's 6
## gear slots at the bottom of the hangar. Gear is equipment for the pilot
## (not the ship): a flight suit, helmet, stick, cockpit layout, chair and
## implant. It stays with the pilot when their ship is destroyed.
##
## HOW IT WORKS: build() makes one heading per gear category
## (Items.CATEGORIES) with a grid of that category's items under it, 4
## cards per row. refresh_card() writes each card's footer 4 times a
## second: the price, then "Owned" for an item the pilot has (selected,
## green footer) or the reason it can't be bought (one item per category,
## all slots full, not enough credits). A card that can't be bought is dim
## (see-through, ignores clicks). Clicking a card buys the item (buy()).
## refresh_slots() shows what is in each of the 6 slots and what it sells
## for; clicking a slot sells it (sell_slot()) for Rules.SELL_BACK (half)
## of its price. Gear can only be bought and sold at the mothership.
## This is a "static library": plain functions with no state of their
## own. As a part of Hangar it reads the panel's fields directly.
##
## WHO USES IT: Hangar._set_tab() calls build(); Hangar._refresh() calls
## refresh_card() for every "gear:" card and refresh_slots(); the slot
## cards, which Hangar._ready() makes in the scene's Slots row, call
## sell_slot(). Buying and selling go through PilotProfile (buy_gear,
## gear_blocker, sell_slot).


## Build the Gear tab's cards on hangar `h` (see HOW IT WORKS).
static func build(h: Hangar) -> void:
	var w := h._card_width(4)
	for cat: String in Items.CATEGORIES:
		# A heading with the category's name, then its items, 4 per row.
		h._content.add_child(UiKit.heading(Items.CATEGORY_LABEL[cat]))
		var g := h._grid(4)
		for id: String in Items.by_category(cat):
			var d: Dictionary = Items.ITEMS[id]
			var iid := id
			h._make_card(g, "gear:" + id, String(d["label"]), String(d["blurb"]), w, func() -> void: buy(h, iid))


## Write the footer of card `c` for gear item `id` on hangar `h`. `shop` =
## the pilot may buy right now (Hangar.can_shop); away from the shop every
## card the pilot doesn't own is blocked.
static func refresh_card(h: Hangar, c: CardButton, id: String, shop: bool) -> void:
	var d: Dictionary = Items.ITEMS[id]
	var owned := h.profile.has_item(id)
	var foot := "%d credits" % int(d["price"])
	var blocked := not shop
	# Step 1: owned, or the price plus the reason it can't be bought.
	if owned:
		foot = "Owned"
	else:
		var b := h.profile.gear_blocker(id)
		if b != "":
			foot += "  ·  " + b
			blocked = true
	# Step 2: show it: green when owned, grey when blocked, amber otherwise.
	c.foot.text = foot
	c.foot.visible = true
	c.foot.add_theme_color_override("font_color", Palette.REPAIR if owned else (Palette.MIST if blocked else Palette.AMBER))
	c.set_state(blocked and not owned, owned, 0.55)


## A gear card was clicked: buy item `id` for hangar `h`'s pilot. Away
## from the mothership a toast (a short message on screen) says where to
## buy it; an item already owned does nothing. A refusal shows as a toast;
## a purchase plays the "buy" sound (Events.cue). Then refresh.
static func buy(h: Hangar, id: String) -> void:
	if not h.can_shop_goods():
		Events.toast.emit("Gear is bought at the mothership.")
		return
	if h.profile.has_item(id):
		return
	var err := h.profile.buy_gear(id)
	if err != "":
		Events.toast.emit(err)
	else:
		Events.cue.emit("buy", Vector2.ZERO)
	h._refresh()


## Show what is in each of hangar `h`'s 6 gear slot cards: "Empty" (dim),
## or the item's name ("Repair Kit xN (R)" for a stack of kits; R is the
## key that uses one) and, where we may shop (`shop`), what selling it
## would pay.
static func refresh_slots(h: Hangar, shop: bool) -> void:
	for i in Items.SLOTS:
		var c := h._slots[i]
		var s: Dictionary = h.profile.inventory[i]
		if s.is_empty():
			c.set_lines("Empty", "", "")
			c.set_state(true, false, 0.6)
			continue
		# Step 1: the name and the sell value: half the price, times the
		# stack size for kits.
		var title := ""
		var value := 0.0
		if s["id"] == Items.KIT["id"]:
			title = "Repair Kit x%d (R)" % int(s["count"])
			value = float(Items.KIT["price"]) * Rules.SELL_BACK * float(s["count"])
		else:
			title = String(Items.ITEMS[s["id"]]["label"])
			value = float(Items.ITEMS[s["id"]]["price"]) * Rules.SELL_BACK
		# Step 2: the footer only where we may sell; elsewhere the slot is dim.
		c.set_lines(title, "", ("Sell: +%d" % int(value)) if shop else "")
		c.set_state(not shop, false, 0.9)


## Gear slot `i` was clicked on hangar `h`: sell what is in it (only at
## the mothership; elsewhere a toast says so), then refresh.
static func sell_slot(h: Hangar, i: int) -> void:
	if not h.can_shop():
		Events.toast.emit("Gear is sold at the mothership.")
		return
	h.profile.sell_slot(i)
	h._refresh()
