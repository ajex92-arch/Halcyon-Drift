class_name AdmiralBoardMothership
extends RefCounted
## WHAT THIS IS: the Mothership tab of the Admiral board: how our
## mothership (the team's huge home ship) is doing, the button to move it,
## and the Flagship research cards that upgrade it.
##
## HOW IT WORKS: build() makes the tab once, in three parts:
##   1. a status block: hull and shields, its guns, and warnings (respawn
##      strain, systems failure, the emergency retreat);
##   2. a "Move the mothership: pick a spot" button that arms the "move"
##      map tool (the Admiral then clicks the map), with the reason next to
##      it when it can't move yet;
##   3. a grid of the Flagship column's research cards, 5 per row (made by
##      AdmiralBoardResearch.tech_card, so they work like the Research tab).
## refresh() rewrites the status block and the move button 4 times a
## second, then lets AdmiralBoardResearch.refresh() update the Flagship
## cards.
## This is a "static library": plain functions with no state of their
## own. As a part of AdmiralBoard it reads the board's fields directly.
##
## WHO USES IT: AdmiralBoard._set_tab() calls build() and
## AdmiralBoard._refresh() calls refresh() for the Mothership tab. It asks
## AdmiralCommand.move_blocker() why the mothership can't move (engines
## online at 20:00, the Admiral must be docked).


## Build the Mothership tab's cards on board `b` (see HOW IT WORKS).
static func build(b: AdmiralBoard) -> void:
	var w := b._inner_w()
	# Step 1: the status block, as wide as the tab (filled in by refresh()).
	var st := UiKit.label("", 14, Palette.ICE, true)
	UiKit.pin_width(st, w)
	b._content.add_child(st)
	b._cards["ms_status"] = st
	# Step 2: the move button, and a label for why it can't move yet.
	var mv := UiKit.hbox(10)
	b._content.add_child(mv)
	var mb := UiKit.button("Move the mothership: pick a spot", func() -> void: b._arm("move"), 34)
	b._hover(mb, "From 20:00 a docked Admiral can move the mothership along the lanes (it's too big for the jungle). It is slow; moving it forward brings its guns, docking and respawns closer to the fight, and its hull closer to enemy capital ships.")
	mv.add_child(mb)
	b._cards["move_btn"] = mb
	var ml := UiKit.label("", 13, Palette.MIST)
	mv.add_child(ml)
	b._cards["move_why"] = ml
	# Step 3: the Flagship research cards, 5 per row. A card is a fifth of
	# the width after the 4 gaps of 6 pixels (24).
	b._content.add_child(UiKit.heading("Flagship research (needs the Research Module)"))
	var g := b._grid(5)
	var cw := floorf((w - 24.0) / 5.0)
	for id: String in Tech.ORDER:
		if Tech.TECHS[id]["column"] == "flagship":
			g.add_child(AdmiralBoardResearch.tech_card(b, id, cw))
	# Step 4: with Fleet Doctrine (DoctrineFeature) its button comes last.
	if DoctrineFeature.current() != null:
		DoctrineFeature.build_card(b)


## Rewrite the Mothership tab on board `b`: the status block, the move
## button and its reason, then the Flagship cards.
static func refresh(b: AdmiralBoard) -> void:
	var ts := b._ts()
	var ms := b.world.mothership(b.team)
	# Step 1: the status block (skipped while we have no mothership).
	if b._cards.has("ms_status") and ms != null:
		var l: Label = b._cards["ms_status"]
		l.text = "\n".join(_status_lines(ts, ms))
	# Step 2: the move button is off while AdmiralCommand gives a reason
	# ("" = it may move); the reason shows next to it.
	if b._cards.has("move_btn"):
		var why := b.world.command.move_blocker(b.team)
		var mb: Button = b._cards["move_btn"]
		mb.disabled = why != ""
		var ml: Label = b._cards["move_why"]
		ml.text = why
	# Step 3: the Flagship cards are research cards ("tech:" keys).
	AdmiralBoardResearch.refresh(b)
	# Step 4: the Fleet Doctrine button (only with DoctrineFeature).
	if DoctrineFeature.current() != null:
		DoctrineFeature.refresh_card(b)


## The lines of the status block for mothership `ms` of team state `ts`,
## top to bottom:
##   - hull and shields (now / most, and the hull as a percent);
##   - its guns: the built-in point-defense and medium cannons (counted
##     from Structures.MOTHERSHIP's mount lists) plus the ones research
##     added (ts.ms_pd, ms_flak, ms_heavy, ms_ion);
##   - RESPAWN STRAIN while ts.strain_t (seconds) is running;
##   - SYSTEMS FAILURE while ms.failure_t (seconds) is running;
##   - the emergency retreat for this match (the "retreat" game option),
##     and whether it was used, unless the option is "none".
static func _status_lines(ts: TeamState, ms: Mothership) -> Array:
	var lines: Array = []
	# Step 1: hull and shields (Util.money writes a number with separators).
	lines.append("Hull %s / %s (%d%%)  ·  shields %s / %s" % [Util.money(ms.hull), Util.money(ms.hull_max), int(ms.hull_frac() * 100.0), Util.money(ms.shields.total()), Util.money(ms.shields.max_total)])
	# Step 2: the guns, built-in plus researched.
	var base_pd := (Structures.MOTHERSHIP["pd_mounts"] as Array).size()
	var base_cannons := (Structures.MOTHERSHIP["cannon_mounts"] as Array).size()
	lines.append("Guns: %d point-defense, %d medium cannons, %d flak, %d heavy cannons, %d ion lance" % [base_pd + ts.ms_pd, base_cannons, ts.ms_flak, ts.ms_heavy, ts.ms_ion])
	# Step 3: the warnings, each with whole seconds left (rounded up).
	if ts.strain_t > 0.0:
		lines.append("RESPAWN STRAIN: too many pilots respawned at once. Guns slowed and shields not recharging for %ds." % int(ceil(ts.strain_t)))
	if ms.failure_t > 0.0:
		lines.append("SYSTEMS FAILURE: no launches, respawns or shopping here for %ds; guns at half." % int(ceil(ms.failure_t)))
	# Step 4: the emergency retreat (unless the "retreat" option is
	# "none").
	if Game.variant("retreat") != "none":
		lines.append("Emergency systems failure at 35%% hull: %s" % ("used" if ms.retreat_used else "not used yet"))
	return lines
