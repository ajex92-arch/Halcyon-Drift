class_name Mothership
extends Unit
## WHAT THIS IS: a team's mothership: the huge home ship where pilots
## launch, dock, respawn and shop. Destroying the enemy's mothership is the
## only way to win. DESIGN.md A12.
##
## HOW IT WORKS:
##   - Long hull: it is a capsule (picture a thick line with round ends),
##     not a circle, so "how far away is it?" and "did that shot hit it?"
##     are measured from the line down its middle, the keel
##     (MothershipHull). The arrow from the centre to the bow end of the keel
##     is asked for all the time and only changes when the ship turns, so
##     keel_arrow() keeps it.
##   - Guns: point defense and medium cannons from the start; Flagship
##     research adds more point defense, flak, heavy batteries and an ion
##     lance, and grows its hull and shield (MothershipGuns, through
##     apply_upgrades()).
##   - Weak to big ships, while the damage modifiers are kept: Combat
##     multiplies damage by the attacker's size (Rules.MOTHERSHIP_ATTACKER),
##     so strike craft barely scratch it and capital ships tear it; minions
##     do half damage. With the damage modifiers removed every hit does its
##     raw damage, whoever fires it. Its own defences stay either way: hull
##     resistance, shield, point defense.
##   - Respawn strain: many PLAYER respawns in a short time
##     (TeamState.strain_t) slow its guns (x0.6) and stop its shield from
##     refilling.
##   - Emergency at 35% hull, once per match (DESIGN.md C11, the "retreat"
##     game option; MothershipRetreat): "systems_failure" (the default: a
##     45 s outage with no launching, respawning or shopping here and guns
##     at half speed) or "none".
##   - Movement: from 20:00 the admiral can order it to a point
##     (MothershipDrive).
##   - Docking: pilots dock within dock_radius() of the hull and launch from
##     just past the bow (launch_point()).
##
## WHO USES IT: WorldSetup makes one per team (World.mothership(team) finds
## it). World calls sim_update() every tick. Very many files call
## hull_dist() (AI pilots, minions, drones, Combat, TeamState, WorldHangar,
## WorldMining...). WorldHangar, the hangar screen, MatchRules and AI
## pilots ask available(); MinionDirector, WorldSpawner and WorldHangar
## launch from launch_point(); AdmiralCommand calls can_move() and
## order_move(); the research code (TeamTech) calls apply_upgrades();
## Projectiles and Combat.beam() call hit_t(); the HUD and admiral's board
## show failure_t; UnitVisual draws it (beam, move_target).
## MatchRules ends the match when it dies.

# --- shape and guns --------------------------------------------------------------------

## Its data row (Structures.MOTHERSHIP): hull, shield, size, speed, gun
## spots and the emergency numbers.
var def: Dictionary = Structures.MOTHERSHIP
## Half the length of the keel line, in world units (1 world unit is about
## one pixel at normal zoom): from the centre to the middle of each round
## end. The hull reaches beam / 2 further. setup() sets it to
## length / 2 - beam / 2 (630 with the current data).
var half_len := 630.0
## The rotation that keel_arrow() last worked out its answer for (INF = none
## yet).
var _keel_rot := INF
## The half_len that keel_arrow() last worked out its answer for.
var _keel_len := -1.0
## The answer keel_arrow() kept: nose direction times half_len.
var _keel_f := Vector2.ZERO
## The hull's width, in world units.
var beam := 340.0
## All its guns (WeaponMount): the base guns first, then research guns in
## the order they were added.
var mounts: Array[WeaponMount] = []
## The rate-of-fire multiplier for its guns right now (1.0 = normal);
## respawn strain and systems failure lower it. Worked out every tick.
var fire_mult := 1.0

# --- movement (see MothershipDrive) ----------------------------------------------------

## Where the admiral ordered it to go, or Vector2.INF (meaning "nowhere")
## when it isn't moving. UnitVisual draws a line to it; the AI admiral
## checks it to see whether the ship is still on its way.
var move_target := Vector2.INF
## The route to move_target: points on the route map, in world positions.
var move_path := PackedVector2Array()
## Which point of move_path it is heading for (an index).
var move_i := 0
## Top speed when moving, in world units per second.
var move_speed := 80.0

# --- emergency retreat (DESIGN.md C11, see MothershipRetreat) --------------------------

## Seconds left of the "systems failure" emergency (0 = working normally).
var failure_t := 0.0
## True once the once-per-match emergency has been used up.
var retreat_used := false

# --- research (see MothershipGuns) -----------------------------------------------------

## How many research guns of each kind it already has ("pd", "flak",
## "heavy", "ion"), so apply_upgrades() only adds the new ones. The "hull"
## and "shield" entries are not used.
var applied := {"pd": 0, "flak": 0, "heavy": 0, "ion": 0, "hull": 0.0, "shield": 0.0}
## Hull points before research (from def).
var base_hull_max := 0.0
## Shield size before research, in shield points.
var base_shield := 0.0
## Shield refill speed before research, in shield points per second.
var base_regen := 0.0


## Set up the mothership of team `t` at `at`, its nose pointing at angle
## `facing` (radians). WorldSetup calls it once per team at the start.
func setup(w: World, t: int, at: Vector2, facing: float) -> void:
	# Step 1: who we are and where.
	world = w
	team = t
	kind = Unit.K_MOTHERSHIP
	size_class = Rules.SIZE_MOTHERSHIP
	# Internal label: tests print it and no screen shows it; a screen that does must use Rules.display_label().
	display_name = "%s mothership" % Rules.TEAM_NAMES[t]
	position = at
	rotation = facing
	# Step 2: the shape. `radius` (used by the code shared by all units) is
	# half the width; the keel runs half_len each way from the centre.
	beam = float(def["beam"])
	half_len = float(def["length"]) * 0.5 - beam * 0.5
	radius = beam * 0.5
	# Step 3: hull, armour, shield, sight and speed from the data.
	base_hull_max = float(def["hull"])
	hull_max = base_hull_max
	hull = hull_max
	hull_resist = float(def["hull_resist"])
	base_shield = float(def["shield"])
	base_regen = float(def["shield_regen"])
	shields = ShieldZones.new()
	# One shield pool: attackers can't starve a single zone of a hull this big.
	shields.setup(base_shield, base_regen, float(def["shield_delay"]), true)
	vision_radius = float(def["vision"])
	move_speed = float(def["move_speed"])
	# Step 4: physics. collision_layer is a "bitmask" (a number whose binary
	# digits are on/off switches): 4 switches on physics layer 3, the
	# "structures" layer that pilot ships bump into. The mask is 0: the
	# mothership itself never checks for bumps.
	collision_layer = 4
	collision_mask = 0
	# The collision shape is a capsule as long as the hull. Godot's capsules
	# stand upright, so it is turned a quarter turn (PI / 2) to lie along
	# our nose.
	var cs := get_node_or_null("Shape") as CollisionShape2D
	if cs != null:
		var cap := CapsuleShape2D.new()
		cap.radius = beam * 0.5
		cap.height = float(def["length"])
		cs.shape = cap
		cs.rotation = PI / 2.0
	# Step 5: the guns we start with.
	MothershipGuns.add_base_mounts(self)


## The arrow from the centre to the bow end of the keel line: the nose
## direction times half_len. It is asked for very often (every distance to
## the hull needs it), but it only changes when the ship turns, so the
## answer is kept and worked out again only when `rotation` or `half_len`
## differs from the ones it was made for. The result is the very same number
## that Vector2.from_angle(rotation) * half_len gives each time.
func keel_arrow() -> Vector2:
	if rotation != _keel_rot or half_len != _keel_len:
		_keel_rot = rotation
		_keel_len = half_len
		_keel_f = Vector2.from_angle(rotation) * half_len
	return _keel_f


## How far point `p` is from the hull's surface, in world units (negative
## inside the hull).
## Forwarding function: the real code is MothershipHull.dist().
func hull_dist(p: Vector2) -> float:
	return MothershipHull.dist(self, p)


## Hit test for a fast round or a beam going from `a` to `b` in one step,
## against our long hull: returns how far along that line it first touches
## us (0..1), or -1 for a miss (see Unit.hit_t). Replaces Unit's circle
## test.
## Forwarding function: the real code is MothershipHull.hit_t().
func hit_t(a: Vector2, b: Vector2, pad: float) -> float:
	return MothershipHull.hit_t(self, a, b, pad)


## How close to the hull (world units from its surface) a pilot ship must
## be to dock (520 with the current data).
func dock_radius() -> float:
	return float(def["dock_radius"])


## Where launched ships appear: 160 world units past the tip of the bow, in
## one of 5 side-by-side spots 90 apart (slot 2 is the middle one; `slot`
## wraps around every 5). MinionDirector launches minions from a random
## spot, WorldSpawner sends wards from spot 1 and repair bays from spot 2,
## and WorldHangar launches each pilot from their seat number's spot.
## `ship_radius` is the radius of the pilot ship that launches (0 for the
## others): a hull whose radius plus 20 is more than 160 is placed that far
## out instead, so a big ship clears the bow instead of appearing inside it.
func launch_point(slot: int, ship_radius: float = 0.0) -> Vector2:
	# `f` points ahead along our nose, `side` to our right (starboard).
	var f := Vector2.from_angle(rotation)
	var side := Util.starboard_of(rotation)
	var lane := float((slot % 5) - 2) * 90.0
	var gap := maxf(160.0, ship_radius + 20.0)
	return global_position + f * (half_len + beam * 0.5 + gap) + side * lane


## True when pilots can launch, respawn and shop here: alive, with no
## systems failure.
func available() -> bool:
	return alive and failure_t <= 0.0


## True when the admiral may move us: from 20:00 on.
## Forwarding function: the real code is MothershipDrive.can_move().
func can_move() -> bool:
	return MothershipDrive.can_move(self)


## Start moving to `p` along `path` (route map points that use only
## big-ship links, so it follows the lanes instead of ploughing through the
## jungle). AdmiralCommand calls it.
## Forwarding function: the real code is MothershipDrive.order_move().
func order_move(p: Vector2, path: PackedVector2Array = PackedVector2Array()) -> void:
	MothershipDrive.order_move(self, p, path)


## Rebuild guns, hull and shield from team `ts`'s Flagship research. Safe
## to call again: it only adds what is new. The research code (TeamTech)
## calls it whenever research finishes; tests call it too.
## Forwarding function: the real code is MothershipGuns.apply_upgrades().
func apply_upgrades(ts: TeamState) -> void:
	MothershipGuns.apply_upgrades(self, ts)


## One tick of `dt` seconds: the hit flash, the emergency timers, the
## shield refill, the guns and the engines. World calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	var ts: TeamState = world.teams[team]
	# Step 1: the emergency timer (MothershipRetreat).
	MothershipRetreat.update(self, dt)
	# Step 2: the shield refills, unless respawn strain is on.
	var regen := 0.0 if ts.strain_t > 0.0 else 1.0
	shields.tick(dt, regen)
	# Step 3: the guns take their turn, then the engines.
	MothershipGuns.fire(self, ts, dt)
	MothershipDrive.move(self, dt)


## Combat.kill() calls this when we die: a huge explosion, then MatchRules
## ends the match (the other team wins).
func on_killed(info: DamageInfo) -> void:
	world.effects.explosion(global_position, 900.0, Palette.team(team))
	world.rules.on_mothership_destroyed(self, info)
