class_name PilotTargeting
extends RefCounted
## WHAT THIS IS: the part of an AI pilot's brain (PilotAI) that decides
## WHAT to shoot, and where to stand to shoot it.
##
## HOW IT WORKS:
##   - pick_target() gives every enemy in range a score and takes the
##     lowest. The score starts as the distance (in world units), then gets
##     bonuses (lower) for juicy targets and penalties (higher) for bad
##     ones: minions about to die (last hits) and weak pilots are juicy,
##     turrets only count while our minions tank them, and a target with a
##     rock between it and us is 700 worse (our shots would hit the rock).
##   - push_target() finds a structure worth attacking with the wave (an
##     enemy turret, or the enemy mothership). Feature modules may change
##     how the turrets are scored (World.push_weight_hooks); with none, the
##     nearest one wins, as always.
##   - prey() finds an enemy pilot worth hunting (one behind a rock scores
##     700 worse, as in pick_target()).
##   - All three pass over the one unit that PilotCombat gave up on because
##     it stayed hidden behind rocks (PilotAI.skip_id), for 6 seconds.
##   - main_reach(), engage_range() and standoff() are plain calculations
##     about our guns ("static": they need no memory, only the ship).
##
## WHO USES IT: PilotGoals (lane, jungle and home thinking) calls
## pick_target, push_target and prey, and uses standoff and engage_range;
## PilotCombat uses main_reach. It asks PilotSenses about turrets, minions
## and odds, runs the feature modules' World.push_weight_hooks, and asks the
## asteroid field (AsteroidField.segment_blocked) whether a rock blocks the
## line to a candidate (pick_target, prey).
##
## Words used here:
##   tanking   our minions stand in an enemy turret's range, so it shoots
##             them instead of us.
##   backdoor  turrets take only 30% damage from pilots unless a minion of
##             the pilots' team is within 1,800 (TurretData.BACKDOOR_RADIUS).
##   PD        point defense: small automatic guns that shred strike craft
##             but barely scratch big ships.

## How far from our station (world units) we go for a push target.
const PUSH_RANGE := 3500.0
## Pilot hunting by size class (small, medium, large, capital): how far we
## look for prey (SEEK), and how far from our station we'll chase it
## (LEASH), in world units. Big ships don't chase: they hold position and
## let targets come into their guns (0 = never hunt).
const SEEK := [2600.0, 2000.0, 0.0, 0.0]
## How far from our station we chase prey, per size class (world units;
## see SEEK above; 0 = never).
const LEASH := [3200.0, 2400.0, 0.0, 0.0]

## The pilot brain this part belongs to (we read its state and world, and
## set its lock_target). It is reached through a weak link: see `_ai_ref`.
## Speed: every use of `ai` goes through the weak link (a small lookup), so each function below looks it up once into a local, `brain`, and uses that.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain. The brain holds this part with a normal
## (strong) link. If the part held the brain strongly too, each would keep
## the other alive forever and Godot could never free them (a memory leak).
## A weak link points at the brain without keeping it alive.
var _ai_ref: WeakRef
## A reusable list that the spatial hash (the world's grid for finding
## nearby units fast) fills with nearby units. PilotSenses has its own, so
## asking it questions while we walk through this list is safe.
var _scratch: Array = []


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


## The best enemy within r of us to shoot, or null. Lower score = better.
## Last hits, weak pilots and drones are juicy; turrets only while our
## minions tank them; an enemy with a rock between it and us (a shot would
## hit the rock) scores 700 worse. Also sets the brain's lock_target to the
## answer.
func pick_target(ship: Ship, r: float) -> Unit:
	var brain := ai
	var world := brain.world
	var best: Unit = null
	var best_s := INF
	# A rough guess of the damage of one of our volleys: a minion with less
	# than two volleys of hull + shields left is a "last hit" (a kill that
	# pays).
	var my_dmg := 30.0
	# Ships with weapons that hurt big hulls and structures a lot.
	var heavy_hitter := ship.hull_id in ["bomber", "ion", "destroyer", "battlecruiser", "lance"]
	# Are we inside an enemy turret's range ourselves (plus 150)?
	var me_covered := brain.senses.enemy_turret_at(ship.global_position, ship.team, 150.0) != null
	for u: Unit in world.unit_hash.query(ship.global_position, r, _scratch):
		# Step 1: only live, visible enemies truly within r.
		# Neutral units (jungle monsters) only count while jungling.
		if not u.alive or u.team == ship.team:
			continue
		if u.team == Rules.NEUTRAL and brain.state != "jungle":
			continue
		# A target given up on (hidden behind rocks) waits 6 s.
		if brain.skip_id != 0 and u.get_instance_id() == brain.skip_id and world.time < brain.skip_until:
			continue
		if not u.visible_to(ship.team):
			continue
		var d := ship.global_position.distance_to(u.global_position)
		if d > r:
			continue
		# Step 2: start from the distance, then adjust by kind.
		var s := d
		match u.kind:
			Unit.K_SHIP:
				# Pilots: +200, but up to 600 less the more damaged they are.
				s += 200.0 - (1.0 - u.hull_frac()) * 600.0
				# Much bigger hulls (2+ size classes up) are a poor match,
				# unless our weapons are made for them.
				if u.size_class > ship.size_class + 1 and not heavy_hitter:
					s += 500.0
				# Torpedoes are wasted on strike craft (x0.35 damage, easy to
				# dodge).
				if ship.hull_id == "bomber" and u.size_class == Rules.SIZE_SMALL:
					s += 800.0
				# Shooting a pilot under their turret makes the turret pick us.
				# Small and medium ships skip that, unless the pilot is nearly
				# dead (25% hull or less) and we are healthy (60% or more).
				if ship.size_class < Rules.SIZE_LARGE and (me_covered or brain.senses.enemy_turret_at(u.global_position, ship.team, 0.0) != null):
					if u.hull_frac() > 0.25 or ship.hull_frac() < 0.6:
						continue
			Unit.K_MINION:
				s += 250.0
				# Last hit: a big bonus.
				if u.hull + u.shield_total() < my_dmg * 2.0:
					s -= 700.0
				# Heavy hitters like the bigger minions (medium size and up,
				# such as the escort corvettes).
				if heavy_hitter and u.size_class >= Rules.SIZE_MEDIUM:
					s -= 300.0
			Unit.K_TURRET:
				# Turrets: small and medium ships only shoot ones our minions
				# tank; heavy hitters and tanked turrets score better.
				var tanked := brain.senses.minions_tanking(u as Turret, ship.team)
				if not tanked and ship.size_class < Rules.SIZE_LARGE:
					continue
				s += 300.0 - (500.0 if heavy_hitter else 0.0) - (300.0 if tanked else 0.0)
			Unit.K_MINING_DRONE:
				s -= 200.0
			Unit.K_WARD:
				s -= 100.0
			Unit.K_REPAIR_DRONE:
				s += 100.0
			Unit.K_MONSTER, Unit.K_SNUB:
				s += 100.0
		# Step 3: keep the lowest score so far. A candidate that would win
		# gets 700 added if a rock blocks the line to it (checked only then,
		# to save the cost); it may lose its lead because of that.
		if s < best_s:
			if world.asteroids.segment_blocked(ship.global_position, u.global_position):
				s += 700.0
				if s >= best_s:
					continue
			best_s = s
			best = u
	# Step 4: the enemy mothership, once we are in range (80% of r from its
	# hull). It isn't in the spatial hash, so it is checked on its own. Big
	# ships and bombers want it much more (+100 instead of +900).
	var ems := world.mothership(1 - ship.team)
	if ems != null and ems.alive and ems.hull_dist(ship.global_position) < r * 0.8:
		var s2 := ems.hull_dist(ship.global_position) + (100.0 if ship.size_class >= Rules.SIZE_LARGE or ship.hull_id == "bomber" else 900.0)
		if s2 < best_s:
			best = ems
	brain.lock_target = best
	return best


## A structure worth attacking now (DESIGN A9: push the wave into turrets),
## or null. Either the nearest enemy turret within PUSH_RANGE of our
## station whose backdoor protection is off (our minions are within 1,440
## of it) and which our minions are tanking (big ships only need the
## minions near a PD turret, which can't hurt them much); or else the enemy
## mothership when its hull is within 5,000 of our station and we are a big
## ship, a bomber, or 3+ of our minions are at its hull.
## Feature hook: when World.push_weight_hooks has functions in it, each
## turret that passes the tests gets a score (its distance, changed by
## every hook in turn; lower = better, INF = never) and the lowest score
## wins instead of the nearest. With no hooks this is today's choice.
func push_target(ship: Ship, station: Vector2) -> Unit:
	var brain := ai
	var world := brain.world
	# Not when hurt (below 45% hull), and not in a scout or logistics ship.
	if ship.hull_frac() < 0.45 or ship.hull_id == "scout" or ship.hull_id == "logistics":
		return null
	# Feature hooks that re-score the turrets (usually none).
	var hooks := world.push_weight_hooks
	var weighted := not hooks.is_empty()
	# Step 1: the nearest (or, with hooks, the best-scored) enemy turret
	# that passes every test. `bd` is the best score so far: without hooks
	# the distance, starting at PUSH_RANGE so farther turrets are skipped
	# before the costlier tests.
	var best: Unit = null
	var bd := INF if weighted else PUSH_RANGE
	for t: Turret in world.turrets:
		if not t.alive or t.team == ship.team or t.team == Rules.NEUTRAL or not t.is_built():
			continue
		if brain.skip_id != 0 and t.get_instance_id() == brain.skip_id and world.time < brain.skip_until:
			continue
		var d := station.distance_to(t.global_position)
		if d > (PUSH_RANGE if weighted else bd):
			continue
		if not brain.senses.minions_near(t.global_position, ship.team, TurretData.BACKDOOR_RADIUS * 0.8):
			continue
		var big_vs_pd := ship.size_class >= Rules.SIZE_LARGE and t.ttype == "pd"
		if not big_vs_pd and not brain.senses.minions_tanking(t, ship.team):
			continue
		# Its score: the distance, or with hooks what they make of it (a
		# score of INF means "never this one").
		var s := d
		if weighted:
			s = _hooked_score(hooks, ship, t, d)
			if s == INF or s > bd:
				continue
		bd = s
		best = t
	if best != null:
		return best
	# Step 2: no turret: the enemy mothership, if it is close enough.
	var ems := world.mothership(1 - ship.team)
	if ems != null and ems.alive and ems.hull_dist(station) < PUSH_RANGE + 1500.0:
		if not ship.is_small() or ship.hull_id == "bomber" or brain.senses.minions_at_hull(ems, ship.team, 2500.0) >= 3:
			return ems
	return null


## Feature hook helper for push_target(): run turret `t`'s `score` (its
## distance from our station, in world units) through every function in
## `hooks` (World.push_weight_hooks), in order, each getting the last one's
## answer. Returns the final score (lower = better; INF = never pick it).
func _hooked_score(hooks: Array[Callable], ship: Ship, t: Unit, score: float) -> float:
	var s := score
	for f: Callable in hooks:
		s = float(f.call(ship, t, s))
	return s


## An enemy pilot worth hunting, or null: visible, within SEEK of us and
## LEASH of our station, not sheltering under an enemy turret, and not in a
## fight we'd lose. Lower score = better: nearer, and more damaged, and 700
## worse when a rock is between it and us.
func prey(ship: Ship, station: Vector2) -> Unit:
	var brain := ai
	# Step 1: only small and medium ships hunt, with at least half their
	# hull, and never in a scout or logistics ship.
	var si := Rules.size_index(ship.size_class)
	var seek: float = SEEK[si]
	if seek <= 0.0 or ship.hull_frac() < 0.5 or ship.hull_id in ["scout", "logistics"]:
		return null
	var leash: float = LEASH[si]
	var best: Unit = null
	var best_s := INF
	for u: Unit in brain.world.unit_hash.query(ship.global_position, seek, _scratch):
		# Step 2: live, visible enemy pilot ships only.
		if u.kind != Unit.K_SHIP or not u.alive or u.team == ship.team or u.team == Rules.NEUTRAL:
			continue
		if not u.visible_to(ship.team):
			continue
		if brain.skip_id != 0 and u.get_instance_id() == brain.skip_id and brain.world.time < brain.skip_until:
			continue
		# Step 3: close to us, close to our station, not under a turret
		# (with 200 to spare).
		var d := ship.global_position.distance_to(u.global_position)
		if d > seek or u.global_position.distance_to(station) > leash:
			continue
		if brain.senses.enemy_turret_at(u.global_position, ship.team, 200.0) != null:
			continue
		# Step 4: score: distance, minus up to 800 the more damaged it is.
		var s := d - (1.0 - u.hull_frac()) * 800.0
		# Match-ups: bombers hunt big hulls; everyone else avoids frigates
		# and capitals unless they're nearly dead (30% hull or less), since
		# flak shreds strike craft.
		if ship.hull_id == "bomber":
			if u.size_class == Rules.SIZE_SMALL:
				continue
			s -= 400.0
		elif u.size_class >= Rules.SIZE_LARGE and u.hull_frac() > 0.3:
			continue
		# Step 5: skip fights where the odds there (with us joining) are
		# worse than -1.
		if brain.senses.odds_at(u.global_position, ship) < -1:
			continue
		# A pilot behind a rock scores 700 worse (checked only for a
		# candidate that would otherwise win).
		if s < best_s and brain.world.asteroids.segment_blocked(ship.global_position, u.global_position):
			s += 700.0
		if s < best_s:
			best_s = s
			best = u
	return best


## How far our main guns reach (world units): the longest reach of our
## aimed guns (fixed and turret mounts), times our range bonus. Automatic
## guns (flak and point defense, which pick their own targets) don't count.
## 600 if we have no aimed gun.
static func main_reach(ship: Ship) -> float:
	var r := 0.0
	for m in ship.mounts:
		if m.mount_type != WeaponMount.AUTO:
			r = maxf(r, m.reach * ship.range_mult)
	return r if r > 0.0 else 600.0


## How far around us we look for targets: 1.25 times our main reach, but at
## least 900 world units.
static func engage_range(ship: Ship) -> float:
	return maxf(900.0, main_reach(ship) * 1.25)


## Where to fly to attack `t`: inside our weapon reach, on the side of it
## facing our station. Medium and bigger ships stand at 80% of their reach
## from its edge, small ships at 60%. For a mothership we measure from the
## closest point on its spine (the line from bow to stern) plus half its
## width.
static func standoff(ship: Ship, t: Unit, station: Vector2) -> Vector2:
	var reach := main_reach(ship)
	var tp := t.global_position
	var pad := t.radius
	if t is Mothership:
		var ms := t as Mothership
		var f := Vector2.from_angle(ms.rotation) * ms.half_len
		tp = Util.closest_on_segment(station, ms.global_position + f, ms.global_position - f)
		pad = ms.beam * 0.5
	# The direction from the target toward our station (or toward us, if
	# the station is right on top of it).
	var dir := (station - tp).normalized()
	if dir == Vector2.ZERO:
		dir = (ship.global_position - tp).normalized()
	return tp + dir * (reach * (0.8 if ship.size_class >= Rules.SIZE_MEDIUM else 0.6) + pad)
