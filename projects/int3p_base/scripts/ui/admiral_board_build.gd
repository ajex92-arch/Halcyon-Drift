class_name AdmiralBoardBuild
extends RefCounted
## WHAT THIS IS: the Build tab of the Admiral board: mining drones,
## turrets at resource nodes, repair bays and wards.
##
## HOW IT WORKS: build() makes the tab once, in four parts:
##   1. Mining drones (small robot ships that mine ore and bring it home):
##      a count line and a "Build a mining drone" button.
##   2. Turrets: one row per resource node (a field of ore rocks), except
##      the enemy's "inner" nodes (the ones near their mothership). A row
##      has the node's status line, a buy button per turret type allowed
##      there (PD, point-defence, at any node; torpedo turrets only at our
##      inner nodes) and a "View" button that points the camera at it.
##   3. Repair bays: a count line and a button that arms the "bay" map
##      tool (the Admiral then clicks the map to place one).
##   4. Wards (small, hidden lookout posts that let us see around them): a
##      count line and a button that arms the "ward" map tool.
## refresh() rewrites the lines 4 times a second. A turret button that
## can't be used is disabled, with the reason as its tooltip (the text
## that pops up when the mouse rests on it).
## This is a "static library": plain functions with no state of their
## own. As a part of AdmiralBoard it reads the board's fields directly.
##
## WHO USES IT: AdmiralBoard._set_tab() calls build() and
## AdmiralBoard._refresh() calls refresh() for the Build tab. Purchases go
## through AdmiralCommand (build_drone, build_turret; turret_blocker says
## why a turret can't be built).


## Build the Build tab's cards on board `b` (see HOW IT WORKS).
static func build(b: AdmiralBoard) -> void:
	var w := b._inner_w()
	# Step 1: mining drones: the count line, then the buy button.
	b._content.add_child(UiKit.heading("Mining drones"))
	var dr := UiKit.hbox(10)
	b._content.add_child(dr)
	var dl := UiKit.label("", 14, Palette.ICE)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dr.add_child(dl)
	b._cards["drones"] = dl
	var db := UiKit.button("Build a mining drone (%d)" % int(Structures.MINING_DRONE["cost"]), func() -> void:
		if b._ok():
			b.world.command.build_drone(b.team)
			b._refresh(), 34)
	b._hover(db, "Drones fly to the richest safe resource node, mine ore and haul it home. Each delivery pays 60% to the treasury and 40% to your pilots. Enemy pilots hunt them; escorting pilots get a bonus.")
	dr.add_child(db)
	# Step 2: turrets: a note on the rules, then one row per node.
	b._content.add_child(UiKit.heading("Turrets at resource nodes"))
	var note := UiKit.label("PD turrets can go at any node we can hold; torpedo turrets only at the three nodes near our mothership (needs Platform Missiles). You can't build with enemy ships within 1,500 of the node. Turrets are hard to kill without minions: enemy pilots attacking alone deal 30% damage.", 12, Palette.MIST, true)
	UiKit.pin_width(note, w)
	b._content.add_child(note)
	for n: ResourceNode in b.world.nodes:
		_node_row(b, n, w)
	# Step 3: repair bays: the count line and the "pick a spot" button.
	b._content.add_child(UiKit.heading("Repair bays and wards"))
	var br := UiKit.hbox(10)
	b._content.add_child(br)
	var bl := UiKit.label("", 14, Palette.ICE)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(bl)
	b._cards["bays"] = bl
	var bb := UiKit.button("Deploy a repair bay (%d): pick a spot" % int(Structures.REPAIR_BAY["cost"]), func() -> void: b._arm("bay"), 34)
	b._hover(bb, "Repair bay: %s Drones heal hull only while the bay's own hull isn't under fire (with Bay Defenses, it keeps repairing while only its shield is hit). Small enough to anchor in the jungle. Max %d." % [Structures.REPAIR_BAY["blurb"], int(Structures.REPAIR_BAY["max_per_team"])])
	br.add_child(bb)
	b._cards["bay_btn"] = bb
	# Step 4: wards: the count line and the "pick a lit spot" button.
	var wr := UiKit.hbox(10)
	b._content.add_child(wr)
	var wl := UiKit.label("", 14, Palette.ICE)
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wr.add_child(wl)
	b._cards["wards"] = wl
	var wb := UiKit.button("Place a ward (%d): pick a lit spot" % int(Structures.WARD["cost"]), func() -> void: b._arm("ward"), 34)
	b._hover(wb, "Ward: %s It is fragile and hidden from enemies more than %d away unless they ping it. Max %d; the oldest shuts down when you place another." % [Structures.WARD["blurb"], int(Structures.WARD["stealth_radius"]), int(Structures.WARD["max_per_team"])])
	wr.add_child(wb)


## Add the turret row for resource node `n` (nothing for the enemy's inner
## nodes): its status line, a buy button per turret type allowed there,
## and a View button. `w` is the tab's width in pixels.
static func _node_row(b: AdmiralBoard, n: ResourceNode, w: float) -> void:
	if n.node_kind == "inner" and n.side != b.team:
		return
	var row := UiKit.hbox(8)
	b._content.add_child(row)
	# Step 1: the status line: 520 pixels wide, less on a narrow board so
	# the buttons keep 380.
	var nl := UiKit.label("", 13, Palette.ICE)
	nl.custom_minimum_size = Vector2(minf(520.0, w - 380.0), 0)
	row.add_child(nl)
	b._cards["node:" + n.node_id] = nl
	var nid := n.node_id
	# Step 2: a buy button per turret type: PD everywhere, torpedo only at
	# inner nodes (which, here, are always ours).
	for ttype: String in ["pd", "torp"]:
		if ttype == "torp" and n.node_kind != "inner":
			continue
		var td: Dictionary = TurretData.TURRETS[ttype]
		var tt := ttype
		var tb := UiKit.button("%s (%d)" % [td["label"], int(td["cost"])], func() -> void:
			if b._ok():
				b.world.command.build_turret(b.team, nid, tt)
				b._refresh(), 30)
		b._hover(tb, "%s: %s" % [td["label"], td["blurb"]])
		row.add_child(tb)
		b._cards["tbtn:%s:%s" % [nid, ttype]] = tb
	# Step 3: the View button points the camera at the node.
	var pos := n.global_position
	row.add_child(UiKit.button("View", func() -> void: b._view(pos), 30))


## Rewrite the Build tab on board `b`: the drone line, each node's line
## and turret buttons, and the repair bay and ward counts.
static func refresh(b: AdmiralBoard) -> void:
	var ts := b._ts()
	# Step 1: drones: working / most allowed, being built, lost, ore delivered.
	if b._cards.has("drones"):
		var dl: Label = b._cards["drones"]
		dl.text = "%d / %d drones working  ·  %d being built  ·  %d lost  ·  %s ore delivered" % [b.world.mining_drone_count(b.team), int(Structures.MINING_DRONE["max"]), ts.drone_queue.size(), ts.drones_lost, Util.money(ts.ore_delivered)]
	# Step 2: each node's line and turret buttons.
	for key: String in b._cards:
		if key.begins_with("node:"):
			_refresh_node_line(b, key.substr(5), b._cards[key])
		elif key.begins_with("tbtn:"):
			_refresh_turret_button(b, ts, key, b._cards[key])
	# Step 3: count our living repair bays.
	var bays := 0
	for bay: RepairBay in b.world.bays:
		if bay.team == b.team and bay.alive:
			bays += 1
	# Step 4: the bay line ("needs research" until Repair Bays is done);
	# the button is off without the research or at the limit.
	if b._cards.has("bays"):
		var bl: Label = b._cards["bays"]
		var drones_txt := "%d drone%s each" % [ts.bay_drones, "" if ts.bay_drones == 1 else "s"]
		bl.text = "Repair bays: %d / %d  ·  %s%s" % [bays, int(Structures.REPAIR_BAY["max_per_team"]), drones_txt, "  ·  defenses" if ts.bay_defenses else ""]
		if not ts.repair_bays:
			bl.text = "Repair bays: needs Repair Bays research (General column)"
		var bb: Button = b._cards["bay_btn"]
		bb.disabled = not ts.repair_bays or bays >= int(Structures.REPAIR_BAY["max_per_team"])
	# Step 5: count our living wards for the ward line.
	if b._cards.has("wards"):
		var wards := 0
		for wd: Ward in b.world.wards:
			if wd.team == b.team and wd.alive:
				wards += 1
		var wl: Label = b._cards["wards"]
		wl.text = "Wards: %d / %d" % [wards, int(Structures.WARD["max_per_team"])]


## Node `node_id`'s line `l`: name, who holds it ("ours", "ENEMY",
## "unclaimed"), turrets out of its slots (the bigger of the two teams'
## counts) and the share of its ore left. Red (Palette.CINDER) when the
## enemy holds it.
static func _refresh_node_line(b: AdmiralBoard, node_id: String, l: Label) -> void:
	var n := b.world.node_by_id(node_id)
	# Step 1: who holds it (owner_team is -1 for nobody).
	var holder := n.owner_team()
	var who := "unclaimed"
	if holder == b.team:
		who = "ours"
	elif holder >= 0:
		who = "ENEMY"
	# Step 2: the line and its colour.
	l.text = "%s  ·  %s  ·  turrets %d/%d  ·  ore %d%%" % [n.node_name, who, maxi(n.turret_count(0), n.turret_count(1)), n.slots.size(), int(100.0 * n.total_ore() / maxf(1.0, n.total_ore_max()))]
	l.add_theme_color_override("font_color", Palette.CINDER if holder >= 0 and holder != b.team else Palette.ICE)


## Turret button `tb`, whose `key` is "tbtn:<node id>:<turret type>":
## disable it when AdmiralCommand gives a reason not to build, or when the
## treasury can't pay. The reason becomes its tooltip.
static func _refresh_turret_button(b: AdmiralBoard, ts: TeamState, key: String, tb: Button) -> void:
	var parts := key.split(":")
	var reason := b.world.command.turret_blocker(b.team, parts[1], parts[2])
	if reason == "" and not ts.can_afford(float(TurretData.TURRETS[parts[2]]["cost"])):
		reason = "Not enough in the treasury"
	tb.disabled = reason != ""
	tb.tooltip_text = reason
