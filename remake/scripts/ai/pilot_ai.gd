class_name PilotAI
extends RefCounted
## WHAT THIS IS: the brain of one computer-controlled pilot. Each team has 12
## pilot seats, and every seat without a human in it gets one of these (so
## 11 or 12 per team). It flies the same ships under the same rules as a
## human: all it does is work the ship's "sticks and buttons" (ShipControls),
## the way a human's keyboard and mouse do. (DESIGN.md A14.)
##
## HOW IT WORKS:
##   - Docked at the mothership: update_docked() goes shopping about once a
##     second and then launches (with the Hyperspace Module it jumps to the
##     repair bay nearest the pilot's lane instead, when that saves a long
##     flight).
##   - Flying: update() runs every tick (the game moves forward in small
##     steps called ticks, 60 per second). About 3 to 4 times a second the
##     brain "thinks" (_think): it checks its hull, decides whether to fly
##     home, and chooses a `goal` (a point to fly to) and a `target` (a unit
##     to shoot). Every tick it then works the controls to reach that goal
##     and hit that target.
##   - What the brain is busy with is its `state`:
##       lane     hold a spot just behind our minion wave (minions are the
##                small robot ships the motherships send down each lane).
##                The spot is a fixed STATION (we park there; we don't
##                circle it). In the OPENING (the first minutes: see
##                PilotGoals.opening_active()) the station is different:
##                for the first Rules.AI_OPENING_HOLD seconds near our
##                mothership, then at our lane's Crossing node, until our
##                first wave gets there. Shoot enemy minions for money
##                (whoever lands the killing shot, the "last hit", gets
##                paid), and:
##                push - attack an enemy turret that our minions are
##                       "tanking" (standing in its range, so it shoots them
##                       and not us) near the front line (big ships lead the
##                       way into point-defense turrets, which barely hurt
##                       them while the damage modifiers are kept), or the
##                       enemy mothership once the wave reaches it;
##                prey - hunt a visible enemy pilot within SEEK of us and
##                       LEASH of our station when the local odds are fair
##                       and it isn't hiding under an enemy turret (big ships
##                       don't chase: they hold and shoot what comes close);
##                farm - with nothing else to do, fly out to the best enemy
##                       minion within PilotTargeting.FARM_RADIUS of our wave's
##                       front minion and shoot it (last hits first), instead
##                       of waiting at the station for a target to come.
##       jungle   clear derelict camps (neutral monster ships in the asteroid
##                "jungle" between the lanes). Junglers join the opening at
##                the middle Crossing first (where, like a lane pilot, one
##                that is hurt and outnumbered falls back), and go to their
##                camps after.
##       retreat  hull is low (or, for a ship smaller than a frigate, hull and
##                shields together are under SOFT_RETREAT_BELOW): use a
##                repair kit, then fly to a repair bay or home to dock.
##       home     fly home to dock and shop.
##   - Its `temperament` (picked from its seat number) decides what it likes
##     to buy: heavy hulls, strike craft (bombers/lances), support corvettes,
##     or dogfighters.
##
## THE PARTS: the brain is split into helper "parts", one job each. This file
## keeps the shared memory (state, target, goal, timers...), the per-tick
## loop and the order in which the brain thinks. The parts do the detail:
##   PilotShopping  (pilot_shopping.gd)  what to buy, and when to fly home
##   PilotGoals     (pilot_goals.gd)     where to fly in each state
##   PilotTargeting (pilot_targeting.gd) what to shoot
##   PilotSenses    (pilot_senses.gd)    "looking around" questions (odds,
##                                       turrets, nearby minions)
##   PilotCombat    (pilot_combat.gd)    every tick: fight the target or fly
##   PilotFlight    (pilot_flight.gd)    flying to a point without crashing
##   PilotSystems   (pilot_systems.gd)   energy routing and shield facing
##
## WHO USES IT: World.setup() makes one per AI pilot and uses ROLE_PLAN to
## give each seat its role. World calls update_docked() every tick while the
## pilot is docked. World.launch() makes this brain the new ship's
## `controller`, so Ship.sim_update() calls update() every tick and
## Ship.homing_target() reads lock_target. Tests (tests/arena.gd,
## match_probe.gd, endgame.gd) read state, target, goal,
## intent, home_reason, path, path_i and the timers, set hold_point and
## launched_at, and call _reset_after_launch().

## The job of each pilot seat, by seat number 0-11 (PilotProfile.slot):
## "top", "mid" or "bot" (hold that lane), "jungle" (roam the jungle between
## the lanes) or "flex" (the support pilot, who moves from lane to lane).
## World.setup() copies these into PilotProfile.role.
const ROLE_PLAN := ["top", "mid", "bot", "jungle", "top", "mid", "bot", "flex", "top", "mid", "bot", "jungle"]
## A ship smaller than a frigate turns back (a "soft" retreat) when its hull
## plus shields together fall below this fraction of their maximum. The
## hull alone is the wrong gauge for them: it stays full until the shields
## are gone, so at 35% hull they have already lost most of their health.
## A tuning knob: a higher number makes small ships retreat earlier.
const SOFT_RETREAT_BELOW := 0.25
## A soft retreat ends when hull plus shields are back up to this fraction.
## A tuning knob.
const SOFT_RETREAT_END := 0.7

# --- the brain's memory ----------------------------------------------------------------

## The game world: units, map, teams and the clock (world.time, in seconds).
var world: World
## This pilot's own record: team, seat (slot), role, credits, hull and gear.
var profile: PilotProfile
## The unit our homing rounds (a bomber's torpedoes) should chase, or null.
## Ship.homing_target() reads it. The brain sets it whenever it picks a
## target (PilotTargeting.pick_target, and the push, prey and assault
## choices in PilotGoals).
var lock_target: Unit = null
## What this pilot likes to buy (see PilotShopping.HULL_PREF): "heavy",
## "heavy_ion", "striker", "support", "lancer", "dog" (dogfighter) or
## "jungle". Set once in _init from the seat number.
var temperament := "dog"
## How good this pilot is, as a 0..1 number (0.5 to 0.95 in practice;
## 0.30 to 0.98 with the --skill-jitter test option, see SkillJitter).
## Better pilots think more often, aim straighter, and use energy routing
## (above 0.55) and shield focus (above 0.6).
var skill := 0.7
## What the brain is busy with: "lane", "jungle", "retreat" or "home" (see
## the list at the top of this file).
var state := "lane"
## Seconds until the brain thinks again.
var think_t := 0.0
## The unit we are shooting at, or null for none.
var target: Unit = null
## The point we are flying to (world position; 1 world unit is about one
## pixel at normal zoom).
var goal := Vector2.ZERO
## The planned route to `goal`: a list of waypoints (stepping-stone points)
## from the map's route graph. Empty = no route, fly straight. PilotFlight
## fills it; tests read it.
var path := PackedVector2Array()
## Which waypoint of `path` we are flying toward (a position in the list).
var path_i := 0
## The goal that `path` was planned for (Vector2.INF = no plan yet). When
## the goal moves more than 600 world units away from it, we plan again.
var path_goal := Vector2.INF
## Which way we slide sideways while fighting or backing off: +1 or -1. It
## flips every 1.8 to 3.4 seconds so we're harder to hit.
var orbit := 1.0
## Seconds until `orbit` flips.
var orbit_t := 0.0
## Seconds until the next shopping-and-launch try while docked.
var shop_t := 0.0
## The derelict camp a jungler is clearing, or null.
var camp: Unit = null
## Seconds left backing out of an enemy turret's range (it targeted us).
var evade_t := 0.0
## Where the turret we're running from stands (world position).
var evade_from := Vector2.ZERO
## Seconds left falling back because we're outnumbered.
var fallback_t := 0.0
## Game time (seconds) of our last launch; -999 means "not launched yet".
## A pilot won't fly home to shop in the first 150 s after a launch.
var launched_at := -999.0
## Tests and orders: hold here instead of the lane station (Vector2.INF =
## off). tests/arena.gd sets it.
var hold_point := Vector2.INF
## Why `target` was chosen: "" (it was in range), "prey" (hunting a pilot),
## "push" (attacking a structure our minions are tanking) or "farm" (flying
## out to a minion near our wave's front minion). Big ships close to a
## standoff range for prey/push/farm targets; otherwise they hold station.
var intent := ""
## Why we're flying home to shop, e.g. "hull:destroyer" (to buy a
## destroyer) or "gear:helm_neural"; "" when not. tests/match_probe.gd
## reports it.
var home_reason := ""
## The id (get_instance_id) of a target we gave up on because it stayed
## hidden behind rocks (0 = none). PilotCombat sets it; the target pickers
## ignore that unit until `skip_until`.
var skip_id := 0
## Game time (seconds) until which the unit `skip_id` is ignored.
var skip_until := 0.0
## True while the current retreat is a "soft" one: it began because hull
## plus shields fell under SOFT_RETREAT_BELOW while the hull was still over
## 35%, so it ends sooner (see _think()).
var soft_retreat := false
## True once this pilot's opening is over for good (PilotGoals
## .opening_active() sets it): our first minion wave reached the lane's
## Crossing node, or Rules.AI_OPENING_MAX seconds went by. The arrival is a
## fact about the team and the lane (TeamState.first_wave_at, noted once), so
## a pilot that was dead, docked, retreating or flying home when the wave got
## there is done at its first think after that, whether or not the wave is
## still alive. It never goes back to false, so a later wave that dies cannot
## start a second opening.
var opening_done := false

# --- the parts (see THE PARTS at the top) ----------------------------------------------

## What to buy, and whether a trip home to shop is worth it.
var shopping: PilotShopping
## Where to fly in each state (lane station, jungle camp, home).
var goals: PilotGoals
## What to shoot (and where to stand to shoot it).
var targeting: PilotTargeting
## Questions about our surroundings (odds, turrets, minions).
var senses: PilotSenses
## Every tick: fight the target, or fly toward the goal.
var combat: PilotCombat
## How to fly to a point: routes, braking, unsticking, dodging rocks.
var flight: PilotFlight
## Energy routing and shield focus.
var systems: PilotSystems


## Make the brain for one pilot. The seat number decides the temperament
## and the skill, so the same seat plays the same way on both teams.
func _init(w: World, p: PilotProfile) -> void:
	world = w
	profile = p
	# Make the parts. Each one keeps a link back to this brain.
	shopping = PilotShopping.new(self)
	goals = PilotGoals.new(self)
	targeting = PilotTargeting.new(self)
	senses = PilotSenses.new(self)
	combat = PilotCombat.new(self)
	flight = PilotFlight.new(self)
	systems = PilotSystems.new(self)
	# Step 1: temperament from the role and the seat number. Junglers get
	# the jungle temperament; seats 1, 5 and 9 fly heavy ships (seat 5
	# prefers the ion frigate); seats 2, 6 and 10 fly strike craft; the flex
	# pilot flies support; seat 4 flies the lance; the rest (seats 0 and 8)
	# dogfight.
	var s := p.slot
	if p.role == "jungle":
		temperament = "jungle"
	elif s in [1, 5, 9]:
		temperament = "heavy_ion" if s == 5 else "heavy"
	elif s in [2, 6, 10]:
		temperament = "striker"
	elif p.role == "flex":
		temperament = "support"
	elif s == 4:
		temperament = "lancer"
	else:
		temperament = "dog"
	# Step 2: skill, between 0.5 and 0.95. It varies by seat but is the same
	# for both teams (playtest: a team term here gave the same role a
	# different skill on each side, and identical 3v3 fighter squads went
	# 15-5 to Vhorr).
	skill = 0.5 + 0.45 * fmod(float(s) * 0.618 + 0.15, 1.0)
	# Fun tests only (--skill-jitter): nudge the seat's skill by its own
	# random amount, the same for this seat on both teams (SkillJitter;
	# it never uses the shared random sequence).
	if Game.opt("skill-jitter") != null:
		skill = SkillJitter.jittered(skill, s)
	# Step 3: start the timers. A random first think (0 to 0.3 s) spreads
	# the pilots' thinking over different ticks. The first shopping waits
	# 1 second plus 0.25 s per seat number, so seats shop one after the
	# other.
	think_t = randf() * 0.3
	shop_t = 1.0 + float(s) * 0.25


# --- docked: shopping ------------------------------------------------------------------

## While docked: every 0.6 to 1.0 seconds, shop and then try to launch (or
## to jump by hyperspace, see _hyperspace_bay()). World calls this every
## tick while profile.state is "docked".
func update_docked(dt: float) -> void:
	# Step 1: wait for the shopping timer.
	shop_t -= dt
	if shop_t > 0.0:
		return
	shop_t = 0.6 + randf() * 0.4
	# Step 2: no shopping during a mothership outage (same rule as the human
	# hangar); a repair bay launch is still allowed, so a pilot with no hull
	# at all takes a free scout.
	var ms := world.mothership(profile.team)
	if ms != null and ms.available():
		shopping.shop()
	elif profile.hull_id == "":
		profile.buy_hull("scout", world.teams[profile.team])
	# Step 3: with the Hyperspace Module, jump to the repair bay nearest our
	# destination when that saves more flying than the 6 s spool costs
	# (MatchRules finishes the launch; the brain starts its fresh plan now).
	if profile.hull_id != "":
		var bay := _hyperspace_bay()
		if bay != null and world.hyperspace_launch(profile, bay) == "":
			_reset_after_launch()
			return
	# Step 4: launch. If it works, start a fresh plan for the new ship.
	if profile.hull_id != "" and world.launch(profile) != null:
		_reset_after_launch()


## The anchored repair bay worth jumping to with the Hyperspace Module, or
## null (no module, no bay, or the jump saves too little). The destination
## is the front of our lane's minion wave (junglers and the flex pilot use
## the mid lane); the jump pays when the bay is closer to it than the
## launch point by more than the ship flies during the 6 s spool plus 1,500
## world units.
func _hyperspace_bay() -> Unit:
	# Feature hook (Forward Redeploy): it chooses a bay or a turret near the
	# pilot's destination itself (RedeployFeature.pick_site).
	if world.features.has("redeploy"):
		return (world.features["redeploy"] as RedeployFeature).pick_site(self)
	# Step 1: we need our mothership and the module.
	var ts := world.teams[profile.team]
	var ms := world.mothership(profile.team)
	if ms == null or not ts.facilities.has("hyperspace"):
		return null
	# Step 2: the repair bay nearest the wave front.
	var dest := goals.lane_front(goals.lane_id(), profile.team)
	var bay := world.best_bay(profile.team, dest)
	if bay == null:
		return null
	# Step 3: jump only when it saves more than flying would cost.
	var speed := float(Ships.HULLS[profile.hull_id]["max"])
	var saved := ms.launch_point(profile.slot).distance_to(dest) - bay.global_position.distance_to(dest)
	if saved > speed * World.HYPERSPACE_SPOOL + 1500.0:
		return bay
	return null


## A fresh ship starts a fresh plan (otherwise "home" or "retreat" would fly
## it straight back to dock). Also called by tests/arena.gd.
func _reset_after_launch() -> void:
	state = "jungle" if profile.role == "jungle" else "lane"
	target = null
	lock_target = null
	intent = ""
	camp = null
	evade_t = 0.0
	fallback_t = 0.0
	soft_retreat = false
	path = PackedVector2Array()
	path_goal = Vector2.INF
	launched_at = world.time


# --- flying ------------------------------------------------------------------------------

## Every tick while flying (Ship.sim_update() calls it through
## Ship.controller): run the timers, think every 0.23 to 0.35 seconds, and
## work the controls every tick.
func update(ship: Ship, dt: float) -> void:
	# Step 1: flip which way we slide sideways every 1.8 to 3.4 seconds.
	orbit_t -= dt
	if orbit_t <= 0.0:
		orbit_t = 1.8 + randf() * 1.6
		orbit = -orbit
	# Step 2: count down the evade and fall-back timers (never below 0).
	evade_t = maxf(0.0, evade_t - dt)
	fallback_t = maxf(0.0, fallback_t - dt)
	# Step 3: think when the timer runs out. Better pilots think sooner
	# (0.23 s at skill 0.95, 0.35 s at skill 0.5).
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.22 + (1.0 - skill) * 0.25
		_think(ship)
	# Step 4: every tick, fight or fly (PilotCombat).
	combat.steer(ship)


## One think: decide the state, the goal and the target. The order matters:
## staying alive first, then shopping trips, then running from turrets and
## from lost fights, and only then the normal job for the state.
func _think(ship: Ship) -> void:
	var c := ship.controls
	var hp := ship.hull_frac()
	var ms := world.mothership(ship.team)
	# Step 1: survival first. Below 35% hull we retreat, and keep retreating
	# until the hull is back to 85%. A repair kit (a consumable that sends a
	# repair drone to fix our hull) is used below 50% while retreating, or
	# below 60% between fights (no hull damage for 2 seconds), never while
	# one is already working.
	var want_retreat := hp < 0.35 or (state == "retreat" and hp < 0.85)
	# A ship smaller than a frigate also turns back when hull plus shields
	# together fall under SOFT_RETREAT_BELOW (a "soft" retreat), and goes
	# back out once they are over SOFT_RETREAT_END again. (The hull is what
	# is left after the shields are gone, so at 35% hull such a ship has
	# already lost most of its health.) A hull under 35% is a normal
	# retreat, with its normal end.
	if hp < 0.35:
		soft_retreat = false
	elif state != "retreat" and ship.size_class < Rules.SIZE_LARGE and ship.total_frac() < SOFT_RETREAT_BELOW:
		want_retreat = true
		soft_retreat = true
	elif state == "retreat" and soft_retreat and ship.total_frac() >= SOFT_RETREAT_END:
		want_retreat = false
	if want_retreat:
		state = "retreat"
		if hp < 0.5 and profile.kit_count() > 0 and not ship.has_active_kit():
			c.use_kit = true
	elif state == "retreat":
		soft_retreat = false
		state = "jungle" if profile.role == "jungle" else "lane"
	elif hp < 0.6 and profile.kit_count() > 0 and not ship.has_active_kit() and world.time - ship.last_hull_damage_time > 2.0:
		# Top up between fights.
		c.use_kit = true
	# Step 2: is a shopping trip home worth it (PilotShopping)?
	if state != "retreat" and state != "home":
		home_reason = shopping.wants_shopping(ship)
		if home_reason != "":
			state = "home"
	elif state == "home" and world.teams[ship.team].siege_lane != "" and (not ship.is_small() or ship.hull_id == "bomber"):
		# A siege started while we were flying home to shop (big ships and
		# bombers only): join it instead.
		state = "jungle" if profile.role == "jungle" else "lane"
		home_reason = ""
	# Step 3: a turret has picked us as its target (the "aggro" rule:
	# turrets go after a pilot who hurts their side's ships nearby). Small
	# and medium ships get out of its range for 2.5 seconds, unless they're
	# already flying home.
	var hunter := senses.turret_targeting(ship)
	if hunter != null and ship.size_class < Rules.SIZE_LARGE and state != "home":
		evade_t = 2.5
		evade_from = hunter.global_position
	# Step 4: outnumbered (odds of -2 or worse) and hurt (below 75% hull) on
	# the lane, or as a jungler in the opening (it then does everything a lane
	# pilot does, see PilotGoals.think_jungle()): fall back toward our side for
	# 4 seconds. (The opening check comes after the cheap ones. Asking is
	# harmless: Step 2 asks it every think anyway.)
	if fallback_t <= 0.0 and hp < 0.75 and (state == "lane" or (state == "jungle" and goals.opening_active())) and senses.odds(ship) <= -2:
		fallback_t = 4.0
	intent = ""
	# Step 5: evading a turret (unless retreating anyway): aim for a point
	# 2,600 from the turret, on our side of it, and shoot nothing.
	if evade_t > 0.0 and state != "retreat":
		var away := (ship.global_position - evade_from).normalized()
		goal = evade_from + away * 2600.0
		target = null
		lock_target = null
		systems.set_energy_and_shields(ship)
		return
	# Step 6: the normal job for our state (PilotGoals), unless a feature
	# module with a pilot_think() takes over this think (see
	# _feature_takes_over(); no feature is on by default).
	if world.features.is_empty() or not _feature_takes_over(ship):
		match state:
			"retreat", "home":
				goals.think_home(ship, ms)
			"jungle":
				goals.think_jungle(ship)
			_:
				goals.think_lane(ship)
	# Feature hooks (World.pilot_think_hooks; none unless a feature is on):
	# they may change the goal and the target chosen above.
	for f: Callable in world.pilot_think_hooks:
		f.call(ship, self)
	# Step 7: set the energy routing and shield focus (PilotSystems).
	systems.set_energy_and_shields(ship)


## Feature hook: does a feature module take over this think? Asks every
## feature in World.features that has a function
## pilot_think(brain: PilotAI, ship: Ship) -> bool, in install order, until
## one answers true (it then has set the goal, target and intent itself, as
## the normal job for our state would). Only called while at least one
## feature is on, and only in the "lane" and "jungle" states (a retreating or
## shopping pilot is left alone). Used by the fork teamfights_jungle's
## modules (GroupLateFeature, SalvageCoreFeature, JungleScaleFeature,
## EpicNeutralFeature, BeaconsFeature).
func _feature_takes_over(ship: Ship) -> bool:
	if state != "lane" and state != "jungle":
		return false
	for f: Object in world.features.values():
		if f.has_method("pilot_think") and f.call("pilot_think", self, ship):
			return true
	return false


# --- forwarding ----------------------------------------------------------------------------
