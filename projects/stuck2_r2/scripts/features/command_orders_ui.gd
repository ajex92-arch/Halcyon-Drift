class_name CommandOrdersUi
extends RefCounted
## WHAT THIS IS: the "Command orders" section of the Admiral board's Fleet
## tab: one button per order that a feature module added (Sensor Sweep,
## Supply Drop, Barrage, Bounty, Fortify; see CommandOrders). It shows
## nothing in today's game, because then no order is registered.
##
## HOW IT WORKS: build() adds a heading and a row of buttons to the tab,
## one per entry of world.command.orders, and remembers each button in the
## board's `_cards` under "order:<id>". A button that needs a spot arms the
## map tool of the same name (AdmiralBoard._arm: the Admiral then clicks the
## map); a button that needs none gives the order at once. refresh() (four
## times a second) rewrites each button's text with its price and whether
## it is ready or recharging, and switches it off while the order can't go.
## Every order goes through CommandOrders.run(), the same call the AI admiral
## uses.
## This is a "static library": plain functions with no state of their own.
## As a part of AdmiralBoardFleet it reads the board's fields directly.
##
## WHO USES IT: AdmiralBoardFleet.build() and AdmiralBoardFleet.refresh().


## Add the Command orders section to the Fleet tab of board `b`. Does
## nothing when no order is registered.
static func build(b: AdmiralBoard) -> void:
	var orders: Dictionary = b.world.command.orders
	if orders.is_empty():
		return
	# Step 1: the heading and the row.
	b._content.add_child(UiKit.heading("Command orders (each has a price and a cooldown)"))
	var row := UiKit.hbox(8)
	b._content.add_child(row)
	b._cards["orders_row"] = row
	# Step 2: one button per order. `oid` is a copy for the click function.
	for id in orders:
		var oid: String = id
		var d: Dictionary = orders[id]
		var btn := UiKit.button(str(d["label"]), func() -> void: _press(b, oid), 34)
		b._hover(btn, str(d.get("tip", d["hint"])))
		row.add_child(btn)
		b._cards["order:" + oid] = btn


## The Admiral clicked the button of order `id`: arm its map tool, or give
## the order straight away when it needs no spot. Does nothing while the
## human may not give orders.
static func _press(b: AdmiralBoard, id: String) -> void:
	if not b._ok():
		return
	if CommandOrders.needs_point(b.world, id):
		b._arm(id)
	else:
		CommandOrders.run(b.world, id, b.team, Vector2.ZERO)
		b._refresh()


## Rewrite every order button of board `b`: its name, price and state.
static func refresh(b: AdmiralBoard) -> void:
	var orders: Dictionary = b.world.command.orders
	for id in orders:
		var key: String = "order:" + str(id)
		if not b._cards.has(key):
			continue
		var d: Dictionary = orders[id]
		var btn: Button = b._cards[key]
		var wait := CommandOrders.ready_in(b.world, str(id), b.team)
		var cost := CommandOrders.cost_of(d, b.team)
		var price := ("  %d" % int(cost)) if cost > 0.0 else "  free"
		var state := ("  (%ds)" % int(ceil(wait))) if wait > 0.0 else ""
		btn.text = "%s%s%s" % [d["label"], price, state]
		# A button is dimmed while recharging or unaffordable (a spot order
		# can still be armed: its reason shows when the spot is picked).
		btn.disabled = wait > 0.0 or not b.world.teams[b.team].can_afford(cost)
