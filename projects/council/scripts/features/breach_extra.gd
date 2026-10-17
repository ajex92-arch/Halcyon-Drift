class_name BreachExtraFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "breach_extra" rule variant: an
## extra "super minion" for every free wave on a breached lane (docs/
## FUN_PLAN.md section 5, endgame_closure fork, idea B7). REQ-CHANGE: "wave
## of 10, with 5 fighters, 4 bombers, and 1 escort corvette" (a breached
## lane's wave has 11 units; the wave-composition gate is expected to fail
## under this key).
##
## HOW IT WORKS: the variant has one value besides "off" (the default):
##   "on"   while a lane is breached for a team (the last turret at an enemy
##          inner node died, see BreachTracker; the same rule as the "breach"
##          variant, which this module does not depend on), each free wave the
##          team launches on that lane carries an 11th unit, a super minion:
##          a copy of the escort corvette with hull 1,400 and shield 250 (base
##          values, before the usual strength growth) and escort cannons that
##          reach 20% farther. Its damage multipliers are the normal minion
##          ones. A breach lasts 8 waves.
## The super minion is made when the wave's first escort corvette launches:
## it appears next to the mothership's launch spots for that lane. The AI
## needs no special rule (it is a minion, so it walks and fights like any
## other). Each super minion is counted in Game.usage as "super_minions".
## The feed line, the HUD banner and the minimap chevron are the breach ones
## (BreachTracker). The module draws no random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=breach_extra:on and
## asks it for banner() and minimap_chevrons().

## The variant key this module belongs to.
const KEY := "breach_extra"
## Super minion hull (base value, before strength growth).
const HULL := 1400.0
## Super minion shield (base value).
const SHIELD := 250.0
## Reach multiplier of the escort cannon (1.2 = +20%).
const CANNON_RANGE := 1.2
## The meta tag set on every super minion.
const TAG := "super_minion"

## The breach notebook (shared helper).
var tracker: BreachTracker
## The world we belong to.
var world: World


## Switch the extra super minion on for match `w`. FeatureRegistry calls this
## once at match start. An unknown value only gets a warning.
func install(w: World) -> void:
	if Game.variant(KEY) != "on":
		push_warning("breach_extra: unknown value \"%s\" (use off or on); nothing changed" % Game.variant(KEY))
		return
	world = w
	tracker = BreachTracker.new(w)
	tracker.start()
	Events.minion_launched.connect(_on_minion_launched)


## A minion has launched with a free wave. If it is the first corvette of a
## wave on a lane that is breached for its team, add the super minion.
func _on_minion_launched(node: Node, wave_id: float) -> void:
	var m := node as Minion
	if m == null or m.mtype != "corvette" or not tracker.serve(m.team, m.lane, wave_id):
		return
	var ms := world.mothership(m.team)
	if ms == null or not ms.alive:
		return
	# Step 1: launch one more corvette from the spot matching its lane (the
	# director's own corvette used a random spot; we use a fixed one, so the
	# module draws no random number).
	var slot := MapLayout.LANE_ORDER.find(m.lane) + 1
	var s := world.spawn_minion(m.team, "corvette", m.lane, ms.launch_point(slot))
	# Step 2: make it a super minion.
	MinionBoost.tough_copy(s, HULL, SHIELD, "Super Minion", TAG)
	MinionBoost.longer_cannon(s, CANNON_RANGE)
	Game.count_usage("super_minions")


## The HUD banner for the human on `team` (see BreachTracker.banner()).
func banner(_w: World, team: int) -> Array:
	return tracker.banner(team)


## The minimap chevrons (see BreachTracker.marks()).
func minimap_chevrons(_w: World) -> Array:
	return tracker.marks()
