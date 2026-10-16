class_name AdmiralMothershipMover
extends RefCounted
## WHAT THIS IS: the part of the AI admiral that moves our mothership (the
## huge home ship that is our base) around the map late in the match.
##
## HOW IT WORKS: motherships can only move from 20:00
## (Rules.MOTHERSHIP_MOVE_UNLOCK, 1200 s; Rules.move_unlock_time()). Each
## admiral think it decides:
##   - Hurt (under half hull) and away from home: fly back home.
##   - Hurt, or our base is under attack: otherwise stay where it is.
##   - Otherwise, when our fleet is at least as strong as theirs, go 35% of
##     the way up the mid lane (ADVANCE_LANE, ADVANCE_FRAC). It is always the
##     mid lane, also during a siege. (If each admiral follows its own push
##     lane, or the lane the other mothership is on, the two motherships
##     park on different lanes, top against bottom some 30,000 units apart,
##     and chase each other from lane to lane: no siege meets anything and
##     no match ends. On the shortest lane they meet.)
##     (DESIGN.md C19 also tested "only during a siege" and "never"; the
##     "advance" rule ended the most matches.)
## No new order is given while the last move is still under way. Apart from
## the fall-back when hurt, a new move order comes at most once every
## 2 minutes (120 s, MOVE_GAP). ADVANCE_FRAC and MOVE_GAP are tuned
## numbers: a feature module may change them for one match
## ("mothership_advance_frac", "mothership_move_gap"; see Rules.tune).
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.mothership_mover) and its
## tick() calls maybe_move(), but only after 20:00. The order goes through
## AdmiralCommand.move_mothership(), which also checks the rules. The siege
## plan (AdmiralSiege) follows the enemy mothership to the lane it is parked
## on, which is therefore the mid lane.

## The lane our mothership always advances up (see HOW IT WORKS). Mid is
## the shortest lane (33,600 units against 44,200 for top and bottom), so a
## fleet and the enemy mothership meet soonest there.
const ADVANCE_LANE := "mid"
## How far up the mid lane the mothership advances, as a fraction of the
## lane's length from our end (0.35 = 35%; tuned "mothership_advance_frac").
const ADVANCE_FRAC := 0.35
## The fewest seconds between two "advance" move orders (tuned
## "mothership_move_gap").
const MOVE_GAP := 120.0

## The game world (motherships, teams, the map, match time).
var world: World
## Our team: 0 = Halcyon, 1 = Cinder.
var team := 0
## The admiral's lane helper (fleet strength, lane points).
var lanes: AdmiralLanes
## Match time (seconds) of our last "advance" move order (not counting the
## fall-back when hurt). Starts far in the past (-999) so the first move
## can happen at once.
var last_move_t := -999.0


## Remember the world, our team and the lane helper. AdmiralAI makes this
## part once.
func _init(w: World, t: int, l: AdmiralLanes) -> void:
	world = w
	team = t
	lanes = l


## Decide whether to move our mothership now, and order the move if so.
## (See the notes at the top for the rules.)
func maybe_move() -> void:
	# Step 1: no mothership, or it is still flying to its last target
	# (move_target is "INF", meaning "none", when it isn't moving).
	var ms := world.mothership(team)
	if ms == null or ms.move_target != Vector2.INF:
		return
	var ts := world.teams[team]
	# Step 2: under attack or badly hurt: fall back to the home position
	# (where it started the match).
	var home: Vector2 = world.map.mothership_pos[team]
	if ms.hull_frac() < 0.5 or ts.defending(world.time):
		if ms.global_position.distance_to(home) > 2000.0 and ms.hull_frac() < 0.5:
			world.command.move_mothership(team, home)
		return
	# Step 3: advance up the mid lane (ADVANCE_LANE) when we're at least
	# even, whatever lane we are pushing or sieging. That means shorter trips
	# for respawned pilots, its guns join the fights, and sieges reach the
	# enemy before their defenders respawn. (Playtest: with both motherships
	# at home, 50-minute matches never ended. And when the lane followed the
	# push or siege lane, it hopped lanes as that flickered, and pilots
	# flying home chased it across the map for minutes.)
	if lanes.fleet_power(team) < lanes.fleet_power(1 - team):
		return
	# Step 4: the spot 35% up that lane (ADVANCE_FRAC). Go if it is over
	# 2,500 away, at most one new move every 2 minutes (MOVE_GAP).
	var p := lanes.lane_point(ADVANCE_LANE, float(Rules.tune("mothership_advance_frac", ADVANCE_FRAC)))
	if ms.global_position.distance_to(p) > 2500.0 and world.time - last_move_t > float(Rules.tune("mothership_move_gap", MOVE_GAP)):
		last_move_t = world.time
		world.command.move_mothership(team, p)
