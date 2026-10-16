class_name AdmiralPlan
extends RefCounted
## WHAT THIS IS: the AI admiral's shopping list for the tech tree. It says
## which modules to build onto our mothership ("facilities") and which
## upgrades to research, and in what order.
##
## HOW IT WORKS: PLAN is a fixed list of steps. Once a second the AI admiral
## asks next_step() for the first step it could start right now. Steps that
## are finished, or already being built or researched, are skipped. A step
## that has to wait (it needs something else first, or the build or
## research queue is full) may be jumped over, but only a few steps ahead
## (LOOKAHEAD), so the list mostly keeps its order.
##
## WHO USES IT: AdmiralAI.tick() calls AdmiralPlan.next_step(), then pays
## for the step with AdmiralCommand.build_facility() or
## AdmiralCommand.research(). The ids and prices come from Tech.FACILITIES
## and Tech.TECHS (scripts/data/tech.gd). TeamState (scripts/team/
## team_state.gd) says what is done, under way, or blocked.
##
## This is a "static library": it keeps nothing of its own between calls,
## so you call it on the class name (AdmiralPlan.next_step(ts)) instead of
## making an object first.

## The build order. Each step is [kind, id]:
##   "f" = a facility, a module built onto our mothership (Tech.FACILITIES),
##   "t" = a tech, a research upgrade (Tech.TECHS).
## The steps are taken from top to bottom. The Fleet Command Module ("fleet")
## is left out on purpose (see AdmiralFleetCommand for why).
const PLAN := [
	["f", "research"], ["t", "fusionBombs"], ["t", "repairBays"], ["t", "corvetteChassis"],
	["f", "platform"], ["f", "corvette"], ["t", "platformMissiles"], ["t", "lanceBeams"],
	["t", "fighterDrive1"], ["t", "commandSystems"], ["t", "repairDrones2"], ["t", "frigateChassis"],
	["f", "frigate"], ["t", "improvedBombs"], ["t", "droneArmor1"], ["t", "msHull1"], ["t", "ionCannons"],
	["t", "bayDefenses"], ["f", "sensors"], ["t", "platformArmor1"], ["t", "corvetteArmor1"],
	["t", "frigateArmor1"], ["t", "repairDrones3"], ["f", "capital"], ["t", "destroyerChassis"],
	["t", "msShield1"], ["t", "msPd2"], ["t", "pilotStipend"], ["t", "fireControl"], ["t", "msFlak"],
	["t", "frigateDrive1"], ["t", "msHeavy1"], ["t", "capitalArmor1"], ["t", "repairDrones4"],
	["t", "battlecruiserChassis"], ["t", "waveArmor1"], ["t", "msHull2"], ["t", "msHeavy2"], ["t", "escortWing"],
	["t", "capitalDrive1"], ["t", "waveArmor2"], ["t", "msShield2"], ["t", "msIon"], ["t", "waveArmor3"],
	["t", "msHull3"], ["f", "hyperspace"],
]

## How many unfinished steps next_step() may look at (a count of steps).
## A blocked step can be skipped, but only up to this many unfinished steps
## from the first one, so the plan's order holds. (Playtest: without this
## limit it jumped straight to the Hyperspace Module while frigates were
## still locked.)
const LOOKAHEAD := 4


## The next PLAN step we could start right now, ignoring the price. Returns
## {"kind": "f" or "t", "id": the facility or tech id, "cost": its price in
## credits}, or {} (an empty dictionary) when there is nothing to start.
## `ts` is our team's shared state: money, what is built and researched.
static func next_step(ts: TeamState) -> Dictionary:
	# How many unfinished steps we have looked at so far.
	var pending := 0
	# A feature may give the team its own order (TeamState.plan_override).
	var plan: Array = PLAN if ts.plan_override.is_empty() else ts.plan_override
	for s: Array in plan:
		var kind: String = s[0]
		var id: String = s[1]
		# Step 1: skip steps that are finished or already under way.
		if kind == "f":
			if ts.facilities.has(id) or ts.is_building(id):
				continue
		elif ts.done.has(id) or ts.is_researching(id):
			continue
		# Step 2: this one still needs doing. Past LOOKAHEAD of these we stop
		# looking, so a far-later step never jumps the queue.
		pending += 1
		if pending > LOOKAHEAD:
			return {}
		# Step 3: a facility. Take it if nothing blocks it (it has its
		# prerequisites and the build queue has room).
		if kind == "f":
			if ts.facility_blocker(id) != "":
				continue
			return {"kind": "f", "id": id, "cost": float(Tech.FACILITIES[id]["cost"])}
		# Step 4: a tech. Same idea with the research queue.
		if ts.tech_blocker(id) != "":
			continue
		return {"kind": "t", "id": id, "cost": float(Tech.TECHS[id]["cost"])}
	return {}
