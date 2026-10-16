class_name AdmiralBoardResearch
extends RefCounted
## WHAT THIS IS: the Research tab of the Admiral board: the mothership
## modules (facilities) the Admiral can build, and the research board of
## techs that those modules open up.
##
## HOW IT WORKS: build() makes the cards once:
##   1. a grid of the mothership modules (Tech.FACILITY_ORDER), 5 per row;
##   2. a row of 8 columns, one per research column (Tech.COLUMNS:
##      Fighter, General, Corvette, Frigate, Capital, Platform, Sensors,
##      Flagship). Each column shows its name, a "Needs the ..." line
##      while its module is missing, and one card per tech.
## The headings tell the player the limits: one module builds at a time
## with 2 queued (waiting in line), one research at a time with 3 queued.
## Clicking a card asks AdmiralCommand to build the module or research the
## tech. refresh() writes each card's footer: "Built" / "Done", progress
## or place in the queue, the price and time, or why it can't be bought
## yet. A card that can't be bought is dim (see-through, ignores clicks);
## a finished one is selected (green footer).
## This is a "static library": plain functions with no state of their
## own. As a part of AdmiralBoard it reads the board's fields directly.
##
## WHO USES IT: AdmiralBoard._set_tab() calls build() and
## AdmiralBoard._refresh() calls refresh() for the Research tab.
## AdmiralBoardMothership also uses tech_card() and refresh() for its
## Flagship cards, and AdmiralBoardFleet uses progress_text().


## Build the Research tab's cards on board `b` (see HOW IT WORKS).
static func build(b: AdmiralBoard) -> void:
	# Step 1: the mothership modules, 5 per row. A card is a fifth of the
	# width after the 4 gaps of 6 pixels (24).
	b._content.add_child(UiKit.heading("Mothership modules · one builds at a time, 2 can be queued"))
	var g := b._grid(5)
	var fw := floorf((b._inner_w() - 24.0) / 5.0)
	for id: String in Tech.FACILITY_ORDER:
		var d: Dictionary = Tech.FACILITIES[id]
		var fid := id
		var c := CardButton.new(String(d["label"]), "", "", fw)
		# A click builds (or queues) the module, if we may give orders.
		c.pressed.connect(func() -> void:
			if b._ok():
				b.world.command.build_facility(b.team, fid)
				b._refresh())
		b._hover(c, "%s: %s" % [d["label"], d["blurb"]])
		g.add_child(c)
		b._cards["fac:" + id] = c
	# Step 2: the research columns side by side: 8 columns share the width
	# after their 7 gaps of 6 pixels.
	b._content.add_child(UiKit.heading("Research · one at a time, 3 can be queued · each column needs its module"))
	var row := UiKit.hbox(6)
	b._content.add_child(row)
	var cw := floorf((b._inner_w() - 7.0 * 6.0) / 8.0)
	for col: String in Tech.COLUMNS:
		# The column's name, then its "Needs the ..." line.
		var cv := UiKit.vbox(4)
		cv.custom_minimum_size = Vector2(cw, 0)
		row.add_child(cv)
		var h := UiKit.label(String(Tech.COLUMN_LABEL[col]), 14, Palette.ICE)
		cv.add_child(h)
		var need := UiKit.label("", 11, Palette.MIST, true)
		UiKit.pin_width(need, cw)
		cv.add_child(need)
		b._cards["colneed:" + col] = need
		# Then one card per tech of this column, in Tech.ORDER order.
		for id: String in Tech.ORDER:
			if Tech.TECHS[id]["column"] != col:
				continue
			cv.add_child(tech_card(b, id, cw))


## Make the card for tech `id`, `w` pixels wide, with smaller text that
## wraps between words so long names fit a narrow column. Clicking it
## starts (or queues) that research. The card is remembered as
## "tech:<id>" for refresh(). Returns it; the caller places it.
static func tech_card(b: AdmiralBoard, id: String, w: float) -> CardButton:
	var d: Dictionary = Tech.TECHS[id]
	var tid := id
	var c := CardButton.new(String(d["label"]), "", "", w)
	# A 13-pixel title and 11-pixel footer, wrapping 20 pixels inside the card.
	c.title.add_theme_font_size_override("font_size", 13)
	c.title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.pin_width(c.title, w - 20.0)
	c.foot.add_theme_font_size_override("font_size", 11)
	c.foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.pin_width(c.foot, w - 20.0)
	# A click researches it, if we may give orders.
	c.pressed.connect(func() -> void:
		if b._ok():
			b.world.command.research(b.team, tid)
			b._refresh())
	# Details line: "Name (cost, time in seconds): blurb". The blurb comes
	# through Tech.blurb(), so a feature module may have replaced it.
	b._hover(c, "%s (%d, %ds): %s" % [d["label"], int(d["cost"]), int(d["time"]), Tech.blurb(id)])
	b._cards["tech:" + id] = c
	return c


## Update every research-type card on board `b`: module cards ("fac:"),
## tech cards ("tech:") and the columns' "Needs the ..." lines
## ("colneed:"). Other keys are skipped, so the Mothership tab can call
## this for its Flagship cards too.
static func refresh(b: AdmiralBoard) -> void:
	var ts := b._ts()
	for key: String in b._cards:
		var node = b._cards[key]
		if key.begins_with("fac:"):
			_refresh_facility(ts, key.substr(4), node)
		elif key.begins_with("tech:"):
			_refresh_tech(ts, key.substr(5), node)
		elif key.begins_with("colneed:"):
			_refresh_column_need(ts, key.substr(8), node)


## One module card `c` for facility `id`: "Built" (selected), its progress
## or queue place, why it can't be built yet (dim), or "cost · seconds"
## with how much money we are short (dim when we can't pay).
static func _refresh_facility(ts: TeamState, id: String, c: CardButton) -> void:
	var d: Dictionary = Tech.FACILITIES[id]
	var foot := ""
	var dim := false
	var sel := false
	# Step 1: already built, or building / waiting in the queue?
	if ts.facilities.has(id):
		foot = "Built"
		sel = true
	elif ts.is_building(id):
		foot = progress_text(ts.building, id)
	else:
		# Step 2: a "blocker" is the reason it can't be built yet ("" = none).
		var b := ts.facility_blocker(id)
		if b != "":
			foot = b
			dim = true
		else:
			# Step 3: price and build time, plus the shortfall if we can't pay.
			foot = "%d · %ds" % [int(d["cost"]), int(d["time"])]
			if not ts.can_afford(float(d["cost"])):
				foot += " · %d short" % int(ceil(float(d["cost"]) - ts.treasury))
				dim = true
	# Step 4: show it: green when built, grey when dim, amber otherwise.
	c.foot.text = foot
	c.foot.visible = true
	c.foot.add_theme_color_override("font_color", Palette.REPAIR if sel else (Palette.MIST if dim else Palette.AMBER))
	c.set_state(dim, sel, 0.5)


## One tech card `c` for tech `id`: "Done" (selected), its progress or
## queue place, or "cost · seconds". It is dim when it can't be researched
## yet or we can't pay. The footer then shows the reason, except when the
## column's module is missing, because the column already says so.
static func _refresh_tech(ts: TeamState, id: String, c: CardButton) -> void:
	var d: Dictionary = Tech.TECHS[id]
	var foot := ""
	var dim := false
	var sel := false
	# Step 1: already done, or researching / waiting in the queue?
	if ts.done.has(id):
		foot = "Done"
		sel = true
	elif ts.is_researching(id):
		foot = progress_text(ts.research, id)
	else:
		var b := ts.tech_blocker(id)
		foot = "%d · %ds" % [int(d["cost"]), int(d["time"])]
		# Step 2: the column header already says which module is missing.
		var fac := Tech.column_facility(String(d["column"]))
		var column_need := not ts.facilities.has("research") or not ts.facilities.has(fac)
		if b != "":
			dim = true
			if not column_need:
				foot = b
		elif not ts.can_afford(float(d["cost"])):
			dim = true
	# Step 3: show it: green when done, grey when dim, amber otherwise.
	c.foot.text = foot
	c.foot.visible = true
	c.foot.add_theme_color_override("font_color", Palette.REPAIR if sel else (Palette.MIST if dim else Palette.AMBER))
	c.set_state(dim, sel, 0.5)


## Column `col`'s "Needs the ..." line `l`: first the Research Module
## (every column needs it), then the column's own module (for the Flagship
## column that is the Research Module itself). Hidden once both are built.
static func _refresh_column_need(ts: TeamState, col: String, l: Label) -> void:
	var fac := Tech.column_facility(col)
	if not ts.facilities.has("research"):
		l.text = "Needs the Research Module"
	elif not ts.facilities.has(fac):
		l.text = "Needs the %s" % Tech.FACILITIES[fac]["label"]
	else:
		l.text = ""
	l.visible = l.text != ""


## The footer for something in a queue. `queue` is TeamState.building or
## TeamState.research: a list of {id, left, total} entries (seconds left
## and seconds in all), the one being worked on first. The first entry
## gets "In progress 45% (12s)"; the ones behind it get "Queued #2",
## "Queued #3", ... Returns "" if `id` isn't in the queue.
static func progress_text(queue: Array, id: String) -> String:
	for i in queue.size():
		var e: Dictionary = queue[i]
		if e["id"] == id:
			# The head of the queue: percent done and whole seconds left.
			if i == 0:
				return "In progress %d%% (%ds)" % [int(100.0 * (1.0 - float(e["left"]) / maxf(0.01, float(e["total"])))), int(ceil(float(e["left"])))]
			return "Queued #%d" % (i + 1)
	return ""
