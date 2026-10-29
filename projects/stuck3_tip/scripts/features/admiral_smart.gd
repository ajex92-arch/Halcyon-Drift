class_name AdmiralSmartFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "admiral_smart" rule variant
## (fork admiral_command, idea F4 "Reactive AI admiral and fleet-composition
## calls"). It makes the COMPUTER admiral read the enemy fleet it has seen
## and react: its build plan reorders, and every minute it makes a
## "composition call" that changes what the AI pilots of its team buy. It is
## AI-only: a human admiral can still research and build everything, and
## nothing here changes what a human is allowed to do.
##
## HOW IT WORKS: the module keeps, for each team with a computer admiral, a
## memory of the enemy pilot ships that team has SEEN (visible to it) in the
## last 90 s (SEEN_MEMORY), counted every second. From that memory:
##   - The BUILD PLAN (AdmiralPlan.PLAN) is handed out in a new order through
##     TeamState.plan_hook: Reinforced Waves I-III and Escort Wing are left
##     out (their money goes to the rest of the plan), and
##       * with 3 or more enemy big ships (frigates and capital ships) seen,
##         Platform Missiles and Ion Cannons move to the front (Platform
##         Missiles also unlocks the torpedo turrets the AI builds);
##       * with 8 or more enemy strike craft (small pilot ships) seen, the
##         Flak Batteries (msFlak) research and the Frigate Facility move to
##         the front.
##     A step moves forward only when it could start right now (its
##     prerequisites are met and the queue has room), so a step that is
##     still blocked never eats the plan's short look-ahead.
##   - The COMPOSITION CALL (TeamState.comp_call) is set every 60 s: with 3+
##     big ships seen "anti_capital", else with 8+ strike craft "anti_strike",
##     else "" (no call). PilotShopping.wish_list() reads it through
##     wish_list() below: anti_capital sends the strikers and the lancer
##     toward bombers and lances and one dogfighter (seat 8) to a bomber;
##     anti_strike sends the dogfighters to the flak frigate from 15:00
##     (today they go at 20:00).
## Hyperspace timing is untouched. The module reads no other fork's variant,
## draws no random numbers and has no skill threshold.
## Usage counters: comp_calls (a new non-empty call was made) and
## plan_reorders (a team's plan was reordered: once when the skips start and
## once for every new set of steps moved forward).
##
## WHO USES IT: FeatureRegistry installs it for --variant=admiral_smart:on.
## AdmiralPlan.next_step() calls the plan hook; PilotShopping.wish_list()
## calls wish_list().

## The variant key this module belongs to.
const KEY := "admiral_smart"
## Plan steps the smart admiral skips (Reinforced Waves I-III, Escort Wing).
const SKIPPED := ["waveArmor1", "waveArmor2", "waveArmor3", "escortWing"]
## Steps that move forward against big enemy ships: [kind, id].
const AGAINST_BIG := [["t", "platformMissiles"], ["t", "ionCannons"]]
## Steps that move forward against many enemy strike craft: [kind, id].
const AGAINST_STRIKE := [["t", "msFlak"], ["f", "frigate"]]
## Enemy big ships (frigates and capital ships) seen that count as a threat.
const BIG_MIN := 3
## Enemy strike craft (small pilot ships) seen that count as a swarm.
const STRIKE_MIN := 8
## Seconds between two composition calls.
const CALL_EVERY := 60.0
## How long (seconds) an enemy ship counts after we last saw it.
const SEEN_MEMORY := 90.0
## Match time (seconds) from which "anti_strike" sends dogfighters to flak
## frigates (15:00).
const FLAK_FROM := 900.0

## The match this module runs in.
var world: World
## Per team: the enemy ships that team has seen: Ship -> match time seen last.
var seen: Array = [{}, {}]
## Seconds until the next once-a-second look at what the teams see.
var _look_t := 0.0
## Seconds until each team's next composition call.
var _call_t: Array = [CALL_EVERY, CALL_EVERY]
## Per team: the last set of steps moved forward (text), to count changes.
var _forward_key: Array = ["", ""]
## Per team: true once the "skips" reorder has been counted.
var _skip_counted: Array = [false, false]


## Plug the smart admiral into match `w` (FeatureRegistry calls this once).
func install(w: World) -> void:
	world = w
	# Only teams with a computer admiral get the new plan and calls.
	for t in 2:
		if AdmiralWeak.ai_acts(world, t):
			world.teams[t].plan_hook = _plan
	world.tick_hooks.append(_tick)


## Every tick (a World.tick_hooks entry): once a second remember the enemy
## ships each team sees, and every CALL_EVERY seconds make the calls.
func _tick(dt: float) -> void:
	_look_t -= dt
	if _look_t > 0.0:
		return
	_look_t = 1.0
	for t in 2:
		if not AdmiralWeak.ai_acts(world, t):
			continue
		# Step 1: remember the enemy pilot ships this team sees right now,
		# and forget the old ones.
		var mem: Dictionary = seen[t]
		for s: Ship in world.ships:
			if s.team == 1 - t and s.alive and s.visible_to(t):
				mem[s] = world.time
		for s in mem.keys():
			if not is_instance_valid(s) or not (s as Ship).alive or world.time - float(mem[s]) > SEEN_MEMORY:
				mem.erase(s)
		# Step 2: the composition call, once every CALL_EVERY seconds.
		_call_t[t] = float(_call_t[t]) - 1.0
		if float(_call_t[t]) <= 0.0:
			_call_t[t] = CALL_EVERY
			_make_call(t)


## How many big ships and strike craft team `t` has seen lately: a
## Dictionary {"big": n, "strike": n}.
func counts(t: int) -> Dictionary:
	var big := 0
	var strike := 0
	for k in (seen[t] as Dictionary).keys():
		# A ship that died since the last look may already be freed.
		if not is_instance_valid(k) or not (k as Ship).alive:
			continue
		var s := k as Ship
		if s.size_class >= Rules.SIZE_LARGE:
			big += 1
		elif s.size_class == Rules.SIZE_SMALL:
			strike += 1
	return {"big": big, "strike": strike}


## Set team `t`'s composition call from what it has seen (see HOW IT WORKS)
## and tell its own side when a new call is made.
func _make_call(t: int) -> void:
	var c := counts(t)
	var call := ""
	if int(c["big"]) >= BIG_MIN:
		call = "anti_capital"
	elif int(c["strike"]) >= STRIKE_MIN:
		call = "anti_strike"
	var ts := world.teams[t]
	if call != ts.comp_call:
		ts.comp_call = call
		if call != "":
			Game.count_usage("comp_calls")
			Events.feed.emit("The %s admiral calls for %s loadouts." % [Rules.TEAM_NAMES[t], "anti-capital" if call == "anti_capital" else "anti-strike"], "team", t)


## The plan hook (TeamState.plan_hook): the plan `plan` in this team's new
## order. See HOW IT WORKS. Steps that are finished or under way are left
## where they are (AdmiralPlan skips them anyway).
func _plan(ts: TeamState, plan: Array) -> Array:
	var t := ts.team
	# Step 1: which steps want to move forward, and can start now.
	var c := counts(t)
	var wanted: Array = []
	if int(c["big"]) >= BIG_MIN:
		wanted.append_array(AGAINST_BIG)
	if int(c["strike"]) >= STRIKE_MIN:
		wanted.append_array(AGAINST_STRIKE)
	var forward: Array = []
	for s: Array in wanted:
		if _can_start(ts, s):
			forward.append(s)
	# Step 2: count a change (once per new set of steps moved forward, and
	# once for the skips).
	var key := ""
	for s: Array in forward:
		key += str(s[1]) + ","
	if key != str(_forward_key[t]):
		_forward_key[t] = key
		if key != "":
			Game.count_usage("plan_reorders")
	if not bool(_skip_counted[t]):
		_skip_counted[t] = true
		Game.count_usage("plan_reorders")
	# Step 3: the forward steps first, then the plan without the skipped steps.
	var out: Array = forward.duplicate()
	for s: Array in plan:
		if SKIPPED.has(s[1]) or forward.has(s):
			continue
		out.append(s)
	return out


## Could step `s` ([kind, id]) start right now: not done, not under way and
## no blocker (prerequisites, queue room)?
func _can_start(ts: TeamState, s: Array) -> bool:
	var id: String = s[1]
	if s[0] == "f":
		return not ts.facilities.has(id) and not ts.is_building(id) and ts.facility_blocker(id) == ""
	return not ts.done.has(id) and not ts.is_researching(id) and ts.tech_blocker(id) == ""


## PilotShopping.wish_list() asks this when the pilot's team has a
## composition call `call`: the hull list this pilot should use instead of
## `base` (its normal list), or an empty list for "no change". Seats are
## PilotProfile.slot.
static func wish_list(brain: PilotAI, call: String, base: Array) -> Array:
	var slot := brain.profile.slot
	if call == "anti_capital":
		match brain.temperament:
			"striker":
				# Two strikers fly bombers, the third a lance.
				return ["lance", "bomber", "fighter"] if slot == 10 else ["bomber", "lance", "fighter"]
			"lancer":
				return ["bomber", "lance", "fighter"]
			"dog":
				# One dogfighter (seat 8) switches to a bomber.
				if slot == 8:
					return ["bomber", "fighter"]
	elif call == "anti_strike":
		# Dogfighters go to flak frigates from 15:00 (the base game: 20:00).
		if brain.temperament == "dog" and brain.world.time > FLAK_FROM:
			return ["flak"] + base
	return []
