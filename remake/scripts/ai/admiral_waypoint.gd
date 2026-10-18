class_name AdmiralWaypoint
extends RefCounted
## WHAT THIS IS: the part of the AI admiral that places the team "waypoint".
## The waypoint is a rally marker on the map: our ships near it fly a bit
## faster, see further and recharge shields faster, and AI pilots gather
## there late in the match. It lasts Rules.WAYPOINT_TIME (75 s) once set.
##
## HOW IT WORKS: during a siege (an attack on the enemy mothership, see
## AdmiralSiege) the waypoint goes on the siege lane: first on the staging
## point where big ships meet, then just short of the enemy mothership.
## Otherwise it goes part-way down the lane we are pushing: 55% of the way,
## or 66% late in the match (after 20:00) once our wave is past 60% of the
## lane, so the rally is at the enemy's inner node (those sit at about 0.7
## of a lane).
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.waypoint) and its tick()
## calls place() when the waypoint timer runs out. The order goes through
## AdmiralCommand.set_waypoint(), like a human admiral's click, but with
## declare_siege = false: the AI declares its sieges itself (AdmiralSiege).

## The game world (for the match time and the AdmiralCommand).
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The admiral's lane helper (push lane, front, points along a lane).
var lanes: AdmiralLanes


## Remember the world, our team and the lane helper. AdmiralAI makes this
## part once.
func _init(w: World, t: int, l: AdmiralLanes) -> void:
	world = w
	team = t
	lanes = l


## Set the team waypoint for the next while (see the notes at the top).
## `ts` is our team's shared state.
func place(ts: TeamState) -> void:
	var cmd := world.command
	var lane := lanes.push_lane()
	if ts.siege_lane != "":
		# Siege: rally at the staging point, then just short of the enemy
		# mothership (use the point for the current phase). The last
		# argument, false, means "just move the marker": our sieges are run
		# by AdmiralSiege, so placing the marker must not start, change or
		# call off a siege.
		cmd.set_waypoint(team, ts.siege_assault_point(ts.siege_lane) if ts.siege_phase == "assault" else ts.siege_stage_point(ts.siege_lane), false)
	elif lane != "":
		# No siege: rally part-way down the lane we're pushing. Late on,
		# rally at the enemy's inner node once our wave is past the middle
		# (enemy inner nodes sit at about 0.7 of a lane).
		var frac := 0.55
		if world.time > 1200.0 and lanes.front_frac(lane) > 0.6:
			frac = 0.66
		# Again "just move the marker" (false). Bug fixed 2026-10-15: this
		# point can land within 6,000 of an enemy mothership that has moved
		# up the lane, and a human-style waypoint there declares an
		# "assault" siege. AdmiralSiege then called that accidental siege off
		# within a second and started its 60 s cooldown, over and over,
		# which blocked our real sieges.
		cmd.set_waypoint(team, lanes.lane_point(lane, frac), false)
