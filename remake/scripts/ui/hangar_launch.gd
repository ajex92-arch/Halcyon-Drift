class_name HangarLaunch
extends RefCounted
## WHAT THIS IS: the launching side of the hangar: the status line under
## the title (where the pilot is, and which ship they will fly), the big
## Launch button, the row of hyperspace launch buttons, and the launches
## themselves.
##
## HOW IT WORKS: the status line, the Launch button and the (empty)
## hyperspace row are nodes in the hangar's scene, scenes/ui/hangar.tscn
## (Head > Texts > Status, Head > Launch, BayRow); this file only fills
## them in. Hangar._refresh() calls status_text(), refresh_button()
## and refresh_bay_row() 4 times a second with the pilot's mode
## (Hangar.mode(): "dock", "dead", "bay", "flying", "spooling", "offline"
## or "bay_launch").
##   - The Launch button shows while docked, waiting to respawn, or while
##     the mothership is out of action. It only works when docked ("dock")
##     or when a repair bay can stand in for the mothership ("bay_launch").
##   - With the Hyperspace Module, a docked pilot also gets one button per
##     working repair bay of ours: a hyperspace launch. The jump drive
##     "spools up" (charges) for World.HYPERSPACE_SPOOL seconds, then the
##     ship appears at that bay.
## A pilot with no ship chosen yet is given a free Scout when they launch.
## This is a "static library": plain functions with no state of their
## own. As a part of Hangar it reads the panel's fields directly.
##
## WHO USES IT: Hangar._refresh() (the three refresh functions),
## Hangar.launch() (forwards to launch()), and the bay buttons made here
## (launch_at()). The launches go through World.launch() and
## World.hyperspace_launch() (the real code is in WorldHangar).


## The status line under the title for hangar `h` in mode `m`: where the
## pilot is and what that allows, then two spaces and the loadout:
## "Next launch: <hull> with <modules>" (or "No ship chosen yet ..."),
## or "Flying: <hull>" while in flight.
static func status_text(h: Hangar, m: String) -> String:
	var p := h.profile
	# Step 1: the loadout for the next launch: the hull, then its modules.
	var loadout := "No ship chosen yet (Scouts are free)"
	if p.hull_id != "":
		loadout = "Next launch: %s" % Ships.HULLS[p.hull_id]["label"]
		if not p.modules.is_empty():
			var names: Array = []
			for mid: String in p.modules:
				names.append(Modules.MODULES[mid]["label"])
			loadout += " with " + ", ".join(names)
	# Step 2: where the pilot is (respawn and spool times in whole seconds,
	# rounded up).
	var where := ""
	match m:
		"dock":
			where = "Docked at the mothership."
		"dead":
			where = "Respawning in %ds; you can shop while you wait." % int(ceil(p.respawn_t))
		"bay":
			where = "Inside a repair bay's range: you can swap modules here."
		"flying":
			where = "In flight: dock at the mothership (F) to shop. Modules can also be swapped inside a repair bay's range."
		"offline":
			where = "The mothership is offline: no shopping or launches there right now."
		"bay_launch":
			where = "The mothership is offline: no shopping, but you can launch from one of our repair bays."
		"spooling":
			where = "Hyperspace drive spooling: jumping to the repair bay in %ds." % int(ceil(p.respawn_t))
	# Step 3: in flight, show the ship being flown instead.
	if m == "bay" or m == "flying":
		var s := p.ship
		if s != null and is_instance_valid(s):
			loadout = "Flying: %s" % Ships.HULLS[s.hull_id]["label"]
	return where + "  " + loadout


## Show, enable and label hangar `h`'s Launch button for mode `m` (see HOW
## IT WORKS). While waiting to respawn it counts down instead.
static func refresh_button(h: Hangar, m: String) -> void:
	# Step 1: shown at the mothership or during an outage; usable only
	# when docked or when a bay launch is possible.
	h._launch.visible = m == "dock" or m == "dead" or m == "offline" or m == "bay_launch"
	h._launch.disabled = m != "dock" and m != "bay_launch"
	# Buyback (BuybackFeature): a dead pilot's button buys the respawn.
	if m == "dead" and BuybackFeature.current() != null:
		h._launch.disabled = not BuybackFeature.can_buy(h.profile)
		h._launch.text = BuybackFeature.button_text(h.profile)
		return
	# Step 2: the button's text.
	if m == "bay_launch":
		h._launch.text = "Launch from a repair bay (F)"
	elif m == "dock":
		h._launch.text = "Launch (F)" if h.profile.hull_id != "" else "Launch a free Scout (F)"
	elif m == "dead":
		h._launch.text = "Respawn in %ds" % int(ceil(h.profile.respawn_t))
	else:
		h._launch.text = "Can't launch"


## Fill hangar `h`'s hyperspace row: when `enabled` (docked, with the
## Hyperspace Module), a "Hyperspace launch to:" label and one button per
## repair bay of ours that is alive and anchored (arrived and set up).
## The row is only rebuilt when the list of bays changed, so the buttons
## don't flicker 4 times a second.
static func refresh_bay_row(h: Hangar, enabled: bool) -> void:
	# Step 1: the bays to offer (none when not enabled), and their uids.
	var bays: Array = []
	if enabled:
		for b: RepairBay in h.world.bays:
			if b.team == h.profile.team and b.alive and b.is_anchored():
				bays.append(b)
	var ids: Array = []
	for b in bays:
		ids.append(b.uid)
	# Step 2: same bays as last time? Then keep the row as it is.
	if ids == h._bay_launch_ids:
		return
	h._bay_launch_ids = ids
	# Step 3: rebuild the row (queue_free deletes a node at the end of this
	# frame); it stays empty when there are no bays.
	for c in h._bay_row.get_children():
		c.queue_free()
	if bays.is_empty():
		return
	h._bay_row.add_child(UiKit.label("Hyperspace launch to:", 13, Palette.MIST))
	for b: RepairBay in bays:
		var bay := b
		h._bay_row.add_child(UiKit.button("Repair bay at %s" % Rules.display_label(h.world.place_name(b.global_position)), func() -> void: launch_at(h, bay), 30))


## Launch hangar `h`'s pilot (F or the Launch button). Only works when
## docked ("dock") or when a repair bay can stand in for the mothership
## ("bay_launch"). Without a ship chosen, the pilot first gets a Scout
## (free). On success the hangar closes; if World.launch() can't make
## the ship, a toast (a short message on screen) says so. Returns true on
## success.
static func launch(h: Hangar) -> bool:
	var m := h.mode()
	# Buyback (BuybackFeature): the button of a dead pilot buys the respawn.
	if m == "dead" and BuybackFeature.current() != null:
		var err := BuybackFeature.press(h.profile)
		if err != "":
			Events.toast.emit(err)
		else:
			Events.cue.emit("buy", Vector2.ZERO)
		return false
	if m != "dock" and m != "bay_launch":
		return false
	# Step 1: no ship chosen yet: take the free Scout.
	if h.profile.hull_id == "":
		h.profile.buy_hull("scout", h.world.teams[h.profile.team])
	# Step 2: launch, and close the hangar if it worked.
	var s := h.world.launch(h.profile)
	if s == null:
		Events.toast.emit("Can't launch right now.")
		return false
	h.closed.emit()
	return true


## A hyperspace launch of hangar `h`'s pilot to repair bay `bay` (one of
## the bay buttons). Only while docked ("dock"). Without a ship chosen,
## the pilot first gets a Scout (free). World.hyperspace_launch() starts
## the spool, or gives the reason it can't (shown as a toast); on success
## the hangar closes.
static func launch_at(h: Hangar, bay: RepairBay) -> void:
	if h.mode() != "dock":
		return
	if h.profile.hull_id == "":
		h.profile.buy_hull("scout", h.world.teams[h.profile.team])
	var err := h.world.hyperspace_launch(h.profile, bay)
	if err != "":
		Events.toast.emit(err)
	else:
		h.closed.emit()
