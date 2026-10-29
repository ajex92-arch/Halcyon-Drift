class_name LanespawnFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "lanespawn" rule variant: late
## minions launch from the lane ends (docs/FUN_PLAN.md section 5,
## endgame_closure fork, an optional carry-over from docs/AI_DEEP_DIVE.md
## section 5 item 2). REQ-CHANGE: minions "spawn from the mothership
## regularly" (and DESIGN.md says launches follow the moved mothership).
##
## HOW IT WORKS: the variant has one value besides "off" (the default):
##   "on"   from the time a mothership has moved away from its home spot
##          (more than 1,000 world units, from about 21:00), each free-wave
##          minion of that team launches at the HOME launch point, where all
##          three lanes start (the bow of the mothership as it stood at the
##          start, with the same sideways spot), not beside the moved
##          mothership. Without it the two lanes the mothership is not on get
##          their waves late and from the side, so late "lane waves" are
##          really "mothership waves" (in the deep dive, turret damage from
##          minions fell from 45k to 3k with this on and the match ran its
##          full length).
## MinionDirector sends Events.minion_launched for each free-wave minion; this
## module moves the new minion to the home spot, faces it like the home
## mothership and asks it to plan its lane path again (Minion.set_lane). The
## AI needs no rule: the minions are the same, they only start elsewhere. A
## wave of a team that is moved counts once in Game.usage as
## "lanespawn_waves". The module draws no random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=lanespawn:on.

## The variant key this module belongs to.
const KEY := "lanespawn"
## The mothership must be this far (world units) from its home spot before
## minions are moved.
const MOVED_DIST := 1000.0

## The world we belong to.
var world: World
## The last wave id counted for each team (so a wave counts once).
var _counted := [-1.0, -1.0]


## Switch late lane launches on for match `w`. FeatureRegistry calls this
## once at match start. An unknown value only gets a warning.
func install(w: World) -> void:
	if Game.variant(KEY) != "on":
		push_warning("lanespawn: unknown value \"%s\" (use off or on); nothing changed" % Game.variant(KEY))
		return
	world = w
	Events.minion_launched.connect(_on_minion_launched)


## A free-wave minion has launched: if its mothership is away from home,
## move it to the home launch point (see the header).
func _on_minion_launched(node: Node, wave_id: float) -> void:
	var m := node as Minion
	if m == null:
		return
	var ms := world.mothership(m.team)
	var home: Vector2 = world.map.mothership_pos[m.team]
	if ms == null or not ms.alive or ms.global_position.distance_to(home) < MOVED_DIST:
		return
	# Step 1: the sideways spot the director picked (one of 5, 90 apart),
	# read back from where the minion stands now.
	var bow := ms.half_len + ms.beam * 0.5 + 160.0
	var base_now := ms.global_position + Vector2.from_angle(ms.rotation) * bow
	var lateral := (m.global_position - base_now).dot(Util.starboard_of(ms.rotation))
	# Step 2: the same spot at the home mothership.
	var facing: float = world.map.mothership_facing[m.team]
	var base_home := home + Vector2.from_angle(facing) * bow
	m.position = base_home + Util.starboard_of(facing) * lateral
	m.rotation = facing
	# Step 3: plan the lane path again from the new spot.
	m.set_lane(m.lane)
	if float(_counted[m.team]) != wave_id:
		_counted[m.team] = wave_id
		Game.count_usage("lanespawn_waves")
