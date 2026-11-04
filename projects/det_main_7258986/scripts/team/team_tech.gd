class_name TeamTech
extends RefCounted
## WHAT THIS IS: the tech-tree part of a team (TeamState). It decides
## whether a facility or a research project may be queued, pays for it,
## moves the queues on each tick, and turns finished research into the
## team's upgrades. DESIGN.md A13.
##
## HOW IT WORKS: the tech-tree data lives in Tech (scripts/data/tech.gd).
## There are two kinds of tech:
##   facilities  modules built onto the mothership (Research Module,
##               Frigate Facility ...). They unlock ships and research.
##               At most 2 are queued; only the first one is being built.
##   research    upgrades such as "Improved Bombs". At most 3 are queued;
##               only the first one makes progress, and only while the
##               team owns the Research Module.
## Queuing pays the full price at once from the team treasury. Each tick
## the first entry of each queue counts its seconds down. When one
## finishes, it is written down (TeamState.facilities or TeamState.done,
## and the time in unlock_times) and announced on Events (the game's
## message board: facility_done or research_done). Finished research also
## adds its "effect" to the team's upgrade fields (apply_effect), refits
## the mothership (Mothership.apply_upgrades) and updates units already in
## space (World.on_research_done).
##
## WHO USES IT: TeamState makes one (TeamState.tech), runs tick() and
## forwards its tech functions here, so other files keep calling them on
## TeamState: AdmiralCommand queues facilities and research; the AI
## admiral's plan (AdmiralPlan) and the admiral board ask the blockers;
## the hangar screen, PilotShopping, PilotProfileShop.buy_hull and the HUD
## feed ask ship_unlocked(); ShipStats reads drive_level() and
## armor_level(); tests call apply_effect() to research everything at once.

## The team this part belongs to (we read and change its fields). It is
## reached through a weak link: see `_ts_ref`.
var ts: TeamState:
	get:
		return _ts_ref.get_ref() as TeamState

## A "weak" link to the team. TeamState holds this part with a normal
## (strong) link. If the part held the team strongly too, each would keep
## the other alive forever and Godot could never free them (a memory
## leak). A weak link points at the team without keeping it alive.
var _ts_ref: WeakRef


## Remember our team (through a weak link). TeamState makes this part once.
func _init(owner: TeamState) -> void:
	_ts_ref = weakref(owner)


# --- questions about the queues --------------------------------------------------

## All research we have finished or queued: tech id -> true. Tech's rules
## use it, so a chain (Drive 1, then Drive 2) can be queued in one go.
func planned_tech() -> Dictionary:
	var out := ts.done.duplicate()
	for r: Dictionary in ts.research:
		out[r["id"]] = true
	return out


## Is facility `id` in the build queue?
func is_building(id: String) -> bool:
	for b: Dictionary in ts.building:
		if b["id"] == id:
			return true
	return false


## Is research `id` in the research queue?
func is_researching(id: String) -> bool:
	for r: Dictionary in ts.research:
		if r["id"] == id:
			return true
	return false


## Why facility `id` can't be queued now, or "" if it can. The cost is
## not checked here. The reasons, checked in this order: we own it or are
## building it already; Tech's rules say no (a facility or research it
## needs is missing); the build queue already holds 2.
func facility_blocker(id: String) -> String:
	# Rule 1: never twice.
	if ts.facilities.has(id) or is_building(id):
		return "Already built or being built"
	# Rule 2: everything it needs must be there (Tech.facility_blocker).
	var b := Tech.facility_blocker(id, ts.facilities, ts.done)
	if b != "":
		return b
	# Rule 3: room in the build queue.
	if ts.building.size() >= 2:
		return "Build queue is full (2 at a time)"
	return ""


## Why research `id` can't be queued now, or "" if it can. The cost is not
## checked here. The reasons, checked in this order: finished or queued
## already; Tech's rules say no (it needs the Research Module, the
## facility of its column, and its earlier research finished or queued);
## the research queue already holds 3.
func tech_blocker(id: String) -> String:
	# Rule 1: never twice.
	if ts.done.has(id) or is_researching(id):
		return "Already researched or queued"
	# Rule 2: everything it needs (Tech.tech_blocker).
	var b := Tech.tech_blocker(id, ts.facilities, planned_tech())
	if b != "":
		return b
	# Rule 3: room in the research queue.
	if ts.research.size() >= 3:
		return "Research queue is full (3 at a time)"
	return ""


# --- queuing (paying up front) ----------------------------------------------------

## Queue facility `id`: check the rules (facility_blocker), pay its cost
## from the treasury, and add it to the end of the build queue. Returns ""
## when it worked, or why not (nothing is paid then).
func queue_facility(id: String) -> String:
	# Step 1: may it be queued at all?
	var b := facility_blocker(id)
	if b != "":
		return b
	# Step 2: pay for it (TeamState.spend says no if we are short).
	var cost: float = float(Tech.FACILITIES[id]["cost"])
	if not ts.spend(cost):
		return "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury))
	# Step 3: join the queue with its whole build time still to go.
	var time: float = float(Tech.FACILITIES[id]["time"])
	ts.building.append({"id": id, "left": time, "total": time})
	return ""


## Queue research `id`: check the rules (tech_blocker), pay its cost from
## the treasury, and add it to the end of the research queue. Returns ""
## when it worked, or why not (nothing is paid then).
func queue_research(id: String) -> String:
	# Step 1: may it be queued at all?
	var b := tech_blocker(id)
	if b != "":
		return b
	# Step 2: pay for it.
	var cost: float = float(Tech.TECHS[id]["cost"])
	if not ts.spend(cost):
		return "Not enough in the team treasury (%d short)" % int(ceil(cost - ts.treasury))
	# Step 3: join the queue with its whole research time still to go.
	var time: float = float(Tech.TECHS[id]["time"])
	ts.research.append({"id": id, "left": time, "total": time})
	return ""


# --- what the tech gives us --------------------------------------------------------

## May our pilots buy hull `ship_id`? Tech.ship_unlocked() checks our
## facilities and finished research.
func ship_unlocked(ship_id: String) -> bool:
	return Tech.ship_unlocked(ship_id, ts.facilities, ts.done)


## Every hull our pilots may buy, in Ships.ORDER order.
func unlocked_ships() -> Array:
	var out: Array = []
	for id: String in Ships.ORDER:
		if ship_unlocked(id):
			out.append(id)
	return out


## How many Drive upgrades we have researched for ship tier `tier`
## ("small", "medium", "large" or "capital"); 0 if none.
func drive_level(tier: String) -> int:
	return int(ts.drive.get(tier, 0))


## How many Armor upgrades we have researched for ship tier `tier`; 0 if
## none.
func armor_level(tier: String) -> int:
	return int(ts.armor.get(tier, 0))


## Add one research `effect` to our upgrade fields on TeamState. `effect`
## is the "effect" dictionary of a Tech.TECHS entry, such as
## {"torp_dmg": 0.25} or {"drive": "small"}. Bonuses add up (two +40%
## drone armour researches give +80%), switches turn on, counts go up.
## Keys not listed here, such as "unlock_ship", are ignored: a ship unlock
## needs no field, because ship_unlocked() reads the finished research.
func apply_effect(effect: Dictionary) -> void:
	for k: String in effect:
		var v = effect[k]
		match k:
			# Ship upgrades: one more level for that tier, or a bonus.
			"drive":
				ts.drive[v] = int(ts.drive[v]) + 1
			"armor":
				ts.armor[v] = int(ts.armor[v]) + 1
			"torp_dmg":
				ts.torp_dmg += float(v)
			"scout_emp":
				ts.scout_emp = true
			# Repair bays.
			"repair_bays":
				ts.repair_bays = true
			"bay_drones":
				ts.bay_drones += int(v)
			"bay_defenses":
				ts.bay_defenses = true
			# Mining drones and pilot pay.
			"drone_armor":
				ts.drone_armor += float(v)
			"mining_capacity":
				ts.mining_capacity += float(v)
			"stipend":
				ts.stipend += float(v)
			# Turrets, range and wards.
			"turret_torp":
				ts.turret_torp = true
			"turret_armor":
				ts.turret_armor += float(v)
			"team_range":
				ts.team_range += float(v)
			"ward_upgrade":
				ts.ward_upgrade = true
			# The mothership: hull, shields and extra guns.
			"ms_hull":
				ts.ms_hull += float(v)
			"ms_shield":
				ts.ms_shield += float(v)
			"ms_pd":
				ts.ms_pd += int(v)
			"ms_flak":
				ts.ms_flak += int(v)
			"ms_heavy":
				ts.ms_heavy += int(v)
			"ms_ion":
				ts.ms_ion += int(v)
			# Minion waves.
			"minion_buff":
				ts.minion_buff += float(v)
			"wave_corvette":
				ts.wave_corvettes += int(v)


# --- progress ------------------------------------------------------------------------

## Move the queues on by one tick of `dt` seconds. `ms` is our mothership:
## TeamState.tick() only calls this while it is alive.
func tick(dt: float, ms: Mothership) -> void:
	# Step 1: the first facility in the build queue counts down.
	if not ts.building.is_empty():
		var head: Dictionary = ts.building[0]
		head["left"] = float(head["left"]) - dt
		# Finished: we own it now. Write down when, and announce it.
		if float(head["left"]) <= 0.0:
			ts.building.pop_front()
			ts.facilities[head["id"]] = true
			ts.unlock_times[head["id"]] = ts.world.time
			Events.facility_done.emit(ts.team, head["id"])
	# Step 2: the first research counts down, but only while we own the
	# Research Module (facility "research").
	if not ts.research.is_empty() and ts.facilities.has("research"):
		var r: Dictionary = ts.research[0]
		r["left"] = float(r["left"]) - dt
		if float(r["left"]) <= 0.0:
			# Finished: write it down.
			ts.research.pop_front()
			var id: String = r["id"]
			ts.done[id] = true
			ts.unlock_times[id] = ts.world.time
			# Make it real: add the bonus, refit the mothership, update the
			# units already out in space, then announce it.
			apply_effect(Tech.TECHS[id]["effect"])
			ms.apply_upgrades(ts)
			ts.world.on_research_done(ts.team, id)
			Events.research_done.emit(ts.team, id)
