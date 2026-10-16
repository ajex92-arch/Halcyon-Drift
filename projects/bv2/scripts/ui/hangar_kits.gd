class_name HangarKits
extends RefCounted
## WHAT THIS IS: the Kits tab of the hangar: a single card for buying
## repair kits. A repair kit (used in flight with R) launches a small
## repair drone that heals the pilot's hull for a while. Kits stack: up to
## Items.KIT["stack"] (3) kits share one gear slot.
##
## HOW IT WORKS: build() makes the card (half the tab wide). refresh_card()
## writes its footer 4 times a second: the price, how many kits the pilot
## has, and, where we may shop, the reason a kit can't be bought (not
## enough credits, or all slots full). The card is dim (see-through,
## ignores clicks) away from the shop or when a kit can't be bought.
## Clicking it buys one kit (buy()).
## This is a "static library": plain functions with no state of their
## own. As a part of Hangar it reads the panel's fields directly.
##
## WHO USES IT: Hangar._set_tab() calls build() and Hangar._refresh() calls
## refresh_card() for the "kit" card. Buying goes through
## PilotProfile.buy_kit() (PilotProfile.kit_blocker() gives the reason).


## Build the Kits tab's card on hangar `h` (see HOW IT WORKS).
static func build(h: Hangar) -> void:
	var w := h._card_width(2)
	var g := h._grid(2)
	h._make_card(g, "kit", String(Items.KIT["label"]), "%s\nStacks of %d share one gear slot." % [Items.KIT["blurb"], int(Items.KIT["stack"])], w, func() -> void: buy(h))


## Write the footer of the kit card `c` on hangar `h`: "N credits · you
## have M", plus the reason a kit can't be bought (only where we may shop,
## `shop`). The card is dim when we may not shop or can't buy one.
static func refresh_card(h: Hangar, c: CardButton, shop: bool) -> void:
	var b := h.profile.kit_blocker()
	c.foot.text = "%d credits  ·  you have %d" % [int(Items.KIT["price"]), h.profile.kit_count()] + ("" if b == "" or not shop else "  ·  " + b)
	c.foot.visible = true
	c.set_state(not shop or b != "", false)


## The kit card was clicked: buy one repair kit for hangar `h`'s pilot.
## Away from the mothership a toast (a short message on screen) says where
## to buy them. A refusal shows as a toast; a purchase plays the "buy"
## sound (Events.cue). Then refresh.
static func buy(h: Hangar) -> void:
	if not h.can_shop():
		Events.toast.emit("Repair kits are bought at the mothership.")
		return
	var err := h.profile.buy_kit()
	if err != "":
		Events.toast.emit(err)
	else:
		Events.cue.emit("buy", Vector2.ZERO)
	h._refresh()
