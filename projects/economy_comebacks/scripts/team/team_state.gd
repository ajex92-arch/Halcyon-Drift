class_name TeamState
extends RefCounted
## WHAT THIS IS: one team's shared notebook. Everything that belongs to a
## whole side, not to one ship or one pilot, is kept here: the team's
## money (the treasury), its tech tree (facilities and research) and the
## upgrades research has given, who sits in the admiral's seat, the rally
## waypoint, the late-game siege and the "defend the base!" call, respawn
## strain, the mining-drone build line, and a few numbers for the end
## screen. DESIGN.md A7, A12, A13.
##
## HOW IT WORKS: there are two of these, one per team (World.teams). Every
## tick (one small step of the game clock; `dt` is its length in seconds)
## World calls tick(), which does, in this order:
##   1. once a second, look for enemy big ships attacking our mothership,
##      and if they are, call our pilots home to defend (TeamDefense);
##   2. count down respawn strain (TeamStrain);
##   3. stop there if our mothership is destroyed. Otherwise add the
##      mothership's own income to the treasury
##      (Rules.MOTHERSHIP_SKIM, 3 credits per second), move the facility
##      and research queues on (TeamTech), and build mining drones
##      (TeamDrones).
## The variables all live here, because many files read and write them
## directly (ts.treasury, ts.siege_lane, ts.turret_armor ...). The real
## work is done by "part" objects, one per job, that each keep a link back
## to this notebook:
##   TeamTech     the tech tree: what may be queued, paying, progress, and
##                turning finished research into upgrades
##   TeamSiege    where our big ships gather and attack during a siege
##   TeamDefense  the "all pilots defend the mothership!" call
##   TeamStrain   respawn strain (too many respawns in a short time)
##   TeamDrones   the mining-drone build line and where drones died
## A function below that only calls a part says so ("the real code is
## ..."); it stays here so other files can keep calling it on TeamState.
##
## WHO USES IT: WorldSetup makes the two teams, and World's tick loop calls
## tick(). Admiral orders that cost money go through AdmiralCommand, which
## checks them and then calls queue_facility(), queue_research() or
## spend(); the AI admiral's parts read this notebook, and AdmiralSiege
## writes the siege fields. AI pilots (PilotAI, PilotGoals, PilotShopping)
## read the siege, defend and waypoint fields. Ships, turrets, wards,
## repair bays, mining drones, the mothership and the minion spawners read
## the upgrade fields. Economy pays into the treasury and counts the stats;
## MatchRules calls note_respawn(); MiningDrone calls note_drone_loss().
## The admiral board, HUD, minimap and end screen show it all.

# --- who we are -----------------------------------------------------------------

## Which side this is: 0 = Halcyon, 1 = Cinder (Rules.TEAM_NAMES).
var team := 0
## The game world (ships, motherships, ore nodes, the match clock).
var world: World = null
## The team's shared money, in credits. It starts at Rules.START_TREASURY
## (1,500). Mining, the mothership's income and destroyed enemy turrets and
## repair bays add to it; the admiral spends it.
var treasury := Rules.START_TREASURY
## Feature hook (fork economy_comebacks): when set, spend() calls it with
## the amount after every successful spend. Not set (the default) = no call.
var spend_hook := Callable()
## Fleet Doctrine levels finished (DoctrineFeature, 0..10). Each level gives
## our pilot ships +2% max hull and +3% shield regeneration (ShipStats). 0 =
## no doctrine, the normal game.
var doctrine_level := 0
## Who sits in the admiral's seat: "ai" or "human".
var admiral := "ai"
## False while a human admiral is out flying their own ship.
var admiral_docked := true

# --- tech tree (the real code is in TeamTech) -----------------------------------

## Facilities (modules built onto the mothership) we own: id -> true. We
## start with Tech.START_FACILITIES (the Fighter Facility).
var facilities := {}
## Research we have finished: tech id -> true.
var done := {}
## Facilities queued to be built, in order: 2 at most, and only the first
## one makes progress. Each entry is {"id", "left" (seconds still to go),
## "total" (seconds it takes in all)}.
var building: Array = []
## Research queued, in order: 3 at most, and only the first one makes
## progress (and only while we own the Research Module). Each entry looks
## like the ones in `building`.
var research: Array = []

# --- upgrades from research (TeamTech.apply_effect adds to these) ---------------
# "A fraction" below means a bonus where 0.25 = +25%.

## Drive upgrades researched per ship tier ("small", "medium", "large",
## "capital") -> how many. Read through drive_level().
var drive := {"small": 0, "medium": 0, "large": 0, "capital": 0}
## Armor upgrades researched per ship tier -> how many (armor_level()).
var armor := {"small": 0, "medium": 0, "large": 0, "capital": 0}
## Extra damage for our ships' torpedo guns, as a fraction (Improved Bombs
## research; Ship reads it).
var torp_dmg := 0.0
## True = a Scout's ping also stalls nearby enemy engines (ShipAbilities).
var scout_emp := false
## True = the admiral may launch repair bays.
var repair_bays := false
## How many repair drones each repair bay carries (starts at 1).
var bay_drones := 1
## True = repair bays get a shield and a point-defense gun.
var bay_defenses := false
## Extra mining-drone hull, as a fraction.
var drone_armor := 0.0
## Extra ore each mining drone carries per trip, as a fraction.
var mining_capacity := 0.0
## Credits every pilot gets each time they respawn (MatchRules pays it).
var stipend := 0.0
## True = torpedo turrets may be built.
var turret_torp := false
## Extra turret hull, as a fraction.
var turret_armor := 0.0
## Extra weapon range for all our ships, turrets and our mothership, as a
## fraction.
var team_range := 0.0
## True = our wards see 40% farther.
var ward_upgrade := false
## Extra mothership hull, as a fraction (it also adds a little damage
## resistance; Mothership.apply_upgrades).
var ms_hull := 0.0
## Extra mothership shields and shield regeneration, as a fraction.
var ms_shield := 0.0
## Extra point-defense guns on the mothership (a count).
var ms_pd := 0
## Flak batteries on the mothership (a count).
var ms_flak := 0
## Heavy cannon batteries on the mothership (a count).
var ms_heavy := 0
## Ion lances on the mothership (a count).
var ms_ion := 0
## Extra hull and damage for our minions, as a fraction (Reinforced Waves
## research; WorldSpawner uses it).
var minion_buff := 0.0
## Extra escort corvettes per lane in every free minion wave (Escort Wing
## research; MinionDirector uses it). With --variant=escort_wing:upgrade
## no corvette is added: above 0 it means each wave's own corvette is
## upgraded instead (EscortWingFeature).
var wave_corvettes := 0

# --- waypoint -------------------------------------------------------------------

## Where the admiral's rally waypoint is (Vector2.INF = never set).
var waypoint := Vector2.INF
## Match time (seconds) when the waypoint runs out.
var waypoint_until := 0.0

# --- siege and defend (the real code is in TeamSiege and TeamDefense) -----------

## Late-game siege: the lane ("top", "mid" or "bot") our fleet (every ship
## bigger than a strike craft, plus bombers) gathers on to attack the enemy
## mothership; "" = no siege. Set by the AI
## admiral's siege plan (AdmiralSiege) or by any admiral's waypoint near
## the enemy mothership (AdmiralCommand.set_waypoint); TeamDefense calls it
## off when our own base is attacked. The AI pilots read it.
var siege_lane := ""
## The siege's phase: "gather" (mass at a staging point part-way down the
## lane, so the slow capital ships arrive together), then "assault" (close
## on the enemy mothership); "" = no siege.
var siege_phase := ""
## Match time (seconds) when the current siege phase began. AdmiralSiege
## sets it and uses it to end a long gather or spot a stalled assault.
var siege_t := 0.0
## Defend: while enemy big ships attack our mothership, every AI pilot
## nearby comes to fight at this point (Vector2.INF = never set). Set by
## TeamDefense.update() until defend_until; PilotGoals reads it.
var defend_point := Vector2.INF
## Match time (seconds) when the defend call runs out.
var defend_until := 0.0

# --- respawn strain (the real code is in TeamStrain) ----------------------------

## Match times (seconds) of recent pilot respawns. Times older than
## Rules.STRAIN_WINDOW (30 s) are dropped at each new respawn.
var respawn_log: Array[float] = []
## Seconds of respawn strain left (0 = none). While it is above 0 the
## mothership's guns are slowed and its shields don't recharge.
var strain_t := 0.0

# --- mining drones (the real code is in TeamDrones) -----------------------------

## Mining drones paid for and waiting to be built, in order. Each entry is
## the ore node id the drone should work, or "" to let it choose each trip.
var drone_queue: Array[String] = []
## Seconds until the drone at the front of the queue is finished.
var drone_t := 0.0
## Seconds until the mothership builds a free drone. It only counts down
## while we have fewer than 3 drones (living plus queued).
var free_drone_t := 0.0
## How many of our mining drones have been destroyed this match.
var drones_lost := 0
## Where our drones died: ore node id -> [the match time (seconds) of each
## loss there]. Mining drones avoid nodes where drones keep dying
## (World.best_node_for_drone asks drone_danger()).
var drone_loss_log := {}

# --- stats for the end screen and tests -----------------------------------------

## All the ore our drones have brought home (1 ore is worth 1 credit).
var ore_delivered := 0.0
## Enemy ships our pilots destroyed (a pilot of ours made the last hit).
var kills := 0
## Enemy turrets our side destroyed.
var turrets_destroyed := 0
## When each facility and research finished: id -> match time (seconds).
var unlock_times := {}

# --- the parts (made in _init) --------------------------------------------------

## The tech-tree part (team_tech.gd).
var tech: TeamTech
## The siege-points part (team_siege.gd).
var siege: TeamSiege
## The home-defence part (team_defense.gd).
var defense: TeamDefense
## The respawn-strain part (team_strain.gd).
var strain: TeamStrain
## The mining-drone part (team_drones.gd): the build line and the memory of
## where drones died.
var drone_line: TeamDrones


## Set up team `t` in world `w`. We start owning Tech.START_FACILITIES (the
## Fighter Facility), and the free-drone clock starts at
## Structures.MINING_DRONE "free_every" (20 s). Then we make our parts.
func _init(t: int, w: World) -> void:
	team = t
	world = w
	# The facilities every team starts with.
	for f: String in Tech.START_FACILITIES:
		facilities[f] = true
	free_drone_t = float(Structures.MINING_DRONE["free_every"])
	# Make the parts. Each one keeps a link back to this notebook.
	tech = TeamTech.new(self)
	siege = TeamSiege.new(self)
	defense = TeamDefense.new(self)
	strain = TeamStrain.new(self)
	drone_line = TeamDrones.new(self)


# --- money ----------------------------------------------------------------------

## Do we have `amount` credits? (A tiny 0.001 slack, so rounding never
## blocks a purchase we can exactly afford.)
func can_afford(amount: float) -> bool:
	return treasury >= amount - 0.001


## Pay `amount` credits from the treasury. Returns false, and pays
## nothing, if we can't afford it.
func spend(amount: float) -> bool:
	if not can_afford(amount):
		return false
	treasury -= amount
	# Feature hook (fork economy_comebacks): a function f(amount) told about
	# every spend. Not set (the default) = nothing happens.
	if spend_hook.is_valid():
		spend_hook.call(amount)
	return true


# --- tech (each of these forwards to TeamTech) ----------------------------------

## All research finished or queued: tech id -> true. The real code is
## TeamTech.planned_tech().
func planned_tech() -> Dictionary:
	return tech.planned_tech()


## Is facility `id` in the build queue? The real code is
## TeamTech.is_building().
func is_building(id: String) -> bool:
	return tech.is_building(id)


## Is research `id` in the research queue? The real code is
## TeamTech.is_researching().
func is_researching(id: String) -> bool:
	return tech.is_researching(id)


## "" if facility `id` can be queued now (cost not checked), else why not.
## The real code is TeamTech.facility_blocker().
func facility_blocker(id: String) -> String:
	return tech.facility_blocker(id)


## "" if research `id` can be queued now (cost not checked), else why not.
## The real code is TeamTech.tech_blocker().
func tech_blocker(id: String) -> String:
	return tech.tech_blocker(id)


## Queue facility `id` and pay for it from the treasury. Returns "" or the
## reason it failed. The real code is TeamTech.queue_facility().
func queue_facility(id: String) -> String:
	return tech.queue_facility(id)


## Queue research `id` and pay for it from the treasury. Returns "" or the
## reason it failed. The real code is TeamTech.queue_research().
func queue_research(id: String) -> String:
	return tech.queue_research(id)


## May our pilots buy hull `ship_id`? The real code is
## TeamTech.ship_unlocked().
func ship_unlocked(ship_id: String) -> bool:
	return tech.ship_unlocked(ship_id)


## Every hull our pilots may buy, in Ships.ORDER order. The real code is
## TeamTech.unlocked_ships().
func unlocked_ships() -> Array:
	return tech.unlocked_ships()


## How many Drive upgrades we have for ship tier `tier`. The real code is
## TeamTech.drive_level().
func drive_level(tier: String) -> int:
	return tech.drive_level(tier)


## How many Armor upgrades we have for ship tier `tier`. The real code is
## TeamTech.armor_level().
func armor_level(tier: String) -> int:
	return tech.armor_level(tier)


## Add one research `effect` (Tech.TECHS[id]["effect"]) to our upgrade
## fields. The real code is TeamTech.apply_effect().
func apply_effect(effect: Dictionary) -> void:
	tech.apply_effect(effect)


# --- siege and defend (forwarding to TeamSiege and TeamDefense) -----------------

## Where the enemy mothership is now, measured along our copy of `lane`:
## {"s" (how far along the lane, in world units), "point" (the nearest
## point on the lane), "dist" (how far it is off the lane)}. The real code
## is TeamSiege.enemy_ms_on_lane().
func enemy_ms_on_lane(lane: String) -> Dictionary:
	return siege.enemy_ms_on_lane(lane)


## The siege staging point on `lane` (where big ships gather first). The
## real code is TeamSiege.stage_point().
func siege_stage_point(lane: String) -> Vector2:
	return siege.stage_point(lane)


## The siege assault rally point on `lane` (close to the enemy mothership).
## The real code is TeamSiege.assault_point().
func siege_assault_point(lane: String) -> Vector2:
	return siege.assault_point(lane)


## Is the "defend the mothership!" call on at match time `now` (seconds)?
## The real code is TeamDefense.defending().
func defending(now: float) -> bool:
	return defense.defending(now)


# --- waypoint -------------------------------------------------------------------

## Put the rally waypoint at `p` for Rules.WAYPOINT_TIME (75 s).
## AdmiralCommand.set_waypoint() calls this, for human and AI admirals.
func set_waypoint(p: Vector2) -> void:
	waypoint = p
	waypoint_until = world.time + Rules.WAYPOINT_TIME


## Is a waypoint set, and not run out yet?
func has_waypoint() -> bool:
	return waypoint != Vector2.INF and world.time < waypoint_until


## Is point `p` inside the live waypoint's circle (Rules.WAYPOINT_RADIUS,
## 1,200 units)? Our ships there get the waypoint bonuses (ShipStats).
func in_waypoint(p: Vector2) -> bool:
	return has_waypoint() and p.distance_to(waypoint) < Rules.WAYPOINT_RADIUS


# --- respawn strain (forwarding to TeamStrain) ----------------------------------

## A pilot of ours just respawned (minions don't count). Many respawns in a
## short time strain the mothership. MatchRules calls this. The real code
## is TeamStrain.note_respawn().
func note_respawn() -> void:
	strain.note_respawn()


# --- tick -----------------------------------------------------------------------

## One tick for this team; `dt` is the tick's length in seconds. World's
## tick loop calls it for both teams. The order of the steps is part of
## how the game behaves, so keep it.
func tick(dt: float) -> void:
	# Step 1: once a second, check whether enemy big ships are attacking
	# our mothership (TeamDefense).
	defense.tick(dt)
	var ms: Mothership = world.mothership(team)
	# Step 2: count down respawn strain (even while the mothership is gone).
	strain.tick(dt)
	# Step 3: no income, building or research while our mothership is
	# destroyed.
	if ms == null or not ms.alive:
		return
	# Step 4: the mothership's own income, in credits per second (a tuned
	# number: a feature module may change it, see Rules.tune).
	treasury += float(Rules.tune("mothership_skim", Rules.MOTHERSHIP_SKIM)) * dt
	# Step 5: move the facility and research queues on (TeamTech).
	tech.tick(dt, ms)
	# Step 6: build mining drones (TeamDrones).
	_drone_line(dt)


# --- mining drones (forwarding to TeamDrones) -----------------------------------

## One of our mining drones was destroyed while working node `node_id`, at
## match time `now` (seconds). MiningDrone calls this. The real code is
## TeamDrones.note_drone_loss().
func note_drone_loss(node_id: String, now: float) -> void:
	drone_line.note_drone_loss(node_id, now)


## How many of our drones were lost at node `node_id` in the last `window`
## seconds (150 unless told otherwise). The real code is
## TeamDrones.danger().
func drone_danger(node_id: String, now: float, window: float = 150.0) -> int:
	return drone_line.danger(node_id, now, window)


## Build mining drones for one tick of `dt` seconds: free ones when we are
## short, and the ones the admiral ordered. The real code is
## TeamDrones.tick().
func _drone_line(dt: float) -> void:
	drone_line.tick(dt)
