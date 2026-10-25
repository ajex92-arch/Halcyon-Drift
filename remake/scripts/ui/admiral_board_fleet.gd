class_name AdmiralBoardFleet
extends RefCounted
## WHAT THIS IS: the Fleet tab of the Admiral board: the rally waypoint
## and Fleet Command (the late-game module that lets the Admiral buy
## minions and give them orders). Minions are the small AI ships that fly
## down the lanes.
##
## HOW IT WORKS: build() makes the tab once, in three parts:
##   1. Rally waypoint: a button that arms the "waypoint" map tool (the
##      Admiral then clicks the map), and a line saying where the waypoint
##      is and for how long.
##   2. Fleet Command: a status line, then a buy grid with one row per
##      minion type (fighter, bomber, corvette): its name and price, then a
##      "Launch to <lane>" button for each lane.
##   3. Orders for selected minions: "Select all", a "Push <lane>" button
##      per lane, and "Move to…" / "Hold at…", which arm the "fleet_move"
##      and "fleet_hold" map tools.
## refresh() rewrites the lines 4 times a second. The buy grid and the
## orders row only show once the Fleet Command Module is built; before
## that the status line explains how to get it.
## This is a "static library": plain functions with no state of their
## own. As a part of AdmiralBoard it reads the board's fields directly.
##
## WHO USES IT: AdmiralBoard._set_tab() calls build() and
## AdmiralBoard._refresh() calls refresh() for the Fleet tab. Purchases go
## through AdmiralCommand (buy_minion); orders go through the
## CommandOverlay (select_all, order_lane); MinionDirector says whether
## Fleet Command is online and how many minions are alive.


## Build the Fleet tab's cards on board `b` (see HOW IT WORKS).
static func build(b: AdmiralBoard) -> void:
	var w := b._inner_w()
	# Step 1: the rally waypoint button and its status line.
	b._content.add_child(UiKit.heading("Rally waypoint"))
	var wr := UiKit.hbox(10)
	b._content.add_child(wr)
	var wb := UiKit.button("Set the rally waypoint: pick a spot", func() -> void: b._arm("waypoint"), 34)
	b._hover(wb, "For %ds, our ships inside the circle get +8%% speed, +25%% shield regeneration and +15%% vision, and AI pilots group up there. Place it within 6,000 of the enemy mothership to order a SIEGE: our AI frigates, capital ships and bombers converge on that lane and attack the mothership." % int(Rules.WAYPOINT_TIME))
	wr.add_child(wb)
	var wl := UiKit.label("", 13, Palette.MIST)
	wr.add_child(wl)
	b._cards["wp"] = wl
	# Step 1b: the orders that feature modules add (Sensor Sweep, ...); this
	# adds nothing in today's game.
	CommandOrdersUi.build(b)
	# Step 2: the Fleet Command status line, as wide as the tab.
	b._content.add_child(UiKit.heading("Fleet Command"))
	var fl := UiKit.label("", 13, Palette.MIST, true)
	UiKit.pin_width(fl, w)
	b._content.add_child(fl)
	b._cards["fleet_status"] = fl
	# Step 3: the buy grid (4 columns: the minion's name, then a button for
	# each of the 3 lanes) and the orders row.
	_build_buy_grid(b)
	_build_orders_row(b)


## Add the minion buy grid to board `b`: for each of fighter, bomber and
## corvette, a "Name (price)" label and a "Launch to <lane>" button per
## lane (MapLayout.LANE_ORDER: top, mid, bot). A click buys that minion
## for that lane, if we may give orders.
static func _build_buy_grid(b: AdmiralBoard) -> void:
	var buy := b._grid(4)
	b._cards["fleet_buy"] = buy
	for type_id: String in ["fighter", "bomber", "corvette"]:
		var md: Dictionary = Minions.TYPES[type_id]
		buy.add_child(UiKit.label("%s (%d)" % [md["label"], int(md["buy_cost"])], 13, Palette.ICE))
		for lane: String in MapLayout.LANE_ORDER:
			# Copies for the click function to remember.
			var tid := type_id
			var ln := lane
			var lb := UiKit.button("Launch to %s" % MapLayout.LANES[lane]["label"], func() -> void:
				if b._ok():
					b.world.command.buy_minion(b.team, tid, ln)
					b._refresh(), 30)
			buy.add_child(lb)


## Add the orders row to board `b`: "Select all" (every live minion of
## ours), "Push <lane>" per lane (send the selection down it), and
## "Move to…" / "Hold at…" (arm a map tool, then click the map).
static func _build_orders_row(b: AdmiralBoard) -> void:
	b._content.add_child(UiKit.heading("Orders for selected minions (drag a box on the map to select; right-click the map to send them)"))
	var orow := UiKit.hbox(6)
	b._content.add_child(orow)
	b._cards["fleet_orders"] = orow
	# Step 1: select every minion.
	orow.add_child(UiKit.button("Select all", func() -> void:
		b.overlay.select_all()
		b._refresh(), 30))
	# Step 2: one Push button per lane ("Push top lane", ...).
	for lane: String in MapLayout.LANE_ORDER:
		var ln := lane
		orow.add_child(UiKit.button("Push %s" % MapLayout.LANES[lane]["label"].to_lower(), func() -> void:
			b.overlay.order_lane(ln)
			b._refresh(), 30))
	# Step 3: the two map tools.
	orow.add_child(UiKit.button("Move to…", func() -> void: b._arm("fleet_move"), 30))
	orow.add_child(UiKit.button("Hold at…", func() -> void: b._arm("fleet_hold"), 30))


## Rewrite the Fleet tab on board `b`: the waypoint line, the Fleet
## Command status line, and whether the buy grid and orders row show.
static func refresh(b: AdmiralBoard) -> void:
	var ts := b._ts()
	# Step 1: "Active at <place> for <seconds>s", or "No waypoint set".
	if b._cards.has("wp"):
		var wl: Label = b._cards["wp"]
		wl.text = ("Active at %s for %ds" % [Rules.display_label(b.world.place_name(ts.waypoint)), int(ts.waypoint_until - b.world.time)]) if ts.has_waypoint() else "No waypoint set"
	# Step 1b: the buttons of the orders that feature modules add.
	CommandOrdersUi.refresh(b)
	# Step 2: the status line: online, being built, or how to get it.
	if b._cards.has("fleet_status"):
		var fl: Label = b._cards["fleet_status"]
		var controlled := b.world.minion_director.controlled(b.team)
		fl.text = _status_text(b, ts, controlled)
		# Step 3: buying and orders only once Fleet Command is online.
		(b._cards["fleet_buy"] as Control).visible = controlled
		(b._cards["fleet_orders"] as Control).visible = controlled


## The Fleet Command status line for board `b` (team state `ts`;
## `controlled` = the Fleet Command Module is built):
##   - online: free minion waves have stopped; how many minions may be
##     alive (Minions.control_cap()), are alive, and are selected;
##   - being built: its progress (AdmiralBoardResearch.progress_text);
##   - otherwise: what the module does and the minion prices.
static func _status_text(b: AdmiralBoard, ts: TeamState, controlled: bool) -> String:
	if controlled:
		return "Fleet Command is online: free minion waves have stopped. Buy minions from the treasury (up to %d alive) and give them orders. Alive: %d. Selected: %d." % [Minions.control_cap(), b.world.minion_director.alive_count(b.team), b.overlay.selected.size()]
	elif ts.is_building("fleet"):
		return "The Fleet Command Module is being built (%s)." % AdmiralBoardResearch.progress_text(ts.building, "fleet")
	return "Late game: build the Fleet Command Module (Research tab, needs the Capital Ship Facility). Free minion waves then stop and you buy minions (Snub-Fighters %d, Light Bombers %d, Patrol Leaders %d; up to %d alive) and command them directly." % [int(Minions.TYPES["fighter"]["buy_cost"]), int(Minions.TYPES["bomber"]["buy_cost"]), int(Minions.TYPES["corvette"]["buy_cost"]), Minions.control_cap()]
