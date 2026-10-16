class_name BreachFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "breach" rule variant: the lane
## breach corvette (docs/FUN_PLAN.md section 5, endgame_closure fork, idea
## B2). When a team destroys the last turret at an enemy inner ore node, that
## lane is "breached" and, for the next 8 free minion waves (about 280 s),
## its single escort corvette launches as a much tougher "breach corvette"
## that soaks mothership and inner-turret fire so that a big-ship siege can
## land.
##
## HOW IT WORKS: the variant has three values (Rules.VARIANT_DEFAULTS):
##   "off"       the default, today's game. The module is not installed.
##   "on"        the breach corvette: a copy of the escort corvette with hull
##               960 (twice 480) and shield 320 (twice 160), and escort
##               cannons that reach 20% farther. No new gun. Its damage
##               multipliers are unchanged (x0.5 against a mothership, x0.35
##               against turrets, x0.6 against pilot ships). It stacks with
##               the escort_wing:upgrade variant (its +40% hull comes on top).
##               REQ-CHANGE: none.
##   "fulldmg"   everything in "on", plus full damage against a mothership
##               (x1.0 instead of x0.5, through Combat.minion_scale_hook) and
##               a siege shell as its first gun: 1,700 world units of reach,
##               70 damage every 2 s (x1.5 against a mothership from the
##               damage table). REQ-CHANGE: "weak to attacks by large ships"
##               (minions could close a game).
## The breach itself is tracked by BreachTracker (shared with the
## breach_extra module): the last inner-node turret dies, the lane is breached
## for the attacker. The feed message, the HUD banner and the minimap chevron
## are shown to both teams. The AI needs no special rule: the corvette is a
## minion, so it walks its lane and fights as minions always do; the AI
## admiral's siege (and the pilots) get the cover. Each breach corvette made
## is counted in Game.usage as "breach_waves". The module draws no random
## numbers and does not touch the turret rebuild lock.
##
## WHO USES IT: FeatureRegistry installs it for --variant=breach:on or
## breach:fulldmg, and asks it for banner() and minimap_marks().

## The variant key this module belongs to.
const KEY := "breach"
## Breach corvette hull (base value, twice the normal escort corvette's 480).
const HULL := 960.0
## Breach corvette shield (base value, twice the normal 160).
const SHIELD := 320.0
## Reach multiplier of the escort cannon (1.2 = +20%).
const CANNON_RANGE := 1.2
## The meta tag set on every breach corvette.
const TAG := "breach_corvette"
## How much more a "fulldmg" breach corvette's hits hurt a mothership: the
## normal x0.5 minion rule (Rules.MOTHERSHIP_MINION_MULT) becomes x1.0.
const FULL_MOTHERSHIP_FACTOR := 2.0

## The breach notebook (shared helper).
var tracker: BreachTracker
## True for "fulldmg".
var full := false
## The world we belong to.
var world: World
## The minion_scale_hook that was set before ours (usually empty); ours calls
## it for hits that are not ours.
var _prev_hook := Callable()


## Switch breach corvettes on for match `w`. FeatureRegistry calls this once
## at match start. An unknown value only gets a warning.
func install(w: World) -> void:
	var value := Game.variant(KEY)
	if value != "on" and value != "fulldmg":
		push_warning("breach: unknown value \"%s\" (use off, on or fulldmg); nothing changed" % value)
		return
	world = w
	full = value == "fulldmg"
	# Step 1: watch for breaches and for launching waves.
	tracker = BreachTracker.new(w)
	tracker.start()
	Events.minion_launched.connect(_on_minion_launched)
	# Step 2: "fulldmg" lets these corvettes hurt a mothership at full strength.
	if full:
		_prev_hook = w.combat.minion_scale_hook
		w.combat.minion_scale_hook = _scale_hook


## A minion has launched with a free wave. If it is the first corvette of a
## wave on a lane that is breached for its team, turn it into a breach
## corvette.
func _on_minion_launched(node: Node, wave_id: float) -> void:
	var m := node as Minion
	if m == null or m.mtype != "corvette" or not tracker.serve(m.team, m.lane, wave_id):
		return
	# Step 1: the tougher corvette with the longer cannon.
	MinionBoost.tough_copy(m, HULL, SHIELD, "Breach Corvette", TAG)
	MinionBoost.longer_cannon(m, CANNON_RANGE)
	# Step 2: "fulldmg" also gets the siege shell.
	if full:
		MinionBoost.add_siege_shell(m)
	Game.count_usage("breach_waves")


## Combat.minion_scale_hook for "fulldmg": a breach corvette's hit on a
## mothership counts double (x0.5 becomes x1.0); every other hit keeps its
## strength `scale` (or is passed to the hook that was there before).
func _scale_hook(m: Minion, target: Unit, scale: float) -> float:
	if target.kind == Unit.K_MOTHERSHIP and m.has_meta(TAG):
		return scale * FULL_MOTHERSHIP_FACTOR
	if _prev_hook.is_valid():
		return float(_prev_hook.call(m, target, scale))
	return scale


## The HUD banner for the human on `team` (see BreachTracker.banner()).
func banner(_w: World, team: int) -> Array:
	return tracker.banner(team)


## The minimap chevrons (see BreachTracker.marks()).
func minimap_marks(_w: World) -> Array:
	return tracker.marks()
