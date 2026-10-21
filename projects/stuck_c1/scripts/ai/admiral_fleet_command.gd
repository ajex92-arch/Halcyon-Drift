class_name AdmiralFleetCommand
extends RefCounted
## WHAT THIS IS: what the AI admiral does when our team owns the Fleet
## Command Module. With that module the free minion waves stop, and the
## admiral must buy minions (small computer-flown lane ships) with team
## money instead.
##
## HOW IT WORKS: once a second it buys up to 4 minions, in the FLEET_MIX
## order, while we have fewer than Minions.control_cap() alive (30 unless
## the fleet_cap variant changes it) and can pay with 300 credits to spare. They are sent down the lane we are
## pushing (or, when no lane is being pushed, a lane that changes every
## minute).
##
## The AI's own build PLAN (AdmiralPlan) never builds Fleet Command: in
## AI-vs-AI matches it cut each side to 30 bought minions, starved the late
## pushes and stalled the game (playtest 2026-10-14). A human admiral can
## still choose it, and this part still runs whenever an AI-run team has
## the module anyway.
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.fleet) and its tick() calls
## run(), only when MinionDirector.controlled() says our team has the
## module. Purchases go through AdmiralCommand.buy_minion().

## The order we buy minion types in, repeating: roughly the mix of a free
## wave (fighters, bombers and an escort corvette). Ids are keys of
## Minions.TYPES.
const FLEET_MIX := ["fighter", "fighter", "bomber", "fighter", "bomber", "corvette"]

## The game world (minions, the MinionDirector, the AdmiralCommand).
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The admiral's lane helper (for the lane we're pushing).
var lanes: AdmiralLanes
## How many minions we have bought so far (a count). It picks the next
## type from FLEET_MIX, so the mix carries on where it left off.
var next_i := 0


## Remember the world, our team and the lane helper. AdmiralAI makes this
## part once.
func _init(w: World, t: int, l: AdmiralLanes) -> void:
	world = w
	team = t
	lanes = l


## Keep the minion count up: buy up to 4 minions this second, from the
## treasury, and send them down a lane. `ts` is our team's shared state.
func run(ts: TeamState) -> void:
	var md := world.minion_director
	# Step 1: the lane to send them down. No push yet: rotate top, mid,
	# bot, changing every 60 s of match time.
	var lane := lanes.push_lane()
	if lane == "":
		lane = MapLayout.LANE_ORDER[int(world.time / 60.0) % 3]
	# Step 2: buy one at a time until we hit the cap, bought 4, run short
	# of money, or a purchase fails.
	var bought := 0
	var cap := Minions.control_cap()
	while md.alive_count(team) < cap and bought < 4:
		var type_id: String = FLEET_MIX[next_i % FLEET_MIX.size()]
		if not ts.can_afford(float(Minions.TYPES[type_id]["buy_cost"]) + 300.0):
			break
		if world.command.buy_minion(team, type_id, lane) != "":
			break
		next_i += 1
		bought += 1
